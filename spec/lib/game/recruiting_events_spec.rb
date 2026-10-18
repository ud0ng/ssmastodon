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
