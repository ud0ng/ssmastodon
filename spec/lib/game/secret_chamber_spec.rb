# frozen_string_literal: true

require 'rails_helper'

# 비밀의방 (웹 전용, 마피아형): 운영진이 이벤트로 열어 모집하고, 시작한 뒤의 진행·안내는 툿이 아니라 웹 메시지(GameMessage)로만 간다
RSpec.describe Game::Web::SecretChamber do
  let!(:system) { Fabricate(:account, username: 'system') }
  let(:accounts) { %w(harry ron hermione draco neville luna ginny).map { |name| Fabricate(:account, username: name) } }
  let(:house) { GameHouse.create!(name: '그리핀도르', emoji: '🦁') }

  before do
    allow(Game::System).to receive(:account).and_return(system)
    accounts.each { |account| GameCharacter.for(account).update!(house: house) }
  end

  def toot(account, text, visibility: 'private')
    status = PostStatusService.new.call(account, text: text, visibility: visibility)
    Game::Engine.new(status).call
    status
  end

  def session
    GameSession.where(kind: 'secret_chamber').order(:id).last
  end

  def kind
    described_class.new(session.reload)
  end

  def player_with(role)
    session.reload.players.find { |player| session.state['roles'][player.seat.to_s] == role }
  end

  def players_without(role)
    session.reload.players.reject { |player| session.state['roles'][player.seat.to_s] == role }
  end

  # 웹에서 보낸 행동 (툿을 올리지 않는다). targets: [고발] @누구 처럼 고른 사람
  def act(account, command, args = [], targets: [])
    Game::WebCommand.play(session.reload, account, command, args, targets: targets)
  end

  def secret_texts_for(account)
    session.reload.messages.where(account: account).order(:id).map(&:text)
  end

  def open_event!
    Game::Events::Opening.open!(described_class, Fabricate(:admin_user, account: Fabricate(:account, username: 'professor')).account) # 운영진이 열어야 모집 툿이 나간다
  end

  def start_game!
    open_event!
    accounts.each { |account| toot(account, '@system [참가]') }
    session.with_lock { kind.recruitment_over! }
    expect(session.reload.status).to eq 'lobby' # 모집이 끝나면 대기방, 모두 준비하면 시작
    @before_start = Status.maximum(:id).to_i
    Game::Lobby.start!(session)
  end

  it 'recruits with a toot, then deals roles by web messages only and starts the first day' do
    start_game!

    expect(session).to have_attributes(status: 'active')
    expect(session.state).to include('phase' => 'day', 'day' => 1)
    expect(session.state['roles'].values.tally).to include('traitor' => 1, 'auror' => 1, 'healer' => 1, 'seer' => 1, 'student' => 3)
    # 시작한 뒤의 진행·역할 안내는 툿이 아니다 (앱에는 아무것도 안 나간다)
    expect(Status.where(account: system).where('id > ?', @before_start).where.not('text LIKE ?', '%이벤트를 확인하세요%').count).to eq 0 # 시작·종료 알림 툿은 빼고
    expect(session.messages.where.not(account_id: nil).count).to eq 7
    expect(session.messages.where(account_id: nil).last.payload['data']).to include('phase' => 'day', 'alive' => [0, 1, 2, 3, 4, 5, 6])
    expect(Status.find(session.root_status_id).text).to include('[참가]') # 모집은 툿
  end

  it 'keeps the roles staff set secretly in the lobby and deals the rest at random' do
    open_event!
    accounts.each { |account| toot(account, '@system [참가]') }
    session.with_lock { kind.recruitment_over! }
    harry, ron, hermione = session.players.order(:seat).first(3)
    expect(kind.preset_role!(harry, 'seer')).to eq :ok
    expect(kind.preset_role!(ron, 'traitor')).to eq :ok
    expect(kind.preset_role!(hermione, 'traitor')).to eq :ok
    expect(kind.preset_role!(hermione, 'wizard')).to eq :invalid
    expect(kind.lobby_roles_view[:picks]).to eq(harry.account_id.to_s => 'seer', ron.account_id.to_s => 'traitor', hermione.account_id.to_s => 'traitor')
    # 운영진만 보인다
    expect(Game::Lobby.view(session.reload, accounts.first, staff: false)[:roles]).to be_nil
    expect(Game::Lobby.view(session.reload, accounts.first, staff: true)[:roles][:options].pluck(:key)).to include('traitor', 'seer')
    # 무작위로 되돌리기
    expect(kind.preset_role!(hermione, '')).to eq :ok

    Game::Lobby.start!(session)
    roles = session.reload.state['roles']
    expect(roles[harry.seat.to_s]).to eq 'seer'
    expect(roles[ron.seat.to_s]).to eq 'traitor'
    expect(roles.values.tally).to include('traitor' => 1, 'seer' => 1, 'auror' => 1, 'healer' => 1, 'student' => 3)
    # 시작한 뒤에는 못 바꾼다
    expect(kind.preset_role!(harry, 'auror')).to eq :closed
  end

  it 'cancels when too few join, telling it on the web only' do
    open_event!
    toot(accounts.second, '@system [참가]')
    session.with_lock { kind.recruitment_over! }

    expect(session.status).to eq 'cancelled'
    expect(session.state['cancel_reason']).to include('7명이 되지 않아')
    expect(system.statuses.reorder(:id).last.text).to include('열렸습니다') # 취소 툿은 없다
  end

  it 'expels the most accused player and ends when the traitor is gone' do
    start_game!
    traitor = player_with('traitor')
    players_without('traitor').each { |player| act(player.account, '고발', targets: [traitor.account]) }
    session.with_lock { kind.timeout! }

    expect(session.reload).to have_attributes(status: 'finished')
    expect(session.state['winner']).to eq 'light'
    expect(traitor.reload.result).to eq 'lose'
    expect(GameHousePoint.where(game_session_id: session.id).sum(:amount)).to be_positive
    expect(Status.where(account: system).where('id > ?', @before_start).where.not('text LIKE ?', '%이벤트를 확인하세요%').count).to eq 0 # 시작·종료 알림 툿은 빼고
  end

  it 'petrifies at night unless the healer protects, and lets the auror investigate privately' do
    start_game!
    session.with_lock { kind.timeout! } # 아무도 고발하지 않은 낮 → 밤

    expect(session.reload.state['phase']).to eq 'night'
    traitor = player_with('traitor')
    student = player_with('student')
    auror = player_with('auror')

    act(auror.account, '조사', targets: [traitor.account])
    expect(secret_texts_for(auror.account)).to include(a_string_including('방주입니다'))

    act(traitor.account, '석화', targets: [student.account])
    session.with_lock { kind.timeout! }

    expect(session.reload.state['alive']).to_not include(student.seat)
    expect(session.state).to include('phase' => 'day', 'day' => 2)
  end

  it 'ignores night actions by the wrong role' do
    start_game!
    session.with_lock { kind.timeout! }
    student = player_with('student')
    traitor = player_with('traitor')

    act(student.account, '석화', targets: [traitor.account])
    expect(session.reload.state.dig('night', 'petrify')).to be_empty
  end

  it 'is opened by staff as an event and cannot be started by challenging someone' do
    expect(described_class.event_only?).to be true
    expect(described_class.web?).to be true
    expect(described_class.invite_error(3)).to include('이벤트로 엽니다')
    expect(Game::Kinds.by_command(described_class.config['command'])).to be_nil
    expect(Game::Kinds.group_games).to include(described_class)
    expect(Game::Events::Opening.kinds).to include(described_class)
  end

  it 'refuses more players than the maximum' do
    Game::Config.update!('secret_chamber', 'event_max_players' => '7', 'event_min_players' => '7')
    open_event!
    accounts.each { |account| toot(account, '@system [참가]') }
    extra = Fabricate(:account, username: 'late')
    GameCharacter.for(extra)
    toot(extra, '@system [참가]') # 정원이 차서 안 들어간다 (시작은 모집이 끝난 뒤)

    expect(session.reload.players.size).to eq 7
    expect(system.statuses.reorder(:id).last.text).to include('열렸습니다') # 정원 초과 답장은 없다 (웹에서는 모달)
  end

  it 'only lets the traitor pass on true prophecies and delivers them to the seer and her notes' do
    start_game!
    session.with_lock { kind.timeout! }
    traitor = player_with('traitor')
    seer = player_with('seer')
    student = player_with('student')

    # 거짓 예언은 막힌다: 방주를 호그와트 진영이라고, 학생 둘을 '둘 중 한 명은 방주'라고
    act(traitor.account, '예언', ['호그와트', traitor.account.username])
    expect(session.reload.state.dig('night', 'prophecy')).to be_nil
    expect(secret_texts_for(traitor.account).last).to include('사실이 아닌 예언')
    others = players_without('traitor').reject { |p| p.seat == seer.seat }.first(2)
    act(traitor.account, '예언', ['둘중', *others.map { |p| p.account.username }])
    expect(session.reload.state.dig('night', 'prophecy')).to be_nil

    # 사실인 예언: 이름(인자)으로 대상을 고른다
    act(traitor.account, '예언', ['둘중', student.account.username, traitor.account.username])
    expect(session.reload.state.dig('night', 'prophecy', 'text')).to include('적어도 한 명은 방주')
    # 보내는 순간 예언자에게 전해지고, 그날 밤에는 다시 보낼 수 없다
    expect(session.reload.state.dig('notes', seer.seat.to_s).last['text']).to include('적어도 한 명은 방주')
    act(traitor.account, '예언', ['역할', student.account.username])
    expect(secret_texts_for(traitor.account).last).to include('이미 보냈습니다')
    session.with_lock { kind.timeout! }

    expect(session.reload.state.dig('notes', seer.seat.to_s).size).to eq 1
    expect(kind.view_for(seer)[:notes].size).to eq 1
    expect(kind.view_for(seer)[:dark_chat]).to eq []
    expect(kind.view_for(traitor)[:my_role][:name]).to eq '방주'
    expect(kind.view_for(traitor)[:prophecy_kinds].size).to eq 8
  end

  it 'splits the traitor night, never skips the prophecy and knows more kinds' do
    start_game!
    session.with_lock { kind.timeout! }
    traitor = player_with('traitor')
    seer = player_with('seer')
    student = player_with('student')
    other = players_without('traitor').find { |p| p.seat != student.seat }

    # 같은편 · 다른편: 사실이 아니면 막힌다
    act(traitor.account, '예언', ['같은편', student.account.username, traitor.account.username])
    expect(session.reload.state.dig('night', 'prophecy')).to be_nil
    act(traitor.account, '예언', ['같은편', student.account.username, other.account.username])
    expect(session.reload.state.dig('night', 'prophecy', 'text')).to include('같은 편')

    # 앞 절반이 지나면 표적을 고를 수 없다
    current = session
    current.state['night']['half_at'] = 1.minute.ago.iso8601
    current.save!
    act(traitor.account, '석화', targets: [student.account])
    expect(session.reload.state.dig('night', 'petrify')).to eq({})
    expect(secret_texts_for(traitor.account).last).to include('표적을 고르는 시간이 끝났습니다')

    # 다음 밤에 예언을 안 보내고 끝나도 예언자는 사실인 예언을 받는다
    session.with_lock { kind.timeout! } # 아침
    session.with_lock { kind.timeout! } # 밤
    expect(session.reload.state['phase']).to eq 'night'
    before = Array(session.state.dig('notes', seer.seat.to_s)).size
    session.with_lock { kind.timeout! }
    notes = Array(session.reload.state.dig('notes', seer.seat.to_s))
    expect(notes.size).to eq before + 1
    expect(notes.last['text']).to include('역할은')
  end

  it 'accepts night targets by name' do
    start_game!
    session.with_lock { kind.timeout! }
    traitor = player_with('traitor')
    student = player_with('student')

    act(traitor.account, '석화', [student.account.username])

    expect(session.reload.state.dig('night', 'petrify', traitor.seat.to_s)).to eq student.seat
  end

  it 'reveals every role to eliminated players and hides them from the living' do
    start_game!
    session.with_lock { kind.timeout! }
    student = player_with('student')
    traitor = player_with('traitor')
    act(traitor.account, '석화', targets: [student.account])
    session.with_lock { kind.timeout! }

    expect(kind.view_for(student)[:players].map { |p| p[:role_name] }).to all(be_present)
    other = players_without('traitor').find { |p| p.seat != student.seat && session.state['alive'].include?(p.seat) }
    expect(kind.view_for(other)[:players].reject { |p| p[:seat] == other.seat || p[:out] }.map { |p| p[:role_name] }.compact).to eq []
  end

  it 'counts abstain votes for no one and ends the day 5 seconds after everyone votes' do
    start_game!
    alive = session.reload.players.to_a
    target = players_without('traitor').last # 방주가 퇴학되면 바로 끝나니 호그와트 쪽을
    alive.first(3).each { |voter| act(voter.account, '고발', targets: [target.account]) }
    act(alive[3].account, '무효')

    expect(session.reload.state['votes'][alive[3].seat.to_s]).to eq described_class::ABSTAIN
    expect(kind.view_for(alive[3])[:players].find { |p| p[:seat] == alive[3].seat }[:abstained]).to be true
    expect(kind.view_for(alive.first)[:all_voted]).to be false
    long_deadline = session.deadline_at
    expect(long_deadline).to be > 1.minute.from_now

    (alive - alive.first(4)).each { |voter| act(voter.account, '무효') }
    expect(kind.view_for(alive.first)[:all_voted]).to be true
    expect(session.reload.deadline_at).to be <= 6.seconds.from_now

    session.with_lock { kind.timeout! }
    expect(session.reload.state['phase']).to eq 'night'
    expect(session.state['out'].last).to include('seat' => target.seat, 'by' => 'vote')
    expect(session.messages.where(account_id: nil).map(&:text).join).to include('무효 4표')
  end

  it 'ends the night 5 seconds after every role has acted' do
    start_game!
    session.with_lock { kind.timeout! } # 1일째 낮 → 밤
    expect(session.reload.state['phase']).to eq 'night'
    traitor = player_with('traitor')
    auror = player_with('auror')
    healer = player_with('healer')
    victim = player_with('student')

    act(traitor.account, '석화', targets: [victim.account])
    act(auror.account, '조사', targets: [traitor.account])
    expect(kind.view_for(traitor)[:all_acted]).to be false
    expect(session.reload.deadline_at).to be > 1.minute.from_now

    act(healer.account, '보호', targets: [healer.account])
    expect(kind.view_for(traitor)[:all_acted]).to be false # 예언자가 살아 있으면 예언까지 보내야 끝난다
    act(traitor.account, '예언', ['남은수'])
    expect(kind.view_for(traitor)[:all_acted]).to be true
    expect(session.reload.deadline_at).to be <= 6.seconds.from_now
    expect(session.state.dig('night', 'looks')).to eq(auror.seat.to_s => traitor.seat)
  end

  it 'records each day and night for the replay and picks MVPs when it ends' do
    start_game!
    traitor = player_with('traitor')
    lights = players_without('traitor')
    # 1일째 낮: 모두 방주를 고발 → 퇴학 → 호그와트 승리
    lights.each { |voter| act(voter.account, '고발', targets: [traitor.account]) }
    act(traitor.account, '고발', targets: [lights.first.account])
    expect(kind.view_for(traitor)[:history]).to eq [] # 진행 중에는 보내지 않는다

    session.with_lock { kind.timeout! } if session.reload.status == 'active'

    expect(session.reload.status).to eq 'finished'
    view = kind.view_for(lights.first)
    expect(view[:history].first).to include('phase' => 'day', 'day' => 1, 'out' => traitor.seat)
    expect(view[:awards].first).to include(key: 'detective', title: '명탐정', dark: false)
    expect(view[:awards].pluck(:key)).to include('survivor', 'disguise')
  end

  it 'lets anyone watch, showing every role only to watching staff' do
    start_game!

    expect(described_class.spectatable?).to be true
    member_view = kind.view_for(nil)
    expect(member_view).to include(spectator: true, spectator_staff: false, dark_chat: [])
    expect(member_view[:players].filter_map { |p| p[:role_name] }).to eq []
    staff_view = kind.view_for(nil, staff: true)
    expect(staff_view[:spectator_staff]).to be true
    expect(staff_view[:players].map { |p| p[:role_name] }).to all(be_present)
  end

  it 'ends when the phase limit is reached, with the dark side winning by default' do
    Game::Config.update!('secret_chamber', 'max_phases' => '2')
    start_game!
    session.with_lock { kind.timeout! } # 낮 → 밤 (1페이즈 지남)
    session.with_lock { kind.timeout! } # 밤 → 낮이 시작되려는데 페이즈 한도

    expect(session.reload.status).to eq 'finished'
    expect(session.state['winner']).to eq 'dark'
  end
end
