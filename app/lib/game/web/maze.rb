# frozen_string_literal: true

module Game
  module Web
    # 트라이위저드 미로 (웹 전용, 2~4명). 진행은 웹 컨텐츠 화면(/system/sessions/:id)에서 하고,
    # 시스템 계정은 시작·턴마다 일어난 일·결과만 툿으로 중계한다.
    #
    #   [미로] @상대 (@상대 …)   신청 → 모두 [수락]하면 시작
    #   턴마다 각자 웹에서 최대 N칸 경로와 태도(협력/방해)를 고른다 → 모두 고르면(또는 시간이 되면) 동시에 움직인다
    #   시야는 주변 2칸 (루모스를 주우면 몇 턴 동안 넓어짐), 지나간 칸은 지도에 남는다
    #   함정: 다음 턴 쉼 / 마법 생물: 확률로 한 칸 밀려남 / 포인트 미: 우승컵 방향 / 루모스: 시야
    #   같은 칸에서 만나면 태도로 결과 (둘 다 협력 → 다음 턴 한 칸 더, 한쪽 방해 → 상대 쉼·방해한 쪽 '적대', 둘 다 방해 → 둘 다 쉼)
    #   우승컵 칸에 먼저 닿은 사람 승리 (같은 턴에 여럿이면 무승부)
    class Maze < Game::Kinds::Base
      KEY = 'maze'

      DIRS = { 'N' => [0, -1, 1, 4], 'E' => [1, 0, 2, 8], 'S' => [0, 1, 4, 1], 'W' => [-1, 0, 8, 2] }.freeze
      ITEMS = %w(point_me lumos).freeze
      STANCES = %w(cooperate hinder).freeze

      FIELDS = (base_fields(name: '트라이위저드 미로', command: '미로', points_win: 10) + [
        F.new(key: 'size', type: :integer, default: 15, group: 'rules', label: '미로 크기 (칸)', hint: '홀수, 9~21'),
        F.new(key: 'max_opponents', type: :integer, default: 3, group: 'rules', label: '함께 태그할 수 있는 상대 수', hint: '1~3 (최대 4명)'),
        F.new(key: 'steps', type: :integer, default: 2, group: 'rules', label: '한 턴에 움직이는 칸 수'),
        F.new(key: 'vision', type: :integer, default: 2, group: 'rules', label: '시야 (칸)'),
        F.new(key: 'max_turns', type: :integer, default: 40, group: 'rules', label: '최대 턴', hint: '넘으면 무승부'),
        F.new(key: 'traps', type: :integer, default: 8, group: 'rules', label: '함정 수'),
        F.new(key: 'creatures', type: :integer, default: 6, group: 'rules', label: '마법 생물 수'),
        F.new(key: 'creature_block', type: :integer, default: 50, group: 'rules', label: '마법 생물이 막을 확률 (%)'),
        F.new(key: 'point_me', type: :integer, default: 2, group: 'rules', label: '포인트 미 (우승컵 방향) 수'),
        F.new(key: 'lumos', type: :integer, default: 2, group: 'rules', label: '루모스 (시야 +2) 수'),
        F.new(key: 'lumos_turns', type: :integer, default: 3, group: 'rules', label: '루모스 지속 (턴)'),
        F.new(key: 'creature_names', type: :lines, group: 'flavors', label: '마법 생물 (줄마다 하나)', default: %w(스크루트 스핑크스 보가트 아크로맨투라)),
        F.new(key: 'msg_start', type: :text, group: 'messages', label: '시작',
              default: "🏆 %{game} 시작! %{players}\n미로 한가운데 우승컵이 있습니다. 진행은 웹에서: %{link}\n턴마다 %{minutes}분 안에 길과 태도(협력/방해)를 골라 주세요."),
        F.new(key: 'msg_turn', type: :text, group: 'messages', label: '턴 결과', default: "%{turn}턴\n%{lines}"),
        F.new(key: 'msg_quiet', type: :text, group: 'messages', label: '조용한 턴', default: '모두 미로 속을 조심스럽게 나아갔다.'),
        F.new(key: 'msg_trap', type: :text, group: 'messages', label: '함정', default: '%{player}{이가} 함정에 걸렸다! (다음 턴 쉼)'),
        F.new(key: 'msg_creature_block', type: :text, group: 'messages', label: '생물에게 막힘', default: '%{player}{이가} %{creature}에게 가로막혀 물러났다.'),
        F.new(key: 'msg_creature_win', type: :text, group: 'messages', label: '생물 물리침', default: '%{player}{이가} %{creature}{을를} 물리쳤다!'),
        F.new(key: 'msg_item', type: :text, group: 'messages', label: '아이템', default: '%{player}{이가} %{item}{을를} 주웠다.'),
        F.new(key: 'msg_meet_coop', type: :text, group: 'messages', label: '만남: 협력', default: '%{player}{과와} %{target}{이가} 손을 잡았다. (다음 턴 한 칸 더)'),
        F.new(key: 'msg_meet_hinder', type: :text, group: 'messages', label: '만남: 방해', default: '%{player}{이가} %{target}{을를} 방해했다! (%{target} 쉼)'),
        F.new(key: 'msg_meet_both', type: :text, group: 'messages', label: '만남: 서로 방해', default: '%{player}{과와} %{target}{이가} 서로 주문을 퍼부었다. (둘 다 쉼)'),
        F.new(key: 'msg_win', type: :text, group: 'messages', label: '우승', default: '🏆 %{winner}{이가} 우승컵을 손에 넣었다! %{turn}턴 만의 승리!'),
        F.new(key: 'msg_tie', type: :text, group: 'messages', label: '동시 도착', default: '🏆 %{players}{이가} 동시에 우승컵을 잡았다! 무승부.'),
        F.new(key: 'msg_limit', type: :text, group: 'messages', label: '최대 턴', default: '%{turns}턴이 지나도록 아무도 우승컵에 닿지 못했다. 무승부.'),
      ]).freeze

      ITEM_NAMES = { 'point_me' => '포인트 미', 'lumos' => '루모스' }.freeze

      class << self
        def web?
          true
        end

        def max_opponents
          config['max_opponents'].to_i.clamp(1, 3)
        end

        # 시간 초과는 그 턴 제자리 (규칙의 일부)
        def continues_on_timeout?
          true
        end
      end

      def start!
        size = config['size'].to_i.clamp(9, 21)
        size += 1 if size.even?
        cells = carve(size)
        center = [size / 2, size / 2]
        corners = [[0, 0], [size - 1, size - 1], [size - 1, 0], [0, size - 1]]
        positions = players.each_with_index.to_h { |player, index| [player.seat.to_s, corners[index]] }

        reserved = corners + [center]
        free = (0...size).to_a.product((0...size).to_a).shuffle - reserved
        take = ->(count) { free.shift(count.to_i.clamp(0, free.size)) }
        items = ITEMS.flat_map { |item| take.call(config[item]).map { |(x, y)| [x, y, item] } }

        state.merge!(
          'size' => size, 'cells' => cells, 'cup' => center, 'positions' => positions,
          'traps' => take.call(config['traps']),
          'creatures' => take.call(config['creatures']).map { |(x, y)| [x, y, (config['creature_names'].presence || ['마법 생물']).sample] },
          'items' => items, 'moves' => {}, 'log' => [],
          'status' => players.to_h { |player| [player.seat.to_s, {}] },
          'seen' => players.to_h { |player| [player.seat.to_s, []] }
        )
        players.each { |player| reveal!(player.seat.to_s) }
        session.update!(turn: 1)
        post(render(config['msg_start'], players: players.map(&:name).join(', '), link: link, minutes: common['turn_minutes']))
        wait_for_turn!
      end

      # 웹 전용: 툿 명령어는 받지 않는다 (진행 화면의 이동 버튼 → submit_move!)
      def handle(_player, _command, _args, _status)
        false
      end

      def timeout!
        resolve!
      end

      # 웹에서 고른 이동: path = ['N', 'E'], stance = cooperate/hinder. 모두 고르면 바로 진행.
      def submit_move!(player, path, stance)
        seat = player.seat.to_s
        path = Array(path).map(&:to_s).select { |dir| DIRS.key?(dir) }.first(max_steps(seat))
        state['moves'][seat] = { 'path' => path, 'stance' => STANCES.include?(stance) ? stance : 'cooperate' }
        session.save!
        resolve! if waiting_on.empty?
        true
      end

      # 이 사람에게 보이는 미로 (웹 진행 화면)
      def view_for(player)
        seat = player.seat.to_s
        x, y = state['positions'][seat]
        seen = state['seen'][seat]
        vision = vision_of(seat)
        visible = ->(cx, cy) { (cx - x).abs <= vision && (cy - y).abs <= vision }
        status = state['status'][seat] || {}

        {
          size: state['size'],
          me: seat.to_i,
          position: [x, y],
          cells: seen.to_h { |index| [index, state['cells'][index]] },
          visible: visible_indexes(x, y, vision),
          cup: seen.include?(index_of(*state['cup'])) ? state['cup'] : nil,
          cup_direction: status['point_me'] ? direction_to(x, y, *state['cup']) : nil,
          items: state['items'].select { |ix, iy, _| visible.call(ix, iy) }.map { |ix, iy, item| { x: ix, y: iy, item: item, name: ITEM_NAMES[item] } },
          creatures: state['creatures'].select { |cx, cy, _| visible.call(cx, cy) }.map { |cx, cy, name| { x: cx, y: cy, name: name } },
          others: players.reject { |other| other.id == player.id }.filter_map do |other|
            ox, oy = state['positions'][other.seat.to_s]
            next unless visible.call(ox, oy)

            { seat: other.seat, name: other.name, x: ox, y: oy, hostile: state['status'].dig(other.seat.to_s, 'hostile') ? true : false }
          end,
          steps: max_steps(seat),
          stunned: status['stunned'].to_i.positive?,
          lumos: status['lumos'].to_i,
          submitted: state['moves'].key?(seat),
          waiting: waiting_on.map { |other| other.name },
          turn: session.turn,
          deadline_at: session.deadline_at&.iso8601,
          log: state['log'],
        }
      end

      def card_data
        {
          'size' => state['size'],
          'max_turns' => config['max_turns'].to_i,
          'log' => state['log'] || [],
          'status' => (state['status'] || {}).transform_values { |value| value.slice('stunned', 'hostile', 'boost', 'lumos') },
          'chosen' => (state['moves'] || {}).keys,
          'web' => true,
        }
      end

      private

      def link
        Game::Web.session_url(session)
      end

      def max_steps(seat)
        base = config['steps'].to_i.clamp(1, 4)
        state.dig('status', seat, 'boost') ? base + 1 : base
      end

      def vision_of(seat)
        base = config['vision'].to_i.clamp(1, 5)
        state.dig('status', seat, 'lumos').to_i.positive? ? base + 2 : base
      end

      def stunned?(seat)
        state.dig('status', seat, 'stunned').to_i.positive?
      end

      # 이번 턴에 아직 고르지 않은 사람 (쉬는 사람 제외)
      def waiting_on
        players.reject { |player| stunned?(player.seat.to_s) || state['moves'].key?(player.seat.to_s) }
      end

      def index_of(x, y)
        (y * state['size']) + x
      end

      def visible_indexes(x, y, vision)
        size = state['size']
        ((y - vision)..(y + vision)).flat_map do |cy|
          ((x - vision)..(x + vision)).filter_map { |cx| (cy * size) + cx if cx.between?(0, size - 1) && cy.between?(0, size - 1) }
        end
      end

      def reveal!(seat)
        x, y = state['positions'][seat]
        state['seen'][seat] = (state['seen'][seat] | visible_indexes(x, y, vision_of(seat)))
      end

      def direction_to(x, y, tx, ty)
        dx = tx <=> x
        dy = ty <=> y
        { [0, -1] => '↑', [1, -1] => '↗', [1, 0] => '→', [1, 1] => '↘', [0, 1] => '↓', [-1, 1] => '↙', [-1, 0] => '←', [-1, -1] => '↖', [0, 0] => '★' }[[dx, dy]]
      end

      # 미로 만들기: 길 파기(깊이 우선) + 벽 몇 개를 더 터서 갈림길. cells[i] = 열린 방향 비트 (N1 E2 S4 W8)
      def carve(size)
        cells = Array.new(size * size, 0)
        visited = Array.new(size * size, false)
        stack = [[rand(size), rand(size)]]
        visited[(stack[0][1] * size) + stack[0][0]] = true
        until stack.empty?
          x, y = stack.last
          options = DIRS.values.filter_map do |dx, dy, bit, back|
            nx = x + dx
            ny = y + dy
            [nx, ny, bit, back] if nx.between?(0, size - 1) && ny.between?(0, size - 1) && !visited[(ny * size) + nx]
          end
          if options.empty?
            stack.pop
            next
          end
          nx, ny, bit, back = options.sample
          cells[(y * size) + x] |= bit
          cells[(ny * size) + nx] |= back
          visited[(ny * size) + nx] = true
          stack << [nx, ny]
        end

        (size * size / 10).times do
          x = rand(size - 1)
          y = rand(size - 1)
          dx, dy, bit, back = DIRS[%w(E S).sample]
          cells[(y * size) + x] |= bit
          cells[((y + dy) * size) + x + dx] |= back
        end
        cells
      end

      def open?(x, y, dir)
        (state['cells'][index_of(x, y)] & DIRS[dir][2]).positive?
      end

      def resolve!
        log = []
        status = state['status']
        moved = []

        players.each do |player|
          seat = player.seat.to_s
          if stunned?(seat)
            status[seat]['stunned'] -= 1
            next
          end

          status[seat].delete('boost')
          walk!(player, Array(state.dig('moves', seat, 'path')), log)
          status[seat]['lumos'] -= 1 if status[seat]['lumos'].to_i.positive?
          moved << player
        end

        meet!(moved, log)
        players.each { |player| reveal!(player.seat.to_s) }
        state['log'] = log
        state['moves'] = {}

        reached = players.select { |player| state['positions'][player.seat.to_s] == state['cup'] }
        lines = log.presence || [render(config['msg_quiet'])]
        turn_text = render(config['msg_turn'], turn: session.turn, lines: lines.join("\n"))

        if reached.size == 1
          finish!(winner: reached.first, message: "#{turn_text}\n\n#{render(config['msg_win'], winner: reached.first, turn: session.turn)}")
        elsif reached.size > 1
          finish!(draw: true, message: "#{turn_text}\n\n#{render(config['msg_tie'], players: reached.map(&:name).join(', '))}")
        elsif session.turn >= config['max_turns'].to_i
          finish!(draw: true, message: "#{turn_text}\n\n#{render(config['msg_limit'], turns: session.turn)}")
        else
          post(turn_text)
          session.update!(turn: session.turn + 1)
          wait_for_turn!
        end
      end

      def walk!(player, path, log)
        seat = player.seat.to_s
        path.each do |dir|
          x, y = state['positions'][seat]
          break unless open?(x, y, dir)

          dx, dy = DIRS[dir]
          nx = x + dx
          ny = y + dy

          creature = state['creatures'].find { |cx, cy, _| cx == nx && cy == ny }
          if creature
            if rand(100) < config['creature_block'].to_i
              log << render(config['msg_creature_block'], player: player, creature: creature[2])
              break
            end
            state['creatures'].delete(creature)
            log << render(config['msg_creature_win'], player: player, creature: creature[2])
          end

          state['positions'][seat] = [nx, ny]

          item = state['items'].find { |ix, iy, _| ix == nx && iy == ny }
          if item
            state['items'].delete(item)
            pick_up!(seat, item[2])
            log << render(config['msg_item'], player: player, item: ITEM_NAMES[item[2]])
          end

          next unless state['traps'].include?([nx, ny])

          state['traps'].delete([nx, ny])
          state['status'][seat]['stunned'] = 1
          log << render(config['msg_trap'], player: player)
          break
        end
      end

      def pick_up!(seat, item)
        case item
        when 'point_me' then state['status'][seat]['point_me'] = true
        when 'lumos' then state['status'][seat]['lumos'] = config['lumos_turns'].to_i.clamp(1, 10)
        end
      end

      # 같은 칸에 선 두 사람: 태도로 결과
      def meet!(moved, log)
        moved.combination(2).each do |a, b|
          next unless state['positions'][a.seat.to_s] == state['positions'][b.seat.to_s]

          stance_a = state.dig('moves', a.seat.to_s, 'stance') || 'cooperate'
          stance_b = state.dig('moves', b.seat.to_s, 'stance') || 'cooperate'
          status = state['status']
          if stance_a == 'cooperate' && stance_b == 'cooperate'
            status[a.seat.to_s]['boost'] = true
            status[b.seat.to_s]['boost'] = true
            log << render(config['msg_meet_coop'], player: a, target: b)
          elsif stance_a == 'hinder' && stance_b == 'hinder'
            status[a.seat.to_s]['stunned'] = 1
            status[b.seat.to_s]['stunned'] = 1
            status[a.seat.to_s]['hostile'] = true
            status[b.seat.to_s]['hostile'] = true
            log << render(config['msg_meet_both'], player: a, target: b)
          else
            hinderer, victim = stance_a == 'hinder' ? [a, b] : [b, a]
            status[victim.seat.to_s]['stunned'] = 1
            status[hinderer.seat.to_s]['hostile'] = true
            log << render(config['msg_meet_hinder'], player: hinderer, target: victim)
          end
        end
      end
    end
  end
end
