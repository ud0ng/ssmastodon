# frozen_string_literal: true

module Game
  module Web
    # 도둑 지도 (웹 전용, 학생 1 vs 사감 1~4). 신청한 사람이 학생, 태그한 사람들이 사감.
    # 지도는 웹 컨텐츠 화면에서 보고, 행동은 마법 결투처럼 시스템에게 DM 으로 고른다 (지도에서 방을 누르면 DM 이 자동으로 나간다).
    #
    #   방은 가로×세로 격자(기본 5×5 = 25개)에 놓인 그래프이고, 복도·계단이 간선이다. 일부 길은 막혀 있다.
    #   턴: 학생이 먼저 이동을 정한다 → 그다음 사감 팀이 동시에 정한다 → 결과를 반영해 중요한 사건만 공개한다.
    #   학생: 사감 위치를 모두 본다. 비밀 통로(학생만, 판마다 일부만 열림)와 투명 망토를 쓴다. 목표 장소를 모두 들르면 승리.
    #         목표 장소에 도착한 턴·비밀 통로를 쓴 턴에는 발자국(정확한 방)이 남고, 그 밖에는 몇 턴마다 대략적인 구역만 알려진다.
    #   사감: 서로의 위치를 보고, 학생 위치는 모른다. 호메눔 레벨리오: 주변 N칸 안에 학생이 있는지만 확인. 같은 방에 들어가면 체포.
    #   움직이는 계단: 몇 턴마다 일부 연결이 바뀐다. 최대 턴이 지나면 사감 승리.
    class MaraudersMap < Game::Kinds::Base
      KEY = 'marauders_map'

      ROOMS = %w(
        천문탑 그리핀도르\ 휴게실 부엉이장 래번클로\ 탑 점술\ 교실
        도서관 금지된\ 구역 대계단 트로피실 필요의\ 방
        변신술\ 교실 마법약\ 교실 대연회장 현관\ 홀 의무실
        슬리데린\ 지하실 부엌 후플푸프\ 휴게실 안뜰 온실
        지하\ 통로 비밀의\ 방\ 입구 정문 해그리드\ 오두막 금지된\ 숲\ 입구
      ).freeze

      ZONES_X = %w(서쪽 가운데 동쪽).freeze
      ZONES_Y = %w(위층 가운데층 아래층).freeze
      ACTIONS = %w(move hide cloak revelio).freeze

      FIELDS = (base_fields(name: '도둑 지도', command: '도둑지도', points_win: 10) + [
        F.new(key: 'width', type: :integer, default: 5, group: 'rules', label: '지도 가로 (방)', hint: '3~8, 가로×세로가 방 수 (기본 5×5 = 25개)'),
        F.new(key: 'height', type: :integer, default: 5, group: 'rules', label: '지도 세로 (방)', hint: '3~8'),
        F.new(key: 'max_opponents', type: :integer, default: 4, group: 'rules', label: '사감 최대 인원', hint: '1~4'),
        F.new(key: 'max_turns', type: :integer, default: 20, group: 'rules', label: '최대 턴', hint: '지나면 사감 승리'),
        F.new(key: 'targets', type: :integer, default: 3, group: 'rules', label: '학생이 들러야 하는 목표 장소 수'),
        F.new(key: 'targets_reduced', type: :integer, default: 2, group: 'rules', label: '사감이 많을 때 목표 장소 수', hint: '사감이 아래 인원 이상이면 이 수로 줄입니다'),
        F.new(key: 'balance_prefects', type: :integer, default: 3, group: 'rules', label: '밸런스 조정이 시작되는 사감 인원', hint: '이 인원 이상이면 목표 장소를 줄이고 투명 망토를 늘립니다'),
        F.new(key: 'cloaks', type: :integer, default: 1, group: 'rules', label: '투명 망토 개수'),
        F.new(key: 'cloaks_bonus', type: :integer, default: 1, group: 'rules', label: '사감이 많을 때 추가 투명 망토'),
        F.new(key: 'cloak_turns', type: :integer, default: 2, group: 'rules', label: '투명 망토 지속 (턴)', hint: '이 동안 발자국·구역 힌트가 남지 않습니다'),
        F.new(key: 'revelio', type: :integer, default: 1, group: 'rules', label: '호메눔 레벨리오 (사감 한 사람당 개수)'),
        F.new(key: 'revelio_range', type: :integer, default: 2, group: 'rules', label: '호메눔 레벨리오 범위 (칸)', hint: '길로 이어진 방 수. 이 안에 학생이 있는지 여부만 알려 줍니다'),
        F.new(key: 'secret_passages', type: :integer, default: 3, group: 'rules', label: '열려 있는 비밀 통로 수', hint: '판마다 후보 중 이 수만큼만 열립니다'),
        F.new(key: 'stairs_every', type: :integer, default: 3, group: 'rules', label: '움직이는 계단이 바뀌는 주기 (턴)'),
        F.new(key: 'hint_every', type: :integer, default: 3, group: 'rules', label: '대략 구역 힌트 (턴마다)'),
        F.new(key: 'student_name', type: :string, default: '학생', group: 'rules', label: '학생 역할 이름'),
        F.new(key: 'prefect_name', type: :string, default: '사감', group: 'rules', label: '사감 역할 이름'),
        F.new(key: 'cmd_move', type: :string, default: '이동', group: 'commands', label: '이동 명령어', hint: '[이동/대연회장] 처럼 붙어 있는 방 이름'),
        F.new(key: 'cmd_hide', type: :string, default: '숨기', group: 'commands', label: '제자리 명령어'),
        F.new(key: 'cmd_cloak', type: :string, default: '투명망토', group: 'commands', label: '투명 망토 명령어 (학생)'),
        F.new(key: 'cmd_revelio', type: :string, default: '레벨리오', group: 'commands', label: '호메눔 레벨리오 명령어 (사감)'),
        F.new(key: 'msg_start', type: :text, group: 'messages', label: '시작',
              default: "%{game} 시작! %{student}: %{player} / %{prefect}: %{players}\n지도는 이 컨텐츠 방에서 볼 수 있습니다. 턴마다 %{seconds}초 안에 움직일 방을 골라 주세요."),
        F.new(key: 'msg_ask_student', type: :text, group: 'messages', label: 'DM: 학생 이동 고르기',
              default: "%{turn}턴 | 지금 %{room} 에 있습니다. 갈 수 있는 방: %{rooms}\n[%{move}/방 이름] 으로 이동하거나 [%{hide}] 로 제자리에 숨으세요.\n남은 목표 장소: %{targets}\n투명 망토 %{cloaks}개: [%{cloak}]"),
        F.new(key: 'msg_ask_prefect', type: :text, group: 'messages', label: 'DM: 사감 이동 고르기',
              default: "%{turn}턴 | 지금 %{room} 에 있습니다. 갈 수 있는 방: %{rooms}\n[%{move}/방 이름] 으로 이동하거나 [%{hide}] 로 제자리에 있으세요.\n호메눔 레벨리오 %{revelios}개: [%{revelio}]"),
        F.new(key: 'msg_role_student', type: :text, group: 'messages', label: 'DM: 학생 시작 안내', default: "당신은 %{student}입니다. 목표 장소: %{targets}\n모두 다녀오면 승리합니다. %{prefect}에게 붙잡히지 마세요."),
        F.new(key: 'msg_role_prefect', type: :text, group: 'messages', label: 'DM: 사감 시작 안내', default: "당신은 %{prefect}입니다. %{student}{을를} 같은 방에서 붙잡으면 승리합니다."),
        F.new(key: 'msg_chosen', type: :text, group: 'messages', label: 'DM: 선택 확인', default: '선택했습니다.'),
        F.new(key: 'msg_bad_move', type: :text, group: 'messages', label: 'DM: 갈 수 없는 방', default: '갈 수 없는 방입니다. 붙어 있는 방을 골라 주세요.'),
        F.new(key: 'msg_wrong_time', type: :text, group: 'messages', label: 'DM: 지금은 할 수 없음', default: '지금은 할 수 없는 선택입니다.'),
        F.new(key: 'msg_no_item', type: :text, group: 'messages', label: 'DM: 아이템 없음', default: '%{item}{이가} 없습니다.'),
        F.new(key: 'msg_cloak_on', type: :text, group: 'messages', label: 'DM: 투명 망토 사용', default: '투명 망토를 썼습니다. %{turns}턴 동안 흔적이 남지 않습니다.'),
        F.new(key: 'msg_revelio_on', type: :text, group: 'messages', label: 'DM: 레벨리오 사용', default: '호메눔 레벨리오를 준비했습니다. 이동이 끝난 뒤 결과를 알립니다.'),
        F.new(key: 'msg_turn', type: :text, group: 'messages', label: '턴 결과', default: "%{turn}턴\n%{lines}"),
        F.new(key: 'msg_quiet', type: :text, group: 'messages', label: '조용한 턴', default: '복도는 조용합니다. 발소리 하나 들리지 않습니다.'),
        F.new(key: 'msg_stairs', type: :text, group: 'messages', label: '계단', default: '계단이 움직였습니다.'),
        F.new(key: 'msg_footprint', type: :text, group: 'messages', label: '발자국', default: '%{room} 근처에서 발자국이 발견되었습니다.'),
        F.new(key: 'msg_target', type: :text, group: 'messages', label: '목표 방문', default: '누군가 %{room}에 다녀갔습니다. (%{count}/%{total})'),
        F.new(key: 'msg_hint', type: :text, group: 'messages', label: '구역 힌트', default: '%{student}{은는} %{zone} 어딘가에 있습니다.'),
        F.new(key: 'msg_cloak', type: :text, group: 'messages', label: '망토', default: '지도에서 흔적이 희미해졌습니다.'),
        F.new(key: 'msg_revelio_found', type: :text, group: 'messages', label: '레벨리오: 있음', default: '%{player}{이가} 호메눔 레벨리오를 사용했습니다. 주변에 누군가 있습니다.'),
        F.new(key: 'msg_revelio_none', type: :text, group: 'messages', label: '레벨리오: 없음', default: '%{player}{이가} 호메눔 레벨리오를 사용했습니다. 아무도 없습니다.'),
        F.new(key: 'msg_caught', type: :text, group: 'messages', label: '체포', default: '%{player}{이가} %{room}에서 %{target}{을를} 붙잡았습니다. %{prefect}의 승리!'),
        F.new(key: 'msg_escaped', type: :text, group: 'messages', label: '학생 승리', default: '%{player}{이가} 목표 장소를 모두 다녀왔습니다. %{student}의 승리!'),
        F.new(key: 'msg_limit', type: :text, group: 'messages', label: '시간 초과', default: '%{turns}턴이 지났습니다. %{student}{은는} 목표를 채우지 못했습니다. %{prefect}의 승리!'),
      ]).freeze

      class << self
        def web?
          true
        end

        def max_opponents
          config['max_opponents'].to_i.clamp(1, 4)
        end

        def continues_on_timeout?
          true
        end
      end

      def start!
        width = config['width'].to_i.clamp(3, 8)
        height = config['height'].to_i.clamp(3, 8)
        count = width * height
        student = players.first
        prefects = players.drop(1)
        balanced = prefects.size >= config['balance_prefects'].to_i.clamp(1, 4)

        build_map!(width, height)
        corners = [0, width - 1, count - width, count - 1]
        start = corners.sample
        center = [(height / 2 * width) + (width / 2)]
        hubs = ((0...count).to_a - [start]).sort_by { |room| [distance_between(room, center.first, width), rand] }.first(prefects.size)
        near = adjacent(start, student: true)
        wanted = (balanced ? config['targets_reduced'] : config['targets']).to_i.clamp(1, 4)
        targets = ((0...count).to_a - [start, *hubs, *near]).sample([wanted, count - 2 - near.size].min)

        state.merge!(
          'positions' => { student.seat.to_s => start }.merge(prefects.each_with_index.to_h { |player, index| [player.seat.to_s, hubs[index]] }),
          'targets' => targets, 'visited' => [], 'clues' => [], 'cloak' => 0,
          'cloaks_left' => config['cloaks'].to_i.clamp(0, 5) + (balanced ? config['cloaks_bonus'].to_i.clamp(0, 5) : 0),
          'revelio_left' => prefects.to_h { |player| [player.seat.to_s, config['revelio'].to_i.clamp(0, 5)] },
          'phase' => 'student', 'moves' => {}, 'cloak_now' => false, 'revelio_now' => {}, 'log' => []
        )
        session.update!(turn: 1)
        post(render(config['msg_start'], student: config['student_name'], prefect: config['prefect_name'], player: student,
                                         players: prefects.map(&:name).join(', '), **Game::Config.turn_time))
        dm(student, render(config['msg_role_student'], student: config['student_name'], prefect: config['prefect_name'], targets: targets.map { |room| name_of(room) }.join(', ')))
        prefects.each { |player| dm(player, render(config['msg_role_prefect'], student: config['student_name'], prefect: config['prefect_name'])) }
        ask_student!
      end

      def handle(player, command, args, status)
        action = ACTIONS.find { |key| config["cmd_#{key}"] == command }
        return false if action.nil?
        return true unless require_dm!(player, status)

        case action
        when 'move' then submit_room!(player, args.join('/'))
        when 'hide' then submit_room!(player, nil)
        when 'cloak' then use_cloak!(player)
        else use_revelio!(player)
        end
        true
      end

      def timeout!
        if state['phase'] == 'student'
          state['moves'][players.first.seat.to_s] ||= { 'room' => state['positions'][players.first.seat.to_s] }
          session.save!
          ask_prefects!
        else
          resolve!
        end
      end

      def view_for(player)
        seat = player.seat.to_s
        student = student?(player)
        here = state['positions'][seat]
        my_turn = state['phase'] == (student ? 'student' : 'prefects')
        {
          map: true,
          width: state['width'], height: state['height'],
          rooms: (0...room_count).map { |index| { id: index, name: name_of(index), x: index % state['width'], y: index / state['width'] } },
          edges: edges.map { |a, b| { a: a, b: b, stairs: stairs?(a, b) } },
          secret: student ? state['secret'].map { |a, b| { a: a, b: b } } : [],
          role: student ? 'student' : 'prefect',
          role_name: student ? config['student_name'] : config['prefect_name'],
          me: player.seat,
          position: here,
          moves: my_turn ? adjacent(here, student: student) : [],
          tokens: players.filter_map do |other|
            next if !student && student?(other)

            { seat: other.seat, name: other.name, room: state['positions'][other.seat.to_s], student: student?(other), me: other.id == player.id }
          end,
          targets: student ? state['targets'].map { |room| { room: room, visited: state['visited'].include?(room) } } : [],
          clues: state['clues'].map { |clue| clue.merge('room_name' => clue['room'] && name_of(clue['room'])) },
          items: student ? { cloak: state['cloaks_left'].to_i } : { revelio: state['revelio_left'][seat].to_i },
          item_info: item_info,
          commands: ACTIONS.to_h { |key| [key, config["cmd_#{key}"]] },
          phase: state['phase'],
          my_turn: my_turn,
          cloak: state['cloak'].to_i,
          submitted: my_turn ? state['moves'].key?(seat) : true,
          waiting: waiting_on.map(&:name),
          turn: session.turn,
          max_turns: config['max_turns'].to_i,
          deadline_at: session.deadline_at&.iso8601,
          log: state['log'],
        }
      end

      # 카드(툿·방 맨 위): 목표 장소·위치는 담지 않는다 (사감도 보는 곳). 방문한 수와 공개된 단서만.
      def card_data
        {
          'targets_done' => Array(state['visited']).size,
          'targets_total' => Array(state['targets']).size,
          'clues' => Array(state['clues']).last(6).map { |clue| clue.merge('room_name' => clue['room'] && name_of(clue['room'])) },
          'log' => state['log'] || [],
          'max_turns' => config['max_turns'].to_i,
          'student_seat' => players.first&.seat,
          'student_name' => config['student_name'],
          'prefect_name' => config['prefect_name'],
          'phase' => state['phase'],
          'web' => true,
        }
      end

      def pending_seats
        waiting_on.map(&:seat)
      end

      # 웹 방 입력창 위 버튼: 이동·아이템은 지도 화면에서 하고, 여기엔 제자리만
      def card_actions
        seats = pending_seats
        seats.empty? ? [] : [Game::Card.action(config['cmd_hide'], seats: seats, dm: true, hint: '제자리에 머물러 이번 턴을 보냅니다.')]
      end

      def max_turns
        config['max_turns'].to_i
      end

      private

      def room_count
        state['width'] * state['height']
      end

      def name_of(room)
        ROOMS[room] || "복도 #{room - ROOMS.size + 1}"
      end

      def student?(player)
        player.seat == players.first.seat
      end

      def waiting_on
        if state['phase'] == 'student'
          state['moves'].key?(players.first.seat.to_s) ? [] : [players.first]
        else
          players.drop(1).reject { |player| state['moves'].key?(player.seat.to_s) }
        end
      end

      def item_info
        {
          cloak: "#{config['cmd_cloak']}: 이동을 정하기 전에 쓰면 #{config['cloak_turns'].to_i.clamp(1, 5)}턴 동안 발자국과 구역 힌트가 남지 않습니다. (학생)",
          revelio: "#{config['cmd_revelio']}: 이동이 끝난 뒤 주변 #{config['revelio_range'].to_i.clamp(1, 4)}칸 안에 학생이 있는지만 알려 줍니다. (사감, 사람마다 정해진 횟수)",
        }
      end

      # ── 지도 만들기 ──
      # 막힌 길·움직이는 계단(두 쪽 모두 연결이 유지되게)·비밀 통로 후보 중 열린 것
      def build_map!(width, height)
        state['width'] = width
        state['height'] = height
        grid = grid_edges(width, height)
        50.times do
          shuffled = grid.shuffle
          blocked = shuffled.first((grid.size * 0.12).round)
          stairs_a = shuffled[blocked.size, 3] || []
          stairs_b = shuffled[blocked.size + 3, 3] || []
          state.merge!('blocked' => blocked, 'stairs_a' => stairs_a, 'stairs_b' => stairs_b)
          next unless connected?(false) && connected?(true)

          break
        end
        candidates = (0...(width * height)).to_a.combination(2).select { |a, b| distance_between(a, b, width) >= [width, height].max - 1 && graph_distance(a, b) >= 4 }
        state['secret'] = candidates.sample(config['secret_passages'].to_i.clamp(0, 6))
      end

      def grid_edges(width, height)
        (0...(width * height)).flat_map do |room|
          x = room % width
          y = room / width
          list = []
          list << [room, room + 1] if x < width - 1
          list << [room, room + width] if y < height - 1
          list
        end
      end

      # 두 계단 상태 모두에서 모든 방이 이어지는가 (b: 계단 B 상태)
      def connected?(phase_b)
        links = edges_for(phase_b)
        seen = [0]
        queue = [0]
        until queue.empty?
          room = queue.shift
          links.each do |a, b|
            other = (a == room && b) || (b == room && a)
            next if other.nil? || other == false || seen.include?(other)

            seen << other
            queue << other
          end
        end
        seen.size == room_count
      end

      def distance_between(room_a, room_b, width)
        (room_a % width - room_b % width).abs + (room_a / width - room_b / width).abs
      end

      # 지금 길 기준 최단 방 수
      def graph_distance(room_a, room_b, links = edges_for(false))
        dist = { room_a => 0 }
        queue = [room_a]
        until queue.empty?
          room = queue.shift
          return dist[room] if room == room_b

          links.each do |a, b|
            other = (a == room && b) || (b == room && a)
            next if other.nil? || other == false || dist.key?(other)

            dist[other] = dist[room] + 1
            queue << other
          end
        end
        Float::INFINITY
      end

      def stairs_phase_b?
        ((session.turn - 1) / config['stairs_every'].to_i.clamp(1, 10)).odd?
      end

      def stairs?(a, b)
        (state['stairs_a'] + state['stairs_b']).any? { |pair| pair.sort == [a, b].sort }
      end

      def edges_for(phase_b)
        inactive = phase_b ? state['stairs_a'] : state['stairs_b']
        grid_edges(state['width'], state['height']).reject { |pair| state['blocked'].include?(pair) || inactive.include?(pair) }
      end

      def edges
        edges_for(stairs_phase_b?)
      end

      def adjacent(room, student:)
        links = edges + (student ? state['secret'] : [])
        links.filter_map { |a, b| (a == room && b) || (b == room && a) || nil }.uniq
      end

      def zone_of(room)
        x = room % state['width']
        y = room / state['width']
        "#{ZONES_X[[x * 3 / state['width'], 2].min]} #{ZONES_Y[[y * 3 / state['height'], 2].min]}"
      end

      # ── 턴: 학생 → 사감 팀 ──
      def ask_student!
        state['phase'] = 'student'
        state['moves'] = {}
        state['cloak_now'] = false
        state['revelio_now'] = {}
        student = players.first
        here = state['positions'][student.seat.to_s]
        remaining = state['targets'].reject { |room| state['visited'].include?(room) }
        dm(student, render(config['msg_ask_student'], turn: session.turn, room: name_of(here), rooms: adjacent(here, student: true).map { |room| name_of(room) }.join(', '),
                                                      move: config['cmd_move'], hide: config['cmd_hide'], cloak: config['cmd_cloak'], cloaks: state['cloaks_left'].to_i,
                                                      targets: remaining.map { |room| name_of(room) }.join(', ')))
        session.save!
        wait_for_turn!
      end

      def ask_prefects!
        state['phase'] = 'prefects'
        players.drop(1).each do |player|
          here = state['positions'][player.seat.to_s]
          dm(player, render(config['msg_ask_prefect'], turn: session.turn, room: name_of(here), rooms: adjacent(here, student: false).map { |room| name_of(room) }.join(', '),
                                                       move: config['cmd_move'], hide: config['cmd_hide'], revelio: config['cmd_revelio'], revelios: state['revelio_left'][player.seat.to_s].to_i))
        end
        session.save!
        wait_for_turn!
      end

      def room_from(arg)
        text = arg.to_s.strip
        return text.to_i if text.match?(/\A\d+\z/) && text.to_i < room_count

        squashed = text.delete(' ')
        (0...room_count).find { |room| name_of(room).delete(' ') == squashed }
      end

      def submit_room!(player, arg)
        seat = player.seat.to_s
        student = student?(player)
        return dm(player, render(config['msg_wrong_time'])) unless state['phase'] == (student ? 'student' : 'prefects')

        here = state['positions'][seat]
        room = arg.nil? ? here : room_from(arg)
        return dm(player, render(config['msg_bad_move'])) if room.nil? || (room != here && !adjacent(here, student: student).include?(room))

        state['moves'][seat] = { 'room' => room }
        session.save!
        dm(player, render(config['msg_chosen']))
        return unless waiting_on.empty?

        student ? ask_prefects! : resolve!
      end

      def use_cloak!(player)
        return dm(player, render(config['msg_wrong_time'])) unless student?(player) && state['phase'] == 'student'
        return dm(player, render(config['msg_no_item'], item: config['cmd_cloak'])) unless state['cloaks_left'].to_i.positive?
        return dm(player, render(config['msg_wrong_time'])) if state['cloak_now']

        state['cloaks_left'] -= 1
        state['cloak_now'] = true
        session.save!
        dm(player, render(config['msg_cloak_on'], turns: config['cloak_turns'].to_i.clamp(1, 5)))
      end

      def use_revelio!(player)
        seat = player.seat.to_s
        return dm(player, render(config['msg_wrong_time'])) if student?(player) || state['phase'] != 'prefects' || state['revelio_now'][seat]
        return dm(player, render(config['msg_no_item'], item: config['cmd_revelio'])) unless state['revelio_left'][seat].to_i.positive?

        state['revelio_left'][seat] -= 1
        state['revelio_now'][seat] = true
        session.save!
        dm(player, render(config['msg_revelio_on']))
      end

      def resolve!
        log = []
        student = players.first
        seat = student.seat.to_s
        from = state['positions'].dup
        moves = state['moves']

        if state['cloak_now']
          state['cloak'] = config['cloak_turns'].to_i.clamp(1, 5)
          log << render(config['msg_cloak'])
        end
        cloaked = state['cloak'].to_i.positive?

        players.each { |player| state['positions'][player.seat.to_s] = moves.dig(player.seat.to_s, 'room') || from[player.seat.to_s] }
        here = state['positions'][seat]

        used_secret = from[seat] != here && state['secret'].any? { |pair| pair.sort == [from[seat], here].sort }
        if used_secret && !cloaked
          state['clues'] << { 'turn' => session.turn, 'kind' => 'footprint', 'room' => here }
          log << render(config['msg_footprint'], room: name_of(here))
        end

        if state['targets'].include?(here) && state['visited'].exclude?(here)
          state['visited'] << here
          unless cloaked
            state['clues'] << { 'turn' => session.turn, 'kind' => 'target', 'room' => here }
          end
          log << render(config['msg_target'], room: name_of(here), count: state['visited'].size, total: state['targets'].size) unless cloaked
        end

        players.drop(1).each do |prefect|
          next unless state['revelio_now'][prefect.seat.to_s]

          near = graph_distance(state['positions'][prefect.seat.to_s], here, edges) <= config['revelio_range'].to_i.clamp(1, 4)
          state['clues'] << { 'turn' => session.turn, 'kind' => 'revelio', 'room' => state['positions'][prefect.seat.to_s], 'found' => near }
          log << render(config[near ? 'msg_revelio_found' : 'msg_revelio_none'], player: prefect)
        end

        catcher = players.drop(1).find do |prefect|
          now = state['positions'][prefect.seat.to_s]
          before = from[prefect.seat.to_s]
          now == here || (before == here && now == from[seat])
        end

        every = config['hint_every'].to_i.clamp(1, 10)
        if !cloaked && (session.turn % every).zero? && catcher.nil?
          state['clues'] << { 'turn' => session.turn, 'kind' => 'zone', 'zone' => zone_of(here) }
          log << render(config['msg_hint'], zone: zone_of(here), student: config['student_name'])
        end
        state['cloak'] = state['cloak'].to_i - 1 if cloaked

        log << render(config['msg_stairs']) if (session.turn % config['stairs_every'].to_i.clamp(1, 10)).zero?
        state['log'] = log
        state['moves'] = {}
        turn_text = render(config['msg_turn'], turn: session.turn, lines: (log.presence || [render(config['msg_quiet'])]).join("\n"))

        if catcher
          finish_team!(false, "#{turn_text}\n\n#{render(config['msg_caught'], player: catcher, target: student, room: name_of(here), prefect: config['prefect_name'])}")
        elsif state['visited'].size >= state['targets'].size
          finish_team!(true, "#{turn_text}\n\n#{render(config['msg_escaped'], player: student, student: config['student_name'])}")
        elsif session.turn >= config['max_turns'].to_i
          finish_team!(false, "#{turn_text}\n\n#{render(config['msg_limit'], turns: session.turn, prefect: config['prefect_name'], student: config['student_name'])}")
        else
          post(turn_text)
          session.update!(turn: session.turn + 1)
          ask_student!
        end
      end

      # 학생 승리면 학생만, 사감 승리면 사감 모두 이긴다
      def finish_team!(student_won, message)
        student = players.first
        winners = student_won ? [student] : players.drop(1)
        players.each { |player| player.update!(result: winners.include?(player) ? 'win' : 'lose') }
        session.update!(status: 'finished', finished_at: Time.now.utc, deadline_at: nil)
        reward_lines = give_rewards!

        if tournament?
          post([message, *reward_lines].join("\n\n"))
          Game::Tournament.finished!(session, winners.size == 1 ? winners.first : nil, draw: winners.size != 1)
          return
        end

        point_lines = winners.map { |player| Game::Points.give(session, player, config['points_win'], reason: "game:#{self.class.key}") }
        post([message, *point_lines.compact, *reward_lines].join("\n\n"))
      end
    end
  end
end
