# frozen_string_literal: true

require 'rails_helper'

# 운영진이 여는 모집형 이벤트 (미로·도둑 지도·비행 대결, 비밀의 방): 모집 툿(전체 멘션) → [참가] → 시간이 끝나면 시작
RSpec.describe Game::Events::Opening do
  let!(:system) { Fabricate(:account, username: 'system') }
  let(:admin) { Fabricate(:admin_user, account: Fabricate(:account, username: 'professor')).account }
  let(:member) { accounts.last }
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

  # 모집이 끝나면 대기방이 열린다 → 모두 준비해 카운트다운이 끝난 것처럼 시작한다
  def finish_recruiting!(key)
    session = event_session(key)
    session.with_lock { session.kind_class.new(session).recruitment_over! }
    session = event_session(key)
    Game::Lobby.start!(session) if session.lobby?
    event_session(key)
  end

  it 'opens a recruiting event with a recruiting toot that tags nobody' do
    session = described_class.open!(Game::Web::Maze, admin)

    expect(session).to have_attributes(status: 'pending', visibility: 'private')
    expect(session.state['mode']).to eq 'event'
    expect(session.deadline_at).to be_present
    root = Status.find(session.root_status_id)
    expect(root.account).to eq system
    expect(root.text).to include('트라이위저드 미로가 열렸습니다', '[참가]')
    expect(root.mentions).to be_empty # 모집 툿은 아무도 태그하지 않는다 (알림은 웹 이벤트 메뉴 배지)
    expect(root.text).to_not include('@')
    expect(GameNotice.exists?(status_id: root.id)).to be true # 모집 툿은 웹에서도 숨기지 않는 안내
  end

  it 'lets only staff open events unless the event settings let everyone, and then only the allowed kinds of opening' do
    expect { described_class.open!(Game::Web::Maze, member) }.to raise_error(described_class::Error, /열 수 있는 사람이 아닙니다/)

    Game::Config.merge!('events', 'event_open_by' => 'everyone', 'event_open_invite' => false)
    expect { described_class.open!(Game::Web::Maze, member, mode: 'pick', players: accounts.first(2)) }.to raise_error(described_class::Error, /열 수 있는 사람이 아닙니다/)
    expect { described_class.open!(Game::Web::Maze, member, mode: 'test', players: accounts.first(2)) }.to raise_error(described_class::Error, /열 수 있는 사람이 아닙니다/)
    expect { described_class.open!(Game::Web::Maze, member) }.to_not raise_error
  end

  it 'posts no toot when a character (not staff) opens a recruitment, but still rings every other character' do
    Game::Config.merge!('events', 'event_open_by' => 'everyone')
    expect(Game::EventNotice).to receive(:alert!).with(match_array(accounts.first(3).map(&:id)))

    session = described_class.open!(Game::Web::Maze, member)

    expect(session.root_status_id).to be_nil
    expect(Status.where(account: system)).to be_empty
  end

  it 'rings the badge of every other character when staff opens a recruitment' do
    expect(Game::EventNotice).to receive(:alert!).with(match_array(accounts.map(&:id)))

    described_class.open!(Game::Web::Maze, admin)
  end

  describe 'picking the players' do
    def join_by_toot(account, visibility: 'private')
      status = PostStatusService.new.call(account, text: '@system [참가]', visibility: visibility)
      Game::Engine.new(status).call
    end

    it 'rings only the picked players, sends no toot or DM and starts when they all accept, with progress on the web only' do
      picked = accounts.first(3)
      expect(Game::EventNotice).to receive(:alert!).with(match_array(picked.map(&:id))).and_call_original
      session = described_class.open!(Game::Web::Maze, admin, mode: 'pick', players: picked)

      expect(session).to have_attributes(status: 'lobby', visibility: 'private') # 초대하면 모집 없이 바로 대기방
      expect(session.test?).to be false
      expect(Status.where(account: system)).to be_empty # 초대는 툿도 DM 도 없다 (이벤트 메뉴 알림 배지만)

      join_by_toot(accounts.last) # 고르지 않은 사람은 못 낀다
      expect(session.reload.players).to be_empty
      expect(Status.where(account: system)).to be_empty # 답장도 없다 (웹에서는 모달로 안내)

      picked.first(2).each { |account| join_by_toot(account) }
      expect(session.reload.status).to eq 'lobby'
      before = Status.maximum(:id).to_i
      join_by_toot(picked.last)

      expect(session.reload).to have_attributes(status: 'lobby') # 모두 수락해도 준비하고 카운트다운이 끝나야 시작
      expect(session.players.map(&:account_id)).to match_array(picked.map(&:id))
      Game::Lobby.start!(session)
      expect(session.reload.status).to eq 'active'
      expect(Status.where(account: system).where('id > ?', before).where.not(visibility: :direct).count).to eq 0 # 참가 확인 답장도 없다 (진행은 웹 메시지)
      expect(session.messages.count).to be_positive
    end

    it 'waits for every invited player to answer; a decline lets the rest start' do
      picked = accounts.first(3)
      session = described_class.open!(Game::Web::Maze, admin, mode: 'pick', players: picked)
      picked.first(2).each { |account| Game::Lobby.accept_invite!(session.reload, account) }
      picked.first(2).each { |account| Game::Lobby.set_ready!(session.reload, account, true) }
      expect(Game::Lobby.counting?(session.reload)).to be_falsey # 아직 답하지 않은 사람이 있다

      Game::Lobby.decline_invite!(session.reload, picked.last)
      expect(Game::Lobby.counting?(session.reload)).to be true
      expect(session.players.size).to eq 2
    end

    it 'refuses too few or too many players and a content that cannot be opened as an event' do
      expect { described_class.open!(Game::Web::Maze, admin, mode: 'pick', players: accounts.first(1)) }.to raise_error(described_class::Error, /2명 이상/)
      expect { described_class.open!(Game::Kinds::Jellybean, admin, mode: 'pick', players: accounts) }.to raise_error(described_class::Error, /이벤트로 열 수 없습니다/)
      expect(GameSession.where(kind: 'maze').count).to eq 0
    end

    it 'plays a hidden test: DM invites, nothing in lists, no points, rewards or records, and nothing posted as toots' do
      picked = accounts.first(2)
      session = described_class.open!(Game::Web::Maze, admin, mode: 'test', players: picked)

      expect(session).to have_attributes(status: 'lobby', visibility: 'direct')
      expect(session.test?).to be true
      expect(GameSession.real).to_not include(session)
      expect(Status.where(account: system)).to be_empty

      picked.each { |account| join_by_toot(account, visibility: 'direct') }
      expect(session.reload.status).to eq 'lobby'
      Game::Lobby.start!(session)
      expect(session.reload.status).to eq 'active'
      before = Status.maximum(:id).to_i

      expect { Game::Web::Maze.new(session).send(:finish!, winner: session.players.first) }.to_not(change { [GameReward.count, GameHousePoint.count] })
      expect(session.reload.status).to eq 'finished'
      expect(Status.where(account: system).where('id > ?', before).where.not('text LIKE ?', '%이벤트를 확인하세요%').count).to eq 0 # 종료 알림 DM 은 빼고
      expect(session.messages.order(:id).last.text).to include('테스트 플레이라 점수와 보상은 없습니다')
    end
  end

  it 'lets staff open several events at once, even the same content several times' do
    described_class.open!(Game::Web::Maze, admin)

    expect { described_class.open!(Game::Kinds::Flying, admin) }.to_not raise_error
    expect { described_class.open!(Game::Web::Maze, admin) }.to_not raise_error
    expect(GameSession.where(kind: 'maze').count).to eq 2
  end

  it 'lets one person join several events at a time when the concurrent limit is off, and caps the joins per day' do
    Game::Config.merge!('events', 'event_concurrent_limit' => false, 'event_daily_limit' => 2)
    described_class.open!(Game::Web::Maze, admin)
    described_class.open!(Game::Kinds::Flying, admin)
    described_class.open!(Game::Web::MaraudersMap, admin)
    toot(accounts.first, '@system [참가/maze]')
    toot(accounts.first, '@system [참가/flying]')
    toot(accounts.first, '@system [참가/marauders_map]')

    expect(GamePlayer.where(account: accounts.first).count).to eq 2
    expect(Status.where(account: system).count).to eq 3 # 모집 툿 3개뿐, 한도에 걸려도 답장은 없다
  end

  it 'limits a person to one event at a time but does not count 1:1 contents' do
    described_class.open!(Game::Web::Maze, admin)
    described_class.open!(Game::Kinds::Flying, admin)
    toot(accounts.first, '@system [참가/maze]')
    expect(GamePlayer.where(account: accounts.first).count).to eq 1

    toot(accounts.first, '@system [참가/flying]')
    expect(GamePlayer.where(account: accounts.first).count).to eq 1
    expect(GamePlayer.joins(:session).where(account: accounts.first, game_sessions: { kind: 'maze' }).count).to eq 1
  end

  it 'still lets a person join once the daily reward limit is reached, but tells them and gives no points or rewards' do
    Game::Config.merge!('events', 'event_daily_reward_limit' => 1)
    Game::Config.merge!('maze', 'event_min_players' => '2', 'points_win' => '5', 'reward_money_win' => '10')
    house = GameHouse.houses.first || GameHouse.create!(name: '그리핀도르', color: '#ae0001', category: 'house')
    accounts.each { |account| GameCharacter.for(account).update!(house: house) }
    earlier = GameSession.create!(kind: 'flying', status: 'finished', visibility: 'private', finished_at: Time.current, state: { 'mode' => 'event' })
    earlier.players.create!(account: accounts.first, seat: 0, result: 'win', state: {})

    described_class.open!(Game::Web::Maze, admin)
    session = event_session('maze')
    expect(Game::Lobby.reward_notice(accounts.first, session)).to include('점수와 보상을 받을 수 없습니다')
    expect(Game::Lobby.reward_notice(accounts.second, session)).to be_nil

    accounts.first(2).each { |account| session.players.create!(account: account, seat: session.players.count, state: { 'accepted' => true }) }
    Game::Lobby.enter!(session)
    Game::Lobby.start!(session.reload)
    Game::Web::Maze.new(session.reload).send(:finish!, winners: session.players.to_a, split_points: false)

    expect(GameCharacter.for(accounts.first).reload.money).to eq 0 # 보상 없음
    expect(GameCharacter.for(accounts.second).reload.money).to eq 10
    expect(GameHousePoint.where(account: accounts.first)).to be_empty
    expect(GameHousePoint.where(account: accounts.second).sum(:amount)).to eq 5
  end

  it 'tells the waiting room why a person cannot join (full, busy elsewhere, daily limit) while the button stays' do
    Game::Config.merge!('events', 'event_daily_limit' => 1)
    described_class.open!(Game::Web::Maze, admin)
    session = event_session('maze')
    allow(GameCharacter).to receive(:eligible_accounts).and_return(Account.where(id: accounts.map(&:id)))

    expect(Game::Lobby.view(session, accounts.first, staff: false)).to include(can_join: true, join_block: nil)

    earlier = GameSession.create!(kind: 'flying', status: 'finished', visibility: 'private', finished_at: Time.current, state: { 'mode' => 'event' })
    earlier.players.create!(account: accounts.first, seat: 0, result: 'win', state: {})
    expect(Game::Lobby.view(session, accounts.first, staff: false)).to include(can_join: true, join_block: '하루에 참가할 수 있는 이벤트 횟수를 넘었습니다.')

    Game::Config.merge!('events', 'event_daily_limit' => 0)
    earlier.update!(status: 'active')
    expect(Game::Lobby.view(session, accounts.first, staff: false)).to include(join_block: '이미 다른 이벤트에 참가 중입니다.')

    Game::Config.merge!('maze', 'event_max_players' => '2', 'event_min_players' => '2')
    accounts.last(2).each { |account| session.players.create!(account: account, seat: session.players.count, state: { 'accepted' => true }) }
    expect(Game::Lobby.view(session.reload, accounts.first, staff: false)).to include(can_join: true, join_block: '참가 인원이 가득 찼습니다.')
  end

  # 대기실은 모든 이벤트(미로·도둑 지도·비행 대결·비밀의 방)가 같은 규칙과 화면을 쓴다
  [Game::Web::Maze, Game::Web::MaraudersMap, Game::Kinds::Flying, Game::Web::SecretChamber].each do |kind|
    it "gives the #{kind.key} waiting room the same join limits, notices and invites" do
      Game::Config.merge!('events', 'event_daily_limit' => 1)
      allow(GameCharacter).to receive(:eligible_accounts).and_return(Account.where(id: accounts.map(&:id)))
      session = described_class.open!(kind, admin)
      session = GameSession.find(session.id)

      view = Game::Lobby.view(session, accounts.first, staff: false)
      expect(view).to include(can_join: true, join_block: nil, recruiting: true)
      expect(view.keys).to include(:can_invite, :join_block, :can_respond, :recruit_ends_at)

      earlier = GameSession.create!(kind: 'maze', status: 'finished', visibility: 'private', finished_at: Time.current, state: { 'mode' => 'event' })
      earlier.players.create!(account: accounts.first, seat: 0, result: 'win', state: {})
      expect(Game::Lobby.join!(session, accounts.first)).to eq :limit
      expect(Game::Lobby.view(session, accounts.first, staff: false)[:join_block]).to include('하루에 참가할 수 있는')

      Game::Config.merge!('events', 'event_daily_limit' => 0)
      expect(Game::Lobby.join!(session, accounts.first)).to eq :ok
      expect(Game::Lobby.reward_notice(accounts.first, session)).to be_nil
    end
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
    accounts.first(3).each { |account| toot(account, '@system [참가]') }

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
  describe 'notices' do
    def system_toots_since(id)
      Status.where(account: system).where('id > ?', id).order(:id).to_a
    end

    it 'sends no start, end, cancel or reply toots: only the staff recruiting toot exists, the rest is shown on the web' do
      Game::Config.merge!('maze', 'event_min_players' => '3')
      described_class.open!(Game::Web::Maze, admin)
      recruited = event_session('maze')
      expect(system_toots_since(0).size).to eq 1 # 모집 툿
      before = Status.maximum(:id).to_i

      toot(accounts.first, '@system [참가]') # 참가 확인 답장도 없다
      expect(recruited.reload.players.size).to eq 1
      recruited.with_lock { recruited.kind_class.new(recruited).recruitment_over! }

      expect(recruited.reload.status).to eq 'cancelled'
      expect(recruited.state['cancel_reason']).to include('3명이 되지 않아', '트라이위저드 미로')
      expect(system_toots_since(before)).to be_empty
    end

    it 'sends nothing when a recruited event starts or ends, or when an invited one starts' do
      Game::Config.merge!('maze', 'event_min_players' => '2')
      described_class.open!(Game::Web::Maze, admin)
      recruited = event_session('maze')
      accounts.first(2).each { |account| recruited.players.create!(account: account, seat: recruited.players.count, state: { 'accepted' => true }) }
      recruited.with_lock { recruited.kind_class.new(recruited).recruitment_over! }
      before = Status.maximum(:id).to_i
      Game::Lobby.start!(recruited.reload)
      recruited.reload.update!(status: 'finished', finished_at: Time.now.utc)

      invited = described_class.open!(Game::Kinds::Flying, admin, mode: 'pick', players: accounts.first(3))
      invited.reload.update!(status: 'active')
      expect(system_toots_since(before)).to be_empty
    end
  end
end
