# frozen_string_literal: true

require 'rails_helper'

# 운영진이 여는 모집형 이벤트 (미로·도둑 지도·비행 대결, 비밀의 방): 모집 툿(전체 멘션) → [참가] → 시간이 끝나면 시작
RSpec.describe Game::Events::Opening do
  let!(:system) { Fabricate(:account, username: 'system') }
  let(:admin) { Fabricate(:account, username: 'professor') }
  let(:accounts) { %w(harry ron hermione draco).map { |name| Fabricate(:user, account: Fabricate(:account, username: name)).account } }

  before do
    allow(Game::System).to receive(:account).and_return(system)
    Game::Config.merge!('marauders_map', 'event_min_players' => '2')
    accounts.each { |account| GameCharacter.for(account) }
  end

  def toot(account, text)
    status = PostStatusService.new.call(account, text: text, visibility: 'private')
    Game::Engine.new(status).call
    status
  end

  def event_session(key)
    GameSession.where(kind: key).order(:id).last.reload
  end

  def finish_recruiting!(key)
    session = event_session(key)
    session.with_lock { session.kind_class.new(session).recruitment_over! }
    event_session(key)
  end

  it 'opens a recruiting event that mentions every character' do
    session = described_class.open!(Game::Web::Maze, admin)

    expect(session).to have_attributes(status: 'pending', visibility: 'private')
    expect(session.state['mode']).to eq 'event'
    expect(session.deadline_at).to be_present
    root = Status.find(session.root_status_id)
    expect(root.account).to eq system
    expect(root.text).to include('트라이위저드 미로가 열렸습니다', '[참가]')
    expect(root.mentions.map(&:account_id)).to include(*accounts.map(&:id))
  end

  describe 'picking the players' do
    def join_by_toot(account, visibility: 'private')
      status = PostStatusService.new.call(account, text: '@system [참가]', visibility: visibility)
      Game::Engine.new(status).call
    end

    it 'sends a participation DM to each picked player only and starts when they all accept, with progress on the web only' do
      picked = accounts.first(3)
      session = described_class.open!(Game::Web::Maze, admin, mode: 'pick', players: picked)

      expect(session).to have_attributes(status: 'pending', visibility: 'private')
      expect(session.test?).to be false
      invites = Status.where(account: system, visibility: :direct).to_a
      expect(invites.flat_map { |status| status.mentions.map(&:account_id) }).to match_array(picked.map(&:id))
      expect(invites.first.text).to include('참가자로 뽑혔습니다', '[참가]')

      join_by_toot(accounts.last) # 고르지 않은 사람은 못 낀다
      expect(session.reload.players).to be_empty
      expect(system.statuses.reorder(:id).last.text).to include('고른 참가자만')

      picked.first(2).each { |account| join_by_toot(account) }
      expect(session.reload.status).to eq 'pending'
      before = Status.maximum(:id).to_i
      join_by_toot(picked.last)

      expect(session.reload).to have_attributes(status: 'active')
      expect(session.players.map(&:account_id)).to match_array(picked.map(&:id))
      expect(Status.where(account: system).where('id > ?', before).where.not(visibility: :direct).count).to be <= 1 # 마지막 참가 확인 답장뿐 (진행은 웹 메시지)
      expect(session.messages.count).to be_positive
    end

    it 'starts with the ones who accepted when the time is up, and cancels when too few did' do
      picked = accounts.first(3)
      session = described_class.open!(Game::Web::Maze, admin, mode: 'pick', players: picked)
      join_by_toot(picked.first)
      session.with_lock { session.kind_class.new(session).recruitment_over! }
      expect(session.reload.status).to eq 'cancelled'

      session = described_class.open!(Game::Web::Maze, admin, mode: 'pick', players: picked)
      picked.first(2).each { |account| join_by_toot(account) }
      session.with_lock { session.kind_class.new(session).recruitment_over! }
      expect(session.reload.status).to eq 'active'
      expect(session.players.size).to eq 2
    end

    it 'refuses too few or too many players and a content that cannot be opened as an event' do
      expect { described_class.open!(Game::Web::Maze, admin, mode: 'pick', players: accounts.first(1)) }.to raise_error(described_class::Error, /2명 이상/)
      expect { described_class.open!(Game::Kinds::Quidditch, admin, mode: 'pick', players: accounts) }.to raise_error(described_class::Error, /이벤트로 열 수 없습니다/)
      expect(GameSession.where(kind: 'maze').count).to eq 0
    end

    it 'plays a hidden test: DM invites, nothing in lists, no points, rewards or records, and nothing posted as toots' do
      picked = accounts.first(2)
      session = described_class.open!(Game::Web::Maze, admin, mode: 'test', players: picked)

      expect(session).to have_attributes(status: 'pending', visibility: 'direct')
      expect(session.test?).to be true
      expect(GameSession.real).to_not include(session)
      invites = Status.where(account: system, visibility: :direct).to_a
      expect(invites.flat_map { |status| status.mentions.map(&:account_id) }).to match_array(picked.map(&:id))
      expect(invites.first.text).to include('테스트 플레이', '보상이 존재하지 않습니다')

      picked.each { |account| join_by_toot(account, visibility: 'direct') }
      expect(session.reload.status).to eq 'active'
      before = Status.maximum(:id).to_i

      expect { Game::Web::Maze.new(session).send(:finish!, winner: session.players.first) }.to_not(change { [GameReward.count, GameHousePoint.count] })
      expect(session.reload.status).to eq 'finished'
      expect(Status.where(account: system).where('id > ?', before).count).to eq 0
      expect(session.messages.order(:id).last.text).to include('테스트 플레이라 점수와 보상은 없습니다')
    end
  end

  it 'allows only one event at a time and refuses a turned-off content' do
    described_class.open!(Game::Web::Maze, admin)

    expect { described_class.open!(Game::Kinds::Flying, admin) }.to raise_error(described_class::Error, /이미 모집 중/)
  end

  it 'cancels when too few people joined' do
    described_class.open!(Game::Web::Maze, admin)
    toot(accounts.first, '@system [참가]')

    expect(finish_recruiting!('maze').status).to eq 'cancelled'
  end

  it 'starts the maze with everyone who joined' do
    described_class.open!(Game::Web::Maze, admin)
    accounts.first(3).each { |account| toot(account, '@system [참가]') }
    toot(accounts.first, '@system [참가]') # 두 번 참가해도 한 번

    session = finish_recruiting!('maze')

    expect(session.status).to eq 'active'
    expect(session.players.map(&:account_id)).to match_array(accounts.first(3).map(&:id))
    expect(session.state['positions']).to be_present
  end

  it 'starts a flying race for the people who joined' do
    described_class.open!(Game::Kinds::Flying, admin)
    accounts.first(2).each { |account| toot(account, '@system [참가]') }

    expect(finish_recruiting!('flying').status).to eq 'active'
  end

  it 'deals the map roles at random: a student team no bigger than the prefect team' do
    described_class.open!(Game::Web::MaraudersMap, admin)
    accounts.each { |account| toot(account, '@system [참가]') }

    session = finish_recruiting!('marauders_map')

    expect(session.status).to eq 'active'
    expect(session.players.map(&:seat)).to eq [0, 1, 2, 3]
    students = session.state['student_count']
    expect(students).to be_between(1, 2)
    expect(session.state['positions'].values_at(*(0...students).map(&:to_s)).uniq.size).to eq 1
  end

  it 'stops accepting people at the maximum' do
    Game::Config.merge!('maze', 'event_max_players' => '2')
    described_class.open!(Game::Web::Maze, admin)
    accounts.first(3).each { |account| toot(account, '@system [참가]') }

    expect(event_session('maze').players.size).to eq 2
  end
end
