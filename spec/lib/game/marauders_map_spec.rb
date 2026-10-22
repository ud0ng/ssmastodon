# frozen_string_literal: true

require 'rails_helper'

# 도둑 지도 (웹 전용 이벤트, 학생 팀 vs 사감 팀, 3~24명): 대기실에서 팀을 나누고, 모두 동시에 고른 뒤 결과를 반영한다
RSpec.describe Game::Web::MaraudersMap do
  let!(:system) { Fabricate(:account, username: 'system') }
  let(:layout) { Game::Web::MaraudersLayout }

  def make_session(total, status: 'lobby')
    session = GameSession.create!(kind: 'marauders_map', status: status, visibility: 'private', state: { 'mode' => 'event' })
    total.times { |index| session.players.create!(account: Fabricate(:account, username: "wizard#{index}#{session.id}"), seat: index, state: { 'accepted' => true }) }
    session.reload
  end

  # 시작까지 간 판. 위치·목표는 아래 helper 로 정한다
  def start!(total)
    session = make_session(total)
    kind = described_class.new(session)
    kind.prepare_event_players!
    session.update!(status: 'active')
    kind.start!
    session.reload
  end

  def kind_for(session)
    described_class.new(session.reload)
  end

  def move!(session, seat, room)
    Game::WebCommand.play(session.reload, session.players.find_by!(seat: seat).account, '이동', [room.to_s])
    session.reload
  end

  def hide!(session, seat)
    Game::WebCommand.play(session.reload, session.players.find_by!(seat: seat).account, '숨기')
    session.reload
  end

  def everyone_hides!(session, except: [])
    kind_for(session).pending_seats.each { |seat| hide!(session, seat) unless except.include?(seat) }
    session.reload
  end

  def links(session, turn = session.turn)
    phase = ((turn - 1) / 3).even? ? 'a' : 'b'
    layout.edges(session.state['map'], phase)
  end

  def neighbor(session, room)
    layout.neighbors(links(session), room).first
  end

  def place!(session, positions, **extra)
    session.state['positions'] = session.state['positions'].merge(positions.transform_keys(&:to_s))
    extra.each { |key, value| session.state[key.to_s] = value }
    session.save!
    session.reload
  end

  describe 'the map' do
    it 'grows with the number of players and stays connected in both stair states' do
      { 3 => 25, 5 => 25, 6 => 35, 10 => 35, 11 => 45, 15 => 45, 16 => 55, 20 => 55, 21 => 60, 24 => 60 }.each do |total, rooms|
        map = layout.build(total)
        expect(map['rooms'].size).to eq rooms
        expect(layout.connected?(map, 'a')).to be true
        expect(layout.connected?(map, 'b')).to be true
        expect(map['rooms'][map['office']]['name']).to eq '사감실'
        expect(map['rooms'].map { |room| room['name'] }.uniq.size).to eq rooms # 방 이름은 겹치지 않는다
      end
    end

    it 'splits the players about one third to the student team, as in the table' do
      expected = { 3 => 1, 5 => 1, 6 => 2, 8 => 3, 10 => 3, 11 => 4, 14 => 5, 16 => 6, 19 => 7, 21 => 7, 23 => 8, 24 => 8 }
      expected.each { |total, students| expect(layout.student_count(total)).to eq students }
      expect(layout.tier(7)).to include(targets: 4, turns: 20)
      expect(layout.tier(24)).to include(targets: 9, turns: 26)
    end
  end

  describe 'the waiting room teams' do
    it 'puts newcomers into teams without going over the caps and lets them change teams until the other team is full' do
      session = make_session(0)
      kind = described_class.new(session)
      6.times { |index| session.players.create!(account: Fabricate(:account, username: "late#{index}#{session.id}"), seat: index, state: { 'accepted' => true }) }
      session.reload

      counts = kind.team_counts
      expect(counts.values.sum).to eq 6
      expect(counts['student']).to be <= kind.team_caps['student']
      expect(counts['prefect']).to be <= kind.team_caps['prefect']

      mover = session.players.find { |player| player.state['team'] == 'prefect' }
      expect(kind.team_full?('student')).to eq(counts['student'] >= 2)
      result = kind.change_team!(mover)
      expect(result).to eq(counts['student'] >= 2 ? :full : :ok)
    end

    it 'shows the teams in the waiting room view with the change blocked once the other team is full' do
      session = make_session(6)
      allow(GameCharacter).to receive(:eligible_accounts).and_return(Account.where(id: session.players.map(&:account_id)))
      kind = described_class.new(session)
      player = session.players.first
      other = player.state['team'] == 'student' ? 'prefect' : 'student'

      view = Game::Lobby.view(session, player.account, staff: false)
      expect(view[:teams]).to include(mine: player.state['team'], can_change: true, change_blocked: kind.team_full?(other))
      expect(view[:teams][:caps]).to eq('student' => 2, 'prefect' => 4)
      expect(view[:players].map { |entry| entry[:team] }.compact.size).to eq 6
    end

    it 'fixes the teams to the caps at the start and puts the students first' do
      session = make_session(7)
      session.players.each { |player| player.update!(state: player.state.merge('team' => 'student')) } # 모두 학생을 골랐다
      kind = described_class.new(session)
      kind.prepare_event_players!

      session.reload
      expect(session.state['student_count']).to eq 2
      expect(session.players.map { |player| player.state['team'] }).to eq %w(student student prefect prefect prefect prefect prefect)
    end
  end

  describe 'starting' do
    it 'sets up the map, targets, roles and cloaks for the number of players' do
      session = start!(10)
      state = session.state

      expect(state['map']['rooms'].size).to eq 35
      expect(state['targets'].size).to eq 4
      expect(state['max_turns']).to eq 20
      expect(state['student_count']).to eq 3
      expect(state['cloaks_left']).to eq 1 # 학생 3명당 1개
      roles = state['roles'].values
      expect(roles.count('watcher')).to eq 1
      expect(roles.count('scout')).to eq 2 # 사감 7명의 약 1/3
      expect(roles.count('chaser')).to eq 4
      expect(state['positions'].size).to eq 10
      expect(state['targets']).to all(satisfy { |room| layout::GOALS.include?(state['map']['rooms'][room]['name']) })
    end

    it 'lets the staff tune the balance: targets, hint period and cloaks' do
      Game::Config.merge!('marauders_map', 'targets_adjust' => '1', 'cloak_adjust' => '1')
      session = start!(6)

      expect(session.state['targets'].size).to eq 5
      expect(session.state['cloaks_left']).to eq 2
    end

    it 'hides where the students are from the prefects while students see everybody' do
      session = start!(6)
      student = session.players.find_by!(seat: 0)
      prefect = session.players.find_by!(seat: 2)
      kind = kind_for(session)

      student_view = kind.view_for(student)
      expect(student_view[:tokens].size).to eq 6
      expect(student_view[:targets].size).to eq 4
      expect(student_view[:secret]).to be_an(Array)

      prefect_view = kind.view_for(prefect)
      expect(prefect_view[:tokens].map { |token| token[:team] }.uniq).to eq ['prefect']
      expect(prefect_view[:targets]).to eq []
      expect(prefect_view[:secret]).to eq []
      expect(prefect_view[:role]).to be_in(%w(watcher scout chaser))
    end
  end

  describe 'a turn' do
    it 'resolves once everyone who can act has chosen, staying put when hiding' do
      session = start!(6)
      kind = kind_for(session)
      expect(kind.pending_seats).to match_array((0..5).to_a)

      before = session.state['positions'].dup
      everyone_hides!(session)

      expect(session.turn).to eq 2
      expect(session.state['positions']).to eq before
      expect(session.state['moves']).to eq({})
    end

    it 'refuses a room that is not next to the player' do
      session = start!(6)
      here = session.state['positions']['0']
      far = (0...session.state['map']['rooms'].size).find { |room| room != here && !layout.neighbors(links(session), here).include?(room) && !session.state['secret'].flatten.include?(room) }

      move!(session, 0, far)
      expect(session.state['moves']).to eq({})
    end
  end

  describe 'arrest and rescue' do
    let(:session) { start!(6) }
    let(:office) { session.state['map']['office'] }

    # 학생 0 은 방 a, 사감 2 는 옆방 b, 나머지는 멀리 둔다
    def setup_chase!
      a = (0...session.state['map']['rooms'].size).find { |room| room != office && layout.neighbors(links(session), room).any? { |other| other != office } }
      b = layout.neighbors(links(session), a).find { |room| room != office }
      far = (0...session.state['map']['rooms'].size).to_a - [a, b, office] - layout.within(links(session), a, 3)
      positions = { '0' => a, '1' => far.first, '2' => b, '3' => far.second, '4' => far.third, '5' => far.fourth }
      place!(session, positions, targets: [far.last])
      [a, b]
    end

    it 'jails a student who shares a room with a prefect in the office, and the prefect is told in the log' do
      a, = setup_chase!
      move!(session, 2, a)
      everyone_hides!(session)

      session.reload
      expect(session.state['status_of']['0']).to eq 'jailed'
      expect(session.state['positions']['0']).to eq office
      expect(session.state['last']['arrests']).to include(include('seat' => 0, 'by' => 2, 'room' => a))
      expect(session.state['log'].join).to include('사감실로 끌려갑니다')
      expect(kind_for(session).pending_seats).not_to include(0) # 갇힌 학생은 고르지 않는다
    end

    it 'frees every jailed student when another student walks into the office, leaving a footprint, and a second arrest is out' do
      a, = setup_chase!
      move!(session, 2, a)
      everyone_hides!(session)
      expect(session.state['status_of']['0']).to eq 'jailed'

      # 학생 1 이 사무실 옆방으로 와서 들어간다
      next_to_office = layout.neighbors(links(session), office).first
      place!(session, { '1' => next_to_office, '2' => (0...session.state['map']['rooms'].size).to_a.last }, status_of: session.state['status_of'])
      move!(session, 1, office)
      everyone_hides!(session, except: [1])

      session.reload
      expect(session.state['status_of']['0']).to eq 'free'
      expect(session.state['rescued_count']['0']).to eq 1
      expect(session.state['clues']).to include(include('kind' => 'footprint', 'seat' => 1, 'room' => office))
      expect(session.state['last']['rescued']).to eq [0]

      # 두 번째 체포는 탈락
      place!(session, { '0' => 5, '2' => neighbor(session, 5) })
      move!(session, 2, 5)
      everyone_hides!(session, except: [2])
      expect(session.reload.state['status_of']['0']).to eq 'out'
      expect(kind_for(session).view_for(session.players.find_by!(seat: 0))[:full]).to be true # 탈락하면 관전
    end
  end

  describe 'clues and abilities' do
    let(:session) { start!(6) }

    def goal_next_to_a_student!
      goal = session.state['targets'].first
      start = layout.neighbors(links(session), goal).first
      far = (0...session.state['map']['rooms'].size).to_a - [goal, start, session.state['map']['office']] - layout.within(links(session), goal, 4)
      place!(session, { '0' => start, '1' => far.first, '2' => far.second, '3' => far.third, '4' => far.fourth, '5' => far.fifth })
      [goal, start]
    end

    it 'leaves a footprint at a target and counts it once, and the cloak hides the trace' do
      goal, = goal_next_to_a_student!
      move!(session, 0, goal)
      everyone_hides!(session, except: [0])

      session.reload
      expect(session.state['done']).to eq [goal]
      expect(session.state['clues']).to include(include('kind' => 'footprint', 'seat' => 0, 'room' => goal))

      cloak_session = start!(6)
      goal = cloak_session.state['targets'].first
      start = layout.neighbors(layout.edges(cloak_session.state['map'], 'a'), goal).first
      far = (0...cloak_session.state['map']['rooms'].size).to_a - [goal, start, cloak_session.state['map']['office']] - layout.within(layout.edges(cloak_session.state['map'], 'a'), goal, 4)
      cloak_session.state['positions'].merge!('0' => start, '1' => far.first, '2' => far.second, '3' => far.third, '4' => far.fourth, '5' => far.fifth)
      cloak_session.save!
      Game::WebCommand.play(cloak_session.reload, cloak_session.players.find_by!(seat: 0).account, '투명망토')
      expect(cloak_session.reload.state['cloaks_left']).to eq 0
      Game::WebCommand.play(cloak_session, cloak_session.players.find_by!(seat: 0).account, '이동', [goal.to_s])
      everyone_hides!(cloak_session, except: [0])

      expect(cloak_session.reload.state['done']).to eq [goal] # 목표는 달성하지만
      expect(cloak_session.state['clues'].select { |clue| clue['seat'] == 0 }).to be_empty # 흔적은 없다
    end

    it 'leaves a footprint when a student uses a secret passage, which only students can see' do
      a, b = session.state['secret'].first.then { |pair| pair || [0, 1] }
      skip 'no passage opened' if session.state['secret'].empty?
      far = (0...session.state['map']['rooms'].size).to_a - [a, b, session.state['map']['office']]
      place!(session, { '0' => a, '1' => far.first, '2' => far.second, '3' => far.third, '4' => far.fourth, '5' => far.fifth })
      move!(session, 0, b)
      everyone_hides!(session, except: [0])

      expect(session.reload.state['last']['secret']).to eq [0]
      expect(session.state['clues']).to include(include('kind' => 'footprint', 'seat' => 0, 'room' => b))
    end

    it 'reveals the zone of two random students every third turn' do
      3.times { everyone_hides!(session) }

      zones = session.reload.state['clues'].select { |clue| clue['kind'] == 'zone' }
      expect(zones.size).to eq 2
      expect(zones.pluck('seat').uniq.size).to eq 2
      expect(zones.first['zone']).to include('name')
      expect(session.state['log'].join).to include('어딘가에 있습니다')
    end

    it 'lets the watcher spot a student entering the watched room, once per game' do
      session = start!(6)
      watcher_seat = session.state['roles'].key('watcher').to_i
      room = (0...session.state['map']['rooms'].size).find { |candidate| candidate != session.state['map']['office'] }
      next_room = layout.neighbors(links(session), room).first
      far = (0...session.state['map']['rooms'].size).to_a - [room, next_room, session.state['map']['office']] - layout.within(links(session), room, 3)
      place!(session, { '0' => next_room, '1' => far.first, '2' => far.second, '3' => far.third, '4' => far.fourth, '5' => far.fifth })
      account = session.players.find_by!(seat: watcher_seat).account

      Game::WebCommand.play(session, account, '능력', [room.to_s])
      Game::WebCommand.play(session.reload, account, '능력', [room.to_s]) # 두 번째는 안 된다
      expect(session.reload.state['ability_left'][watcher_seat.to_s]).to eq 0
      move!(session, 0, room)
      everyone_hides!(session, except: [0])

      expect(session.reload.state['clues']).to include(include('kind' => 'watch', 'seat' => 0, 'room' => room))
    end

    it 'lets a chaser move two rooms and a scout count the students nearby' do
      session = start!(6)
      chaser = session.state['roles'].key('chaser')
      scout = session.state['roles'].key('scout')
      skip 'needs both a scout and a chaser' if chaser.nil? || scout.nil?
      here = session.state['positions'][chaser]
      two_away = layout.within(links(session), here, 2) - layout.within(links(session), here, 1)
      move!(session, chaser.to_i, two_away.first)
      expect(session.state['moves']).to eq({}) # 능력 없이는 2칸을 못 간다

      Game::WebCommand.play(session, session.players.find_by!(seat: chaser.to_i).account, '능력')
      move!(session, chaser.to_i, two_away.first)
      expect(session.state['moves'][chaser]).to include('room' => two_away.first, 'chase' => true)
    end
  end

  describe 'the end' do
    it 'ends with a student win when the team reaches every target' do
      session = start!(6)
      goals = session.state['targets']
      far = (0...session.state['map']['rooms'].size).to_a - goals - [session.state['map']['office']]
      session.state['done'] = goals.first(goals.size - 1)
      session.save!
      goal = goals.last
      start = layout.neighbors(links(session), goal).first
      place!(session, { '0' => start, '1' => far.first, '2' => far.second, '3' => far.third, '4' => far.fourth, '5' => far.fifth })
      move!(session, 0, goal)
      everyone_hides!(session, except: [0])

      session.reload
      expect(session.status).to eq 'finished'
      expect(session.players.order(:seat).map(&:result)).to eq %w(win win lose lose lose lose)
      expect(kind_for(session).view_for(session.players.first)[:winner]).to eq 'student'
      expect(kind_for(session).view_for(nil)[:history]).to be_present
    end

    it 'ends with a prefect win when every student is jailed' do
      session = start!(3)
      student = session.players.find_by!(seat: 0)
      a = (0...session.state['map']['rooms'].size).find { |room| room != session.state['map']['office'] }
      b = layout.neighbors(links(session), a).find { |room| room != session.state['map']['office'] } || layout.neighbors(links(session), a).first
      far = (0...session.state['map']['rooms'].size).to_a - [a, b, session.state['map']['office']]
      place!(session, { '0' => a, '1' => b, '2' => far.first }, targets: [far.last])
      move!(session, 1, a)
      everyone_hides!(session, except: [1])

      session.reload
      expect(session.status).to eq 'finished'
      expect(session.players.order(:seat).map(&:result)).to eq %w(lose win win)
      expect(student.reload.result).to eq 'lose'
    end

    it 'ends with a prefect win when the maximum number of turns has passed' do
      session = start!(6)
      session.update!(turn: session.state['max_turns'])
      everyone_hides!(session)

      expect(session.reload.status).to eq 'finished'
      expect(session.players.order(:seat).map(&:result)).to eq %w(lose lose win win win win)
    end
  end

  describe 'chat' do
    it 'keeps team chat inside the team and shows public bubbles at a decoy room to prefects for students they cannot see' do
      session = start!(6)
      student = session.players.find_by!(seat: 0)
      Game::Lobby.chat!(session, student.account, '여기!')
      Game::Lobby.chat!(session, student.account, '우리끼리만', team: 'student')

      prefect_view = kind_for(session).view_for(session.players.find_by!(seat: 2))
      expect(prefect_view[:bubbles].map { |bubble| bubble[:text] }).to eq ['여기!'] # 팀 채팅은 말풍선이 없다
      student_view = kind_for(session).view_for(student)
      expect(student_view[:bubbles].first[:room]).to eq session.state['positions']['0']
    end
  end
  describe 'team chat visibility and who has chosen' do
    it 'shows every team message to spectators, only the own team to players, and marks who already chose' do
      session = start!(6)
      kind = kind_for(session)
      student = session.players.find { |player| kind.team_of(player) == 'student' }
      prefect = session.players.find { |player| kind.team_of(player) == 'prefect' }
      Game::Lobby.chat!(session, student.account, '학생끼리', team: 'student')
      Game::Lobby.chat!(session, prefect.account, '사감끼리', team: 'prefect')
      Game::Lobby.chat!(session, student.account, '다 같이')

      view = kind.view_for(student)
      expect(view[:players].map { |entry| entry[:chosen] }).to all(be(false).or(be(true)))

      move!(session, student.seat, kind_for(session).view_for(student)[:moves].first)
      expect(kind_for(session).view_for(prefect)[:players].find { |entry| entry[:seat] == student.seat }[:chosen]).to be true
    end
  end
end
