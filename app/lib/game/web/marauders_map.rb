# frozen_string_literal: true

module Game
  module Web
    # 도둑 지도 (웹 전용, 학생 1 vs 사감 1~4). 신청한 사람이 학생, 태그한 사람들이 사감.
    #
    #   호그와트 방 25개 (5×5). 매 턴 모두 붙어 있는 방으로 한 칸(또는 제자리)을 웹에서 골라 동시에 움직인다.
    #   학생: 도둑 지도로 모두의 위치를 본다. 비밀 통로(학생만)를 쓸 수 있고, 투명 망토 1번(2턴 동안 단서 없음).
    #         목표 장소를 모두 들르면 승리.
    #   사감: 학생 위치는 모른다. 단서 — 비밀 통로로 나온 곳·목표 장소의 발자국, 3턴마다 대략 구역,
    #         사람마다 1번 호메눔 레벨리오(그 턴 학생이 있는 방을 정확히). 같은 방에 들어가거나 길에서 엇갈리면 체포.
    #   움직이는 계단: 3턴마다 대계단 주변 길이 바뀐다. 최대 턴이 지나면 사감 승리.
    class MaraudersMap < Game::Kinds::Base
      KEY = 'marauders_map'

      ROOMS = %w(
        천문탑 그리핀도르\ 휴게실 부엉이장 래번클로\ 탑 점술\ 교실
        도서관 금지된\ 구역 대계단 트로피실 필요의\ 방
        변신술\ 교실 마법약\ 교실 대연회장 현관\ 홀 의무실
        슬리데린\ 지하실 부엌 후플푸프\ 휴게실 안뜰 온실
        지하\ 통로 비밀의\ 방\ 입구 정문 해그리드\ 오두막 금지된\ 숲\ 입구
      ).freeze

      SIZE = 5
      # 막힌 길 (이웃이지만 이어지지 않음)
      BLOCKED = [[1, 6], [3, 4], [10, 15], [13, 14], [16, 21], [18, 23]].freeze
      # 움직이는 계단: 3턴마다 A ↔ B
      STAIRS_A = [[2, 7], [7, 12], [8, 13]].freeze
      STAIRS_B = [[6, 7], [7, 8], [11, 12]].freeze
      # 비밀 통로 (학생만)
      SECRET = [[0, 21], [5, 9], [16, 1], [8, 20], [14, 24]].freeze
      ZONES_X = %w(서쪽 가운데 동쪽).freeze
      ZONES_Y = %w(위층 가운데층 아래층).freeze

      FIELDS = (base_fields(name: '도둑 지도', command: '도둑지도', points_win: 10) + [
        F.new(key: 'max_opponents', type: :integer, default: 4, group: 'rules', label: '사감 최대 인원', hint: '1~4'),
        F.new(key: 'max_turns', type: :integer, default: 20, group: 'rules', label: '최대 턴', hint: '지나면 사감 승리'),
        F.new(key: 'targets', type: :integer, default: 2, group: 'rules', label: '학생이 들러야 하는 목표 장소 수'),
        F.new(key: 'hint_every', type: :integer, default: 3, group: 'rules', label: '대략 구역 힌트 (턴마다)'),
        F.new(key: 'cloak_turns', type: :integer, default: 2, group: 'rules', label: '투명 망토 지속 (턴)'),
        F.new(key: 'student_name', type: :string, default: '학생', group: 'rules', label: '학생 역할 이름'),
        F.new(key: 'prefect_name', type: :string, default: '사감', group: 'rules', label: '사감 역할 이름'),
        F.new(key: 'msg_start', type: :text, group: 'messages', label: '시작',
              default: "🗺️ %{game} 시작! %{student}: %{player} / %{prefect}: %{players}\n목표 장소: %{targets}\n진행은 웹에서: %{link}\n턴마다 %{seconds}초 안에 움직일 방을 골라 주세요."),
        F.new(key: 'msg_turn', type: :text, group: 'messages', label: '턴 결과', default: "%{turn}턴\n%{lines}"),
        F.new(key: 'msg_quiet', type: :text, group: 'messages', label: '조용한 턴', default: '복도는 조용하다… 발소리 하나 들리지 않는다.'),
        F.new(key: 'msg_stairs', type: :text, group: 'messages', label: '계단', default: '🪜 계단이 움직였다!'),
        F.new(key: 'msg_footprint', type: :text, group: 'messages', label: '발자국', default: '👣 %{room}에서 발자국이 발견되었다.'),
        F.new(key: 'msg_target', type: :text, group: 'messages', label: '목표 방문', default: '✨ 누군가 %{room}에 다녀갔다! (%{count}/%{total})'),
        F.new(key: 'msg_hint', type: :text, group: 'messages', label: '구역 힌트', default: '🔭 학생은 %{zone} 어딘가에 있다.'),
        F.new(key: 'msg_cloak', type: :text, group: 'messages', label: '망토', default: '🧥 지도에서 흔적이 희미해졌다…'),
        F.new(key: 'msg_revelio', type: :text, group: 'messages', label: '레벨리오', default: '🔦 %{player}의 호메눔 레벨리오! 학생은 %{room}에 있다.'),
        F.new(key: 'msg_caught', type: :text, group: 'messages', label: '체포', default: '🚨 %{player}{이가} %{room}에서 %{target}{을를} 붙잡았다! %{prefect}의 승리!'),
        F.new(key: 'msg_escaped', type: :text, group: 'messages', label: '학생 승리', default: '🗺️ %{player}{이가} 목표 장소를 모두 다녀왔다! "장난 끝." %{student}의 승리!'),
        F.new(key: 'msg_limit', type: :text, group: 'messages', label: '시간 초과', default: '%{turns}턴이 지났다. 학생은 기숙사로 돌아가지 못했다. %{prefect}의 승리!'),
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
        student = players.first
        prefects = players.drop(1)
        start = [0, 4, 20, 24].sample
        hub = [12, 7, 13, 11, 17]
        targets = (0...ROOMS.size).to_a.reject { |room| room == start || hub.include?(room) || adjacent(start, student: true).include?(room) }
                                   .sample(config['targets'].to_i.clamp(1, 4))
        state.merge!(
          'positions' => { student.seat.to_s => start }.merge(prefects.each_with_index.to_h { |player, index| [player.seat.to_s, hub[index % hub.size]] }),
          'targets' => targets, 'visited' => [], 'clues' => [], 'cloak' => 0, 'cloak_used' => false,
          'revelio_used' => [], 'moves' => {}, 'log' => []
        )
        session.update!(turn: 1)
        post(render(config['msg_start'], student: config['student_name'], prefect: config['prefect_name'], player: student,
                                         players: prefects.map(&:name).join(', '), targets: targets.map { |room| ROOMS[room] }.join(', '),
                                         link: Game::Web.session_url(session), **Game::Config.turn_time))
        wait_for_turn!
      end

      def handle(_player, _command, _args, _status)
        false
      end

      def timeout!
        resolve!
      end

      # 웹에서 고른 행동: path = [방 번호] (비우면 제자리), stance = 'cloak'(학생) / 'revelio'(사감)
      def submit_move!(player, path, stance)
        seat = player.seat.to_s
        here = state['positions'][seat]
        target = Array(path).first.to_s
        room = target.match?(/\A\d+\z/) ? target.to_i : here
        room = here unless room == here || adjacent(here, student: student?(player)).include?(room)

        move = { 'room' => room }
        move['cloak'] = true if stance == 'cloak' && student?(player) && !state['cloak_used']
        move['revelio'] = true if stance == 'revelio' && !student?(player) && state['revelio_used'].exclude?(player.seat)
        state['moves'][seat] = move
        session.save!
        resolve! if waiting_on.empty?
        true
      end

      def view_for(player)
        seat = player.seat.to_s
        student = student?(player)
        here = state['positions'][seat]
        {
          map: true,
          rooms: ROOMS.each_with_index.map { |name, index| { id: index, name: name, x: index % SIZE, y: index / SIZE } },
          edges: edges.map { |a, b| { a: a, b: b, stairs: stairs?(a, b) } },
          secret: student ? SECRET.map { |a, b| { a: a, b: b } } : [],
          role: student ? 'student' : 'prefect',
          role_name: student ? config['student_name'] : config['prefect_name'],
          me: player.seat,
          position: here,
          moves: adjacent(here, student: student),
          tokens: players.filter_map do |other|
            next if !student && student?(other)

            { seat: other.seat, name: other.name, room: state['positions'][other.seat.to_s], student: student?(other), me: other.id == player.id }
          end,
          targets: state['targets'].map { |room| { room: room, visited: state['visited'].include?(room) } },
          clues: state['clues'],
          cloak_available: student && !state['cloak_used'],
          cloak: state['cloak'].to_i,
          revelio_available: !student && state['revelio_used'].exclude?(player.seat),
          submitted: state['moves'].key?(seat),
          waiting: waiting_on.map(&:name),
          turn: session.turn,
          max_turns: config['max_turns'].to_i,
          deadline_at: session.deadline_at&.iso8601,
          log: state['log'],
        }
      end

      def card_data
        {
          'targets' => (state['targets'] || []).map { |room| { 'room' => ROOMS[room], 'visited' => Array(state['visited']).include?(room) } },
          'clues' => Array(state['clues']).last(6).map { |clue| clue.merge('room_name' => clue['room'] && ROOMS[clue['room']]) },
          'log' => state['log'] || [],
          'max_turns' => config['max_turns'].to_i,
          'student_seat' => players.first&.seat,
          'student_name' => config['student_name'],
          'prefect_name' => config['prefect_name'],
          'chosen' => (state['moves'] || {}).keys,
          'web' => true,
        }
      end

      private

      def student?(player)
        player.seat == players.first.seat
      end

      def waiting_on
        players.reject { |player| state['moves'].key?(player.seat.to_s) }
      end

      def stairs_phase_b?
        ((session.turn - 1) / 3).odd?
      end

      def stairs?(a, b)
        (STAIRS_A + STAIRS_B).any? { |pair| pair.sort == [a, b].sort }
      end

      # 지금 이어진 길 (막힌 길 빼고, 계단은 지금 쪽만)
      def edges
        grid = (0...ROOMS.size).flat_map do |room|
          x = room % SIZE
          y = room / SIZE
          list = []
          list << [room, room + 1] if x < SIZE - 1
          list << [room, room + SIZE] if y < SIZE - 1
          list
        end
        inactive = stairs_phase_b? ? STAIRS_A : STAIRS_B
        grid.reject { |pair| BLOCKED.include?(pair.sort) || inactive.include?(pair.sort) } + (stairs_phase_b? ? STAIRS_B : STAIRS_A)
      end

      def adjacent(room, student:)
        links = edges + (student ? SECRET : [])
        links.filter_map { |a, b| (a == room && b) || (b == room && a) || nil }.uniq
      end

      def zone_of(room)
        x = room % SIZE
        y = room / SIZE
        "#{ZONES_X[[x * 3 / SIZE, 2].min]} #{ZONES_Y[[y * 3 / SIZE, 2].min]}"
      end

      def resolve!
        log = []
        student = players.first
        seat = student.seat.to_s
        from = state['positions'].dup
        moves = state['moves']

        if moves.dig(seat, 'cloak')
          state['cloak'] = config['cloak_turns'].to_i.clamp(1, 5)
          state['cloak_used'] = true
          log << render(config['msg_cloak'])
        end
        cloaked = state['cloak'].to_i.positive?

        players.each { |player| state['positions'][player.seat.to_s] = moves.dig(player.seat.to_s, 'room') || from[player.seat.to_s] }
        here = state['positions'][seat]

        used_secret = SECRET.any? { |pair| pair.sort == [from[seat], here].sort } && from[seat] != here
        if used_secret && !cloaked
          state['clues'] << { 'turn' => session.turn, 'kind' => 'footprint', 'room' => here }
          log << render(config['msg_footprint'], room: ROOMS[here])
        end

        if state['targets'].include?(here) && state['visited'].exclude?(here)
          state['visited'] << here
          state['clues'] << { 'turn' => session.turn, 'kind' => 'target', 'room' => here }
          log << render(config['msg_target'], room: ROOMS[here], count: state['visited'].size, total: state['targets'].size)
        end

        players.drop(1).each do |prefect|
          next unless moves.dig(prefect.seat.to_s, 'revelio')

          state['revelio_used'] << prefect.seat
          state['clues'] << { 'turn' => session.turn, 'kind' => 'revelio', 'room' => here }
          log << render(config['msg_revelio'], player: prefect, room: ROOMS[here])
        end

        catcher = players.drop(1).find do |prefect|
          now = state['positions'][prefect.seat.to_s]
          before = from[prefect.seat.to_s]
          now == here || (before == here && now == from[seat])
        end

        every = config['hint_every'].to_i.clamp(1, 10)
        if !cloaked && (session.turn % every).zero? && catcher.nil?
          state['clues'] << { 'turn' => session.turn, 'kind' => 'zone', 'zone' => zone_of(here) }
          log << render(config['msg_hint'], zone: zone_of(here))
        end
        state['cloak'] = state['cloak'].to_i - 1 if cloaked

        log << render(config['msg_stairs']) if (session.turn % 3).zero?
        state['log'] = log
        state['moves'] = {}
        turn_text = render(config['msg_turn'], turn: session.turn, lines: (log.presence || [render(config['msg_quiet'])]).join("\n"))

        if catcher
          finish_team!(false, "#{turn_text}\n\n#{render(config['msg_caught'], player: catcher, target: student, room: ROOMS[here], prefect: config['prefect_name'])}")
        elsif state['visited'].size >= state['targets'].size
          finish_team!(true, "#{turn_text}\n\n#{render(config['msg_escaped'], player: student, student: config['student_name'])}")
        elsif session.turn >= config['max_turns'].to_i
          finish_team!(false, "#{turn_text}\n\n#{render(config['msg_limit'], turns: session.turn, prefect: config['prefect_name'])}")
        else
          post(turn_text)
          session.update!(turn: session.turn + 1)
          wait_for_turn!
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
