# frozen_string_literal: true

module Game
  module Web
    # 도둑 지도 (웹 전용 이벤트, 학생 팀 vs 사감 팀, 3~24명). 호그와트 지도에서 숨바꼭질을 한다.
    #
    #   인원: 학생 팀은 전체의 약 1/3 (MaraudersLayout::STUDENTS), 나머지는 사감 팀. 대기실에서 무작위로 나뉘고 [팀 변경]으로 바꿀 수 있다.
    #   지도: 인원에 따라 방 25~60개, 층·탑이 늘어난다. 복도(일부는 막힘), 계단(일부는 움직이는 계단: 몇 턴마다 연결이 바뀜), 비밀 통로(학생만, 판마다 일부만 열림),
    #         필치의 사무실(체포된 학생이 갇히는 곳).
    #   턴: 학생과 사감 모두 동시에 고르고, 모두 고르면 결과를 반영한다 (비행 대결과 같다). 매 턴 인접한 방으로 1칸 이동하거나 제자리에 숨는다.
    #   학생: 사감 위치를 모두 본다. 팀 목표 장소(들)에 팀원 누구든 들어가면 1곳 달성. 목표 장소 도착·비밀 통로 사용은 그 턴에 발자국(정확한 방)을 남기고,
    #         3턴마다 무작위 학생 2명의 대략적인 구역(층/탑)이 공개된다. 투명 망토(팀 공용, 학생 3명당 1개): 쓴 학생은 2턴 동안 흔적도 구역 공개도 없다.
    #   사감: 서로의 위치만 본다. 역할(판당 1회 능력): 감시자(방 하나를 3턴 감시) / 정찰자(주변 2칸 안 학생 수) / 추격자(이번 턴 2칸 이동). 같은 방에 들어가면 체포.
    #   체포: 학생은 필치의 사무실에 갇힌다 (이동 불가, 팀 채팅만). 다른 학생이 사무실에 들어가면 갇힌 학생이 전원 구출된다 (구출자는 발자국이 남는다).
    #         학생마다 구출은 1번까지, 두 번째로 체포되면 탈락(관전).
    #   종료: 학생 팀은 목표 장소를 모두 달성하면 승리, 사감 팀은 학생이 모두 갇히거나 탈락하거나 최대 턴이 지나면 승리.
    class MaraudersMap < Game::Kinds::Base
      KEY = 'marauders_map'

      include Game::Events::Recruiting

      L = Game::Web::MaraudersLayout

      ROLES = %w(watcher scout chaser).freeze
      TEAM_CHAT_KEEP = 60
      CHAT_LENGTH = 200

      FIELDS = (base_fields(name: '도둑 지도', command: '도둑지도', points_win: 10) + [
        # 밸런스 메모: 승률이 한쪽으로 쏠리면 아래 세 가지로 조절한다 (목표 장소 수 ±1, 구역 공개 주기 3턴 ↔ 4턴, 투명 망토 개수)
        F.new(key: 'targets_adjust', type: :integer, default: 0, group: 'rules', label: '목표 장소 수 조절 (±)', hint: '인원별 기본 목표 장소 수에 더하거나 뺍니다 (-2~2). 학생이 너무 이기면 +1, 사감이 너무 이기면 -1'),
        F.new(key: 'hint_every', type: :integer, default: 3, group: 'rules', label: '구역 공개 주기 (턴)', hint: '무작위 학생 2명의 대략적인 구역이 공개되는 주기 (3 ↔ 4). 길수록 학생에게 유리합니다'),
        F.new(key: 'cloak_adjust', type: :integer, default: 0, group: 'rules', label: '투명 망토 개수 조절 (±)', hint: '기본은 학생 3명당 1개(최소 1개). 더하거나 뺍니다 (-1~2)'),
        F.new(key: 'cloak_turns', type: :integer, default: 2, group: 'rules', label: '투명 망토 지속 (턴)', hint: '이 동안 발자국·구역 공개가 없습니다'),
        F.new(key: 'secret_passages', type: :integer, default: 3, group: 'rules', label: '열려 있는 비밀 통로 수', hint: '판마다 후보 중 이 수만큼만 열립니다 (학생만 쓸 수 있습니다)'),
        F.new(key: 'stairs_every', type: :integer, default: 3, group: 'rules', label: '움직이는 계단이 바뀌는 주기 (턴)'),
        F.new(key: 'watch_turns', type: :integer, default: 3, group: 'rules', label: '감시 지속 (턴)', hint: '감시자가 방 하나를 감시하는 턴 수'),
        F.new(key: 'scout_range', type: :integer, default: 2, group: 'rules', label: '정찰 범위 (칸)'),
        F.new(key: 'chase_steps', type: :integer, default: 2, group: 'rules', label: '추격자 이동 (칸)'),
        F.new(key: 'student_name', type: :string, default: '학생', group: 'rules', label: '학생 팀 이름'),
        F.new(key: 'prefect_name', type: :string, default: '사감', group: 'rules', label: '사감 팀 이름'),
        F.new(key: 'cmd_move', type: :string, default: '이동', group: 'commands', label: '이동 명령어', hint: '웹 지도에서 방을 누르면 [이동/방 번호]로 보냅니다'),
        F.new(key: 'cmd_hide', type: :string, default: '숨기', group: 'commands', label: '제자리 명령어'),
        F.new(key: 'cmd_cloak', type: :string, default: '투명망토', group: 'commands', label: '투명 망토 명령어 (학생)'),
        F.new(key: 'cmd_ability', type: :string, default: '능력', group: 'commands', label: '사감 능력 명령어', hint: '감시자 [능력/방 번호] · 정찰자 [능력] · 추격자 [능력]'),
        F.new(key: 'msg_start', type: :text, group: 'messages', label: '시작', default: "%{game} 시작!\n%{student} %{students}명과 %{prefect} %{prefects}명이 호그와트에서 숨바꼭질을 시작합니다."),
        F.new(key: 'msg_footprint', type: :text, group: 'messages', label: '발자국', default: '%{room}에서 %{player}의 발자국이 발견되었습니다.'),
        F.new(key: 'msg_zone', type: :text, group: 'messages', label: '구역 공개', default: '%{player}{이가} %{zone} 어딘가에 있습니다.'),
        F.new(key: 'msg_watch', type: :text, group: 'messages', label: '감시 걸림', default: '감시 중인 %{room}에 %{player}{이가} 들어왔습니다.'),
        F.new(key: 'msg_caught', type: :text, group: 'messages', label: '체포', default: '%{prefect}{이가} %{room}에서 %{player}{을를} 붙잡았습니다. 필치의 사무실로 끌려갑니다.'),
        F.new(key: 'msg_out', type: :text, group: 'messages', label: '탈락', default: '%{player}{은는} 두 번째로 붙잡혀 탈락했습니다.'),
        F.new(key: 'msg_rescue', type: :text, group: 'messages', label: '구출', default: '%{player}{이가} 필치의 사무실에서 %{players}{을를} 구출했습니다!'),
        F.new(key: 'msg_stairs', type: :text, group: 'messages', label: '계단', default: '계단이 움직였습니다.'),
        F.new(key: 'msg_quiet', type: :text, group: 'messages', label: '조용한 턴', default: '복도는 조용합니다. 발소리 하나 들리지 않습니다.'),
        F.new(key: 'msg_turn', type: :text, group: 'messages', label: '턴 결과', default: "%{turn}턴\n%{lines}"),
        F.new(key: 'msg_win_student', type: :text, group: 'messages', label: '학생 팀 승리', default: "%{game} 종료! %{student} 팀이 목표 장소를 모두 다녀왔습니다. %{student} 팀의 승리!"),
        F.new(key: 'msg_win_prefect', type: :text, group: 'messages', label: '사감 팀 승리 (모두 체포)', default: "%{game} 종료! %{student} 팀이 모두 잡혔습니다. %{prefect} 팀의 승리!"),
        F.new(key: 'msg_win_limit', type: :text, group: 'messages', label: '사감 팀 승리 (시간 초과)', default: "%{game} 종료! %{turns}턴이 지나도록 %{student} 팀이 목표를 채우지 못했습니다. %{prefect} 팀의 승리!"),
      ] + Game::Events::Recruiting.fields(min: 3, max: 24)).freeze

      class << self
        def web?
          true
        end

        def spectatable?
          true
        end

        def event_only?
          true
        end

        # 대기실에서 팀을 나눈다 (Game::Lobby)
        def lobby_teams?
          true
        end

        def continues_on_timeout?
          true
        end

        def max_opponents
          [config['event_max_players'].to_i.clamp(3, 24) - 1, 2].max
        end

        def invite_error(_total, _args = [])
          '도둑 지도는 이벤트로 엽니다. 모집 안내를 기다려 주세요.'
        end
      end

      # ── 대기실: 팀 ──
      def event_max_players
        super.clamp(3, 24)
      end

      def team_names
        { 'student' => config['student_name'], 'prefect' => config['prefect_name'] }
      end

      # 지금 인원(total) 기준 팀 정원: 학생 팀은 전체의 약 1/3
      def team_caps(total = players.size)
        total = [total, 3].max
        students = L.student_count(total)
        { 'student' => students, 'prefect' => total - students }
      end

      def team_counts
        players.map { |player| player.state['team'] }.tally.then { |tally| { 'student' => tally['student'].to_i, 'prefect' => tally['prefect'].to_i } }
      end

      # 새로 들어온 사람: 정원을 넘지 않게 무작위로 (대기실에서 바꿀 수 있다)
      def assign_team!(player)
        return if player.state['team'].present?

        session.players.reset

        counts = team_counts
        caps = team_caps(players.size)
        team = if counts['student'] >= caps['student'] then 'prefect'
               elsif counts['prefect'] >= caps['prefect'] then 'student'
               else (rand < caps['student'].to_f / (caps['student'] + caps['prefect']) ? 'student' : 'prefect')
               end
        player.update!(state: player.state.merge('team' => team))
        session.players.reset
      end

      # [팀 변경]: 반대 팀으로. 반대 팀 정원이 다 찼으면 :full. :ok / :full / :closed
      def change_team!(player)
        return :closed unless session.lobby? && !Game::Lobby.counting?(session)

        target = player.state['team'] == 'student' ? 'prefect' : 'student'
        return :full if team_counts[target] >= team_caps[target]

        player.update!(state: player.state.merge('team' => target))
        session.players.reset
        :ok
      end

      def team_full?(team)
        team_counts[team] >= team_caps[team]
      end

      # 시작 직전: 정원에 맞게 팀을 맞추고 (넘치면 무작위로 옮김) 학생이 앞 번호가 되게 자리를 정한다
      def prepare_event_players!
        list = session.players.to_a
        list.each { |player| assign_team!(player) }
        list = session.players.reload.to_a
        caps = team_caps(list.size)
        teams = list.group_by { |player| player.state['team'] }
        students = Array(teams['student']).shuffle
        prefects = Array(teams['prefect']).shuffle
        students, prefects = [students.first(caps['student']), prefects + students.drop(caps['student'])] if students.size > caps['student']
        students, prefects = [students + prefects.first(caps['student'] - students.size), prefects.drop(caps['student'] - students.size)] if students.size < caps['student']
        ordered = students + prefects
        ordered.each_with_index { |player, index| player.update!(seat: 100 + index) }
        ordered.each_with_index do |player, index|
          player.update!(seat: index, state: player.state.merge('team' => index < students.size ? 'student' : 'prefect'))
        end
        state['student_count'] = students.size
        session.save!
        session.players.reset
      end

      # ── 시작 ──
      def start!
        total = players.size
        spec = L.tier(total)
        map = L.build(total)
        passages = L.secret_passages(map, config['secret_passages'].to_i.clamp(0, 6))
        count = student_count
        studs = players.first(count)
        prefs = players.drop(count)
        links = L.edges(map, 'a')

        anchor = rand(map['rooms'].size)
        anchor = rand(map['rooms'].size) while map['rooms'][anchor]['kind'] == 'office' || map['rooms'][anchor]['kind'] == 'tower'
        near = L.within(links, anchor, 2).reject { |room| map['rooms'][room]['kind'] == 'office' }
        positions = {}
        studs.each { |player| positions[player.seat.to_s] = near.sample }
        far = (0...map['rooms'].size).reject { |room| map['rooms'][room]['kind'] == 'office' || studs.any? { |s| L.distance(links, positions[s.seat.to_s], room) < 3 } }
        far = (0...map['rooms'].size).to_a - [map['office']] if far.empty?
        prefs.each { |player| positions[player.seat.to_s] = far.sample }

        goal_names = L::GOALS
        candidates = map['rooms'].select { |room| goal_names.include?(room['name']) && studs.none? { |s| L.distance(links, positions[s.seat.to_s], room['id']) < 3 } }.map { |room| room['id'] }
        candidates = map['rooms'].select { |room| goal_names.include?(room['name']) }.map { |room| room['id'] } if candidates.empty?
        wanted = (spec[:targets] + config['targets_adjust'].to_i.clamp(-2, 2)).clamp(1, [candidates.size, 1].max)
        targets = candidates.sample(wanted)

        shuffled = prefs.shuffle
        scouts = (prefs.size / 3.0).round
        roles = {}
        shuffled.each_with_index do |player, index|
          roles[player.seat.to_s] = index.zero? ? 'watcher' : (index <= scouts ? 'scout' : 'chaser')
        end
        cloaks = [(count / 3.0).ceil + config['cloak_adjust'].to_i.clamp(-1, 2), 0].max

        state.merge!(
          'student_count' => count, 'map' => map, 'secret' => passages, 'targets' => targets, 'done' => [],
          'positions' => positions, 'status_of' => studs.to_h { |player| [player.seat.to_s, 'free'] }, 'rescued_count' => {},
          'roles' => roles, 'ability_left' => roles.transform_values { 1 }, 'cloaks_left' => cloaks, 'cloak_until' => {},
          'watch' => nil, 'clues' => [], 'moves' => {}, 'last' => nil, 'history' => [], 'max_turns' => spec[:turns], 'log' => []
        )
        state['history'] << { 'turn' => 0, 'positions' => positions.dup }
        session.update!(turn: 1)
        post(render(config['msg_start'], student: config['student_name'], prefect: config['prefect_name'], students: studs.size, prefects: prefs.size))
        begin_turn!
      end

      # ── 명령 ──
      # 웹 지도에서: [이동/방 번호] [숨기] [투명망토] [능력/방 번호]. 모두 고르면 결과를 반영한다
      def handle(player, command, args, _status)
        action = { config['cmd_move'] => :move, config['cmd_hide'] => :hide, config['cmd_cloak'] => :cloak, config['cmd_ability'] => :ability }[command]
        return false if action.nil?
        return true unless acting?(player)

        case action
        when :move then submit_room!(player, Integer(args.first.to_s, exception: false))
        when :hide then submit_room!(player, here_of(player))
        when :cloak then use_cloak!(player)
        else use_ability!(player, Integer(args.first.to_s, exception: false))
        end
        true
      end

      def timeout!
        resolve!
      end

      def max_turns
        state['max_turns'].to_i
      end

      # 이 판에서 지금 행동해야 하는 자리들 (자유로운 학생 + 사감)
      def pending_seats
        acting_players.reject { |player| state['moves'].key?(player.seat.to_s) }.map(&:seat)
      end

      def card_data
        {
          'targets_done' => Array(state['done']).size,
          'targets_total' => Array(state['targets']).size,
          'clues' => [],
          'log' => state['log'] || [],
          'max_turns' => max_turns,
          'student_seats' => student_seats,
          'student_name' => config['student_name'],
          'prefect_name' => config['prefect_name'],
          'phase' => 'turn',
          'web' => true,
        }
      end

      def card_actions
        []
      end

      # 팀 채팅이 닿는 팀 ('student' / 'prefect'), 시작 전 대기실에서는 고른 팀
      def team_of(player)
        return player.state['team'] if state['map'].nil?

        student?(player) ? 'student' : 'prefect'
      end

      # ── 보이는 것 ──
      # 이 사람에게 보이는 지도. 학생: 모두의 위치 / 사감: 사감 위치와 공개된 흔적만 / 관전자·끝난 판·탈락한 학생: 전부
      def view_for(player)
        return nil if state['map'].nil?

        full = player.nil? || session.status == 'finished' || out_student?(player)
        team = player && team_of(player)
        seat = player&.seat&.to_s
        base_view(player, team, full)
          .merge(
            me: player&.seat, team: team, spectator: player.nil?, full: full,
            role: team == 'prefect' ? state.dig('roles', seat) : nil,
            my_status: team == 'student' ? status_of(player) : nil,
            items: items_for(player, team),
            planned: player && state.dig('moves', seat),
            my_turn: !full && acting?(player),
            submitted: player.nil? || !acting?(player) || state['moves'].key?(seat),
            waiting: acting_players.reject { |each| state['moves'].key?(each.seat.to_s) }.map(&:name),
            moves: !full && acting?(player) ? reachable(player) : [],
            chase: player && state.dig('moves', seat, 'chase') ? true : false
          )
      end

      private

      def finished?
        session.status == 'finished'
      end

      def student_count
        [state['student_count'].to_i, 1].max
      end

      def student_seats
        players.first(student_count).map(&:seat)
      end

      def student?(player)
        student_seats.include?(player.seat)
      end

      def students
        players.first(student_count)
      end

      def prefects
        players.drop(student_count)
      end

      def status_of(player)
        state.dig('status_of', player.seat.to_s)
      end

      def out_student?(player)
        student?(player) && status_of(player) == 'out'
      end

      def free_students
        students.select { |player| status_of(player) == 'free' }
      end

      def acting_players
        free_students + prefects
      end

      def acting?(player)
        session.status == 'active' && acting_players.any? { |each| each.id == player.id }
      end

      def map
        state['map']
      end

      def rooms
        map['rooms']
      end

      def office
        map['office']
      end

      def room_name(room)
        rooms[room]['name']
      end

      def here_of(player)
        state['positions'][player.seat.to_s]
      end

      # 이번 턴에 열려 있는 계단 상태: 몇 턴마다 번갈아 A·B
      def stairs_phase(turn = session.turn)
        ((turn - 1) / config['stairs_every'].to_i.clamp(1, 10)).even? ? 'a' : 'b'
      end

      def links
        L.edges(map, stairs_phase)
      end

      def adjacent(room, student:)
        found = L.neighbors(links, room)
        found += state['secret'].filter_map { |a, b| (a == room && b) || (b == room && a) || nil } if student
        found.uniq
      end

      # 이 사람이 이번 턴에 갈 수 있는 방 (제자리 포함)
      def reachable(player)
        here = here_of(player)
        steps = !student?(player) && state.dig('moves', player.seat.to_s, 'chase') ? config['chase_steps'].to_i.clamp(1, 3) : 1
        list = steps == 1 ? adjacent(here, student: student?(player)) : L.within(links, here, steps)
        ([here] + list).uniq
      end

      def cloaked?(seat, turn = session.turn)
        state.dig('cloak_until', seat.to_s).to_i >= turn
      end

      # ── 턴 ──
      def begin_turn!
        state['moves'] = {}
        session.save!
        wait_for_turn!
      end

      def submit_room!(player, room)
        return dm(player, '갈 수 없는 방입니다.') if room.nil? || !reachable(player).include?(room)

        seat = player.seat.to_s
        plan = state['moves'][seat] || {}
        state['moves'][seat] = plan.merge('room' => room)
        session.save!
        resolve! if pending_seats.empty?
      end

      def use_cloak!(player)
        seat = player.seat.to_s
        return unless student?(player) && state['cloaks_left'].to_i.positive?
        return if state.dig('moves', seat, 'room') || cloaked?(seat)

        state['cloaks_left'] -= 1
        state['cloak_until'][seat] = session.turn + config['cloak_turns'].to_i.clamp(1, 5) - 1
        state['moves'][seat] = (state['moves'][seat] || {}).merge('cloak' => true)
        session.save!
      end

      # 사감 능력 (판당 1회): 감시자는 방 번호, 정찰자·추격자는 번호 없이
      def use_ability!(player, room)
        seat = player.seat.to_s
        role = state.dig('roles', seat)
        return if student?(player) || role.nil? || !state.dig('ability_left', seat).to_i.positive? || state.dig('moves', seat, 'room')

        case role
        when 'watcher'
          return if room.nil? || room.negative? || room >= rooms.size

          state['watch'] = { 'room' => room, 'until' => session.turn + config['watch_turns'].to_i.clamp(1, 6) - 1, 'by' => player.seat }
          plan = { 'ability' => 'watch', 'target' => room }
        when 'scout'
          plan = { 'ability' => 'scout' }
        else
          plan = { 'ability' => 'chase', 'chase' => true }
        end
        state['ability_left'][seat] -= 1
        state['moves'][seat] = (state['moves'][seat] || {}).merge(plan)
        session.save!
      end

      # ── 결과 ──
      def resolve!
        turn = session.turn
        from = state['positions'].dup
        plans = state['moves']
        log = []
        last = { 'turn' => turn, 'moves' => {}, 'arrests' => [], 'rescued' => [], 'secret' => [], 'stairs' => (turn % config['stairs_every'].to_i.clamp(1, 10)).zero? }

        # 1) 이동
        acting_players.each do |player|
          seat = player.seat.to_s
          room = plans.dig(seat, 'room') || from[seat]
          state['positions'][seat] = room
          secret = student?(player) && from[seat] != room && state['secret'].any? { |pair| pair.sort == [from[seat], room].sort }
          last['moves'][seat] = { 'from' => from[seat], 'to' => room, 'secret' => secret }
          last['secret'] << player.seat if secret
        end
        moved = free_students

        # 2) 목표 장소
        moved.each do |player|
          room = state['positions'][player.seat.to_s]
          state['done'] << room if state['targets'].include?(room) && state['done'].exclude?(room)
        end

        # 3) 발자국: 목표 장소 도착·비밀 통로 사용 (투명 망토를 쓰면 없다). 감시 중인 방에 들어와도 위치가 공개된다
        moved.each do |player|
          seat = player.seat.to_s
          room = state['positions'][seat]
          next if cloaked?(seat, turn)

          arrived = from[seat] != room && state['targets'].include?(room)
          if arrived || last['secret'].include?(player.seat)
            footprint!(player, room, turn, log)
          elsif state['watch'] && state['watch']['room'] == room && state['watch']['until'] >= turn && from[seat] != room
            state['clues'] << { 'turn' => turn, 'kind' => 'watch', 'seat' => player.seat, 'room' => room }
            log << render(config['msg_watch'], room: room_name(room), player: player)
          end
        end

        # 4) 체포: 사감과 같은 방에 있는 자유로운 학생
        moved.each do |student|
          seat = student.seat.to_s
          catcher = prefects.find { |prefect| state['positions'][prefect.seat.to_s] == state['positions'][seat] }
          next if catcher.nil?

          room = state['positions'][seat]
          if state['rescued_count'][seat].to_i >= 1
            state['status_of'][seat] = 'out'
            log << render(config['msg_out'], player: student)
          else
            state['status_of'][seat] = 'jailed'
          end
          state['positions'][seat] = office
          last['arrests'] << { 'seat' => student.seat, 'by' => catcher.seat, 'room' => room, 'out' => state['status_of'][seat] == 'out' }
          log << render(config['msg_caught'], prefect: catcher, room: room_name(room), player: student)
        end

        # 5) 구출: 사무실에 들어온 자유로운 학생이 있으면 갇힌 학생이 전원 구출 (구출자는 반드시 발자국을 남긴다)
        rescuers = free_students.select { |player| state['positions'][player.seat.to_s] == office && from[player.seat.to_s] != office }
        jailed = students.select { |player| status_of(player) == 'jailed' }
        if rescuers.any? && jailed.any?
          jailed.each do |player|
            state['status_of'][player.seat.to_s] = 'free'
            state['rescued_count'][player.seat.to_s] = state['rescued_count'][player.seat.to_s].to_i + 1
            last['rescued'] << player.seat
          end
          rescuers.each { |player| footprint!(player, office, turn, log) }
          log << render(config['msg_rescue'], player: rescuers.first, players: jailed.map(&:name).join(', '))
        end

        # 6) 정찰자: 주변 N칸 안 학생 수
        prefects.each do |prefect|
          next unless plans.dig(prefect.seat.to_s, 'ability') == 'scout'

          here = state['positions'][prefect.seat.to_s]
          range = L.within(links, here, config['scout_range'].to_i.clamp(1, 4))
          count = free_students.count { |student| range.include?(state['positions'][student.seat.to_s]) }
          state['clues'] << { 'turn' => turn, 'kind' => 'scout', 'seat' => prefect.seat, 'room' => here, 'count' => count, 'range' => config['scout_range'].to_i.clamp(1, 4) }
        end

        # 7) 구역 공개: 몇 턴마다 무작위 학생 2명 (학생 팀이 1~2명이면 전원)
        every = config['hint_every'].to_i.clamp(2, 6)
        if (turn % every).zero?
          eligible = free_students.reject { |player| cloaked?(player.seat, turn) }
          picked = students.size <= 2 ? eligible : eligible.sample(2)
          picked.each do |player|
            zone = L.zone(map, state['positions'][player.seat.to_s])
            state['clues'] << { 'turn' => turn, 'kind' => 'zone', 'seat' => player.seat, 'zone' => zone }
            log << render(config['msg_zone'], player: player, zone: zone['name'])
          end
        end

        log << render(config['msg_stairs']) if last['stairs']
        state['clues'] = state['clues'].last(60)
        state['last'] = last
        state['log'] = log
        state['moves'] = {}
        state['history'] << { 'turn' => turn, 'positions' => state['positions'].dup, 'status_of' => state['status_of'].dup, 'arrests' => last['arrests'], 'rescued' => last['rescued'] }
        text = render(config['msg_turn'], turn: turn, lines: (log.presence || [render(config['msg_quiet'])]).join("\n"))

        if state['done'].size >= state['targets'].size
          finish_game!(:student, text)
        elsif free_students.empty?
          finish_game!(:prefect, text)
        elsif turn >= max_turns
          finish_game!(:limit, text)
        else
          post(text)
          session.update!(turn: turn + 1)
          begin_turn!
        end
      end

      def footprint!(player, room, turn, log)
        state['clues'] << { 'turn' => turn, 'kind' => 'footprint', 'seat' => player.seat, 'room' => room }
        log << render(config['msg_footprint'], room: room_name(room), player: player)
      end

      def finish_game!(who, text)
        winners = who == :student ? students : prefects
        names = { student: 'msg_win_student', prefect: 'msg_win_prefect', limit: 'msg_win_limit' }
        ending = render(config[names.fetch(who)], student: config['student_name'], prefect: config['prefect_name'], turns: session.turn)
        state['finished_turn'] = session.turn
        session.save!
        finish!(winners: winners, message: "#{text}\n\n#{ending}")
      end

      # ── 화면 데이터 ──
      def map_view
        {
          rooms: rooms.map { |room| { id: room['id'], name: room['name'], x: room['x'], y: room['y'], kind: room['kind'], tower: room['tower'] } },
          cols: map['cols'], floors: map['floors'], tower_cols: map['tower_cols'], office: office,
          corridors: map['corridors'].map { |a, b| { a: a, b: b } },
          fixed_stairs: map['fixed_stairs'].map { |a, b| { a: a, b: b } },
          moving_stairs: %w(a b).flat_map { |phase| map['stairs'][phase].map { |a, b| { a: a, b: b, phase: phase } } },
          stairs_phase: stairs_phase,
          stairs_every: config['stairs_every'].to_i.clamp(1, 10),
        }
      end

      def base_view(viewer, team, full)
        prefect_view = team == 'prefect'
        turn = session.turn
        {
          map: map_view,
          status: session.status, turn: turn, max_turns: max_turns, deadline_at: session.deadline_at&.iso8601, now: Time.current.iso8601(3),
          student_name: config['student_name'], prefect_name: config['prefect_name'], hint_every: config['hint_every'].to_i,
          commands: { move: config['cmd_move'], hide: config['cmd_hide'], cloak: config['cmd_cloak'], ability: config['cmd_ability'] },
          secret: !prefect_view || full ? state['secret'].map { |a, b| { a: a, b: b } } : [],
          targets: !prefect_view || full ? state['targets'].map { |room| { room: room, done: state['done'].include?(room) } } : [],
          targets_done: state['done'].size, targets_total: state['targets'].size,
          cloak_turns: config['cloak_turns'].to_i,
          tokens: tokens_for(prefect_view && !full),
          clues: state['clues'].last(40).map { |clue| clue_view(clue) },
          last: last_view(prefect_view && !full),
          players: players.map do |other|
            { seat: other.seat, name: other.name, account_id: other.account_id, team: student?(other) ? 'student' : 'prefect',
              status: student?(other) ? status_of(other) : nil, rescued: state.dig('rescued_count', other.seat.to_s).to_i,
              chosen: acting?(other) && state['moves'].key?(other.seat.to_s) }
          end,
          bubbles: bubbles_for(viewer, prefect_view && !full),
          log: state['log'] || [],
          history: full ? Array(state['history']) : nil,
          finish: finished? ? finish_view : nil,
          roles: full ? state['roles'] : nil,
          winner: session.status == 'finished' ? (players.find { |player| player.result == 'win' }&.then { |winner| student?(winner) ? 'student' : 'prefect' }) : nil,
        }
      end

      # 끝난 뒤 보여 줄 것: 이긴 팀, 사람마다 받은 점수·재화·아이템
      def finish_view
        {
          currency: common['currency_name'], test: session.test?,
          rewards: players.to_h do |player|
            outcome = player.result.to_s
            [player.seat, session.test? || outcome.blank? ? nil : {
              result: outcome, points: config["points_#{outcome}"].to_i, money: config["reward_money_#{outcome}"].to_i,
              items: outcome == 'win' ? Array(config['reward_items_win']).filter_map { |line| line.to_s.split('|').first.to_s.strip.presence } : []
            }]
          end,
        }
      end

      # 지도 위 이름표: 사감 팀 화면에서는 학생의 정확한 위치가 숨겨진다 (갇힌 학생은 사무실이라 모두가 안다)
      def tokens_for(hide_students)
        players.filter_map do |other|
          if student?(other)
            next if hide_students && status_of(other) == 'free'
          end
          { seat: other.seat, room: state['positions'][other.seat.to_s], team: student?(other) ? 'student' : 'prefect', status: student?(other) ? status_of(other) : nil }
        end
      end

      def clue_view(clue)
        clue.merge('room_name' => clue['room'] && room_name(clue['room']), 'age' => session.turn - clue['turn'])
      end

      # 지난 턴의 움직임(애니메이션용): 사감 팀에게는 공개된 학생(발자국·체포)의 움직임만
      def last_view(hide_students)
        last = state['last']
        return nil if last.nil?

        moves = last['moves'].select do |seat, _|
          next true unless hide_students

          player = players.find { |each| each.seat.to_s == seat }
          !student?(player) || last['arrests'].any? { |arrest| arrest['seat'].to_s == seat } || state['clues'].any? { |clue| clue['turn'] == last['turn'] && clue['seat'].to_s == seat }
        end
        last.merge('moves' => moves)
      end

      def items_for(player, team)
        return {} if player.nil?

        if team == 'student'
          { cloak: state['cloaks_left'].to_i, cloaked: cloaked?(player.seat) }
        else
          { ability: state.dig('ability_left', player.seat.to_s).to_i }
        end
      end

      # 전체 공개 채팅 말풍선: 사감 팀에게는 지금 위치가 드러난 학생만 그 자리에, 모르는 학생은 아무 방에나 (혼란)
      def bubbles_for(viewer, hide_students)
        recent = session.messages.where(kind: 'chat').where('created_at > ?', 12.seconds.ago).order(:id).last(6)
        recent.filter_map do |message|
          next if message.payload.present? && message.payload['team'].present?

          author = players.find { |player| player.account_id == message.author_id }
          next if author.nil?

          room = state['positions'][author.seat.to_s]
          if hide_students && student?(author) && status_of(author) == 'free'
            revealed = state['clues'].reverse.find { |clue| clue['seat'] == author.seat && clue['room'] && clue['turn'] >= session.turn - 1 }
            room = revealed ? revealed['room'] : Random.new(message.id).rand(rooms.size)
          end
          { id: message.id.to_s, seat: author.seat, text: message.text, room: room, at: message.created_at.iso8601(3) }
        end
      end
    end
  end
end
