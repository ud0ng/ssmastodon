# frozen_string_literal: true

module Game
  module Web
    # 트라이위저드 미로 (웹 전용, 2~4명). 지도는 웹 컨텐츠 화면(/system/sessions/:id)에서 보고,
    # 행동은 마법 결투처럼 시스템에게 DM 으로 보낸다 (웹 지도에서 칸을 누르면 DM 이 자동으로 나간다).
    # 시스템 계정은 모두 고른 뒤 그 턴에 일어난 일만 툿으로 공개한다.
    #
    #   [미로] @상대 (@상대 …)   신청 → 모두 [수락]하면 시작
    #   턴: ① 이동(최대 N칸, 시야 안) ② 생물과 마주치면 주문 대결 ③ 다른 참가자와 같은 칸·옆 칸이면 협력/방해(적대자는 주문 대결)
    #   시야는 주변 2칸(루모스로 +1), 지나온 칸은 지도에 남는다. 우승컵 위치는 모르고, 포트키로 방향만 한 번 알 수 있다.
    #   함정: 밟으면 1턴 쉼 / 마법 생물: 이기면 다음 턴 한 칸 더·지면 부상(1턴 쉼)·비기면 지나감
    #   방해한 상대는 '적대'로 공개되고, 적대자와 다시 만나면 주문 대결 (이기면 상대 지도를 얻고, 지면 부상(2턴 쉼), 비기면 둘 다 1턴 쉼)
    #   우승컵 칸에 먼저 닿은 사람 승리 (같은 턴에 여럿이면 공동 우승, 점수는 나눈다)
    class Maze < Game::Kinds::Base
      KEY = 'maze'

      include Game::Events::Recruiting

      DIRS = { 'N' => [0, -1, 1, 4], 'E' => [1, 0, 2, 8], 'S' => [0, 1, 4, 1], 'W' => [-1, 0, 8, 2] }.freeze
      DIR_NAMES = { '북' => 'N', '동' => 'E', '남' => 'S', '서' => 'W' }.freeze
      SPELLS = %w(attack disarm defend).freeze
      BEATS = { 'attack' => 'disarm', 'disarm' => 'defend', 'defend' => 'attack' }.freeze
      STANCES = %w(cooperate hinder).freeze
      ACTIONS = %w(move stay portkey lumos cooperate hinder attack disarm defend).freeze
      # 같은 사람과 다시 만나기까지 쉬는 턴 (만난 턴 포함)
      MEET_COOLDOWN = 3

      FIELDS = (base_fields(name: '트라이위저드 미로', command: '미로', points_win: 10) + [
        F.new(key: 'width', type: :integer, default: 15, group: 'rules', label: '지도 가로 (칸)', hint: '7~31'),
        F.new(key: 'height', type: :integer, default: 15, group: 'rules', label: '지도 세로 (칸)', hint: '7~31'),
        F.new(key: 'max_opponents', type: :integer, default: 3, group: 'rules', label: '함께 태그할 수 있는 상대 수', hint: '1~3 (최대 4명)'),
        F.new(key: 'steps', type: :integer, default: 2, group: 'rules', label: '한 턴에 움직이는 칸 수'),
        F.new(key: 'vision', type: :integer, default: 2, group: 'rules', label: '시야 (칸)'),
        F.new(key: 'max_turns', type: :integer, default: 40, group: 'rules', label: '최대 턴', hint: '넘으면 무승부'),
        F.new(key: 'traps', type: :integer, default: 8, group: 'rules', label: '함정 수'),
        F.new(key: 'creatures', type: :integer, default: 6, group: 'rules', label: '마법 생물 수'),
        F.new(key: 'portkey', type: :integer, default: 1, group: 'rules', label: '포트키 소지 개수', hint: '시작할 때 한 사람이 가지는 수 (우승컵 방향을 한 번 알려 줌)'),
        F.new(key: 'lumos', type: :integer, default: 1, group: 'rules', label: '루모스 소지 개수', hint: '시작할 때 한 사람이 가지는 수 (시야 넓히기)'),
        F.new(key: 'lumos_bonus', type: :integer, default: 1, group: 'rules', label: '루모스 시야 증가 (칸)'),
        F.new(key: 'lumos_turns', type: :integer, default: 3, group: 'rules', label: '루모스 지속 (턴)'),
        F.new(key: 'cmd_move', type: :string, default: '이동', group: 'commands', label: '이동 명령어', hint: '[이동/동/남] 처럼 방향(북·동·남·서)을 이어서'),
        F.new(key: 'cmd_stay', type: :string, default: '대기', group: 'commands', label: '제자리 명령어'),
        F.new(key: 'cmd_portkey', type: :string, default: '포트키', group: 'commands', label: '포트키 명령어'),
        F.new(key: 'cmd_lumos', type: :string, default: '루모스', group: 'commands', label: '루모스 명령어'),
        F.new(key: 'cmd_cooperate', type: :string, default: '협력', group: 'commands', label: '협력 명령어'),
        F.new(key: 'cmd_hinder', type: :string, default: '방해', group: 'commands', label: '방해 명령어'),
        F.new(key: 'cmd_attack', type: :string, default: '공격', group: 'commands', label: '공격 명령어'),
        F.new(key: 'cmd_disarm', type: :string, default: '무장해제', group: 'commands', label: '무장해제 명령어'),
        F.new(key: 'cmd_defend', type: :string, default: '방어', group: 'commands', label: '방어 명령어'),
        F.new(key: 'creature_names', type: :lines, group: 'flavors', label: '마법 생물 (줄마다 하나)', default: %w(스크루트 스핑크스 보가트 아크로맨투라)),
        F.new(key: 'msg_start', type: :text, group: 'messages', label: '시작',
              default: "%{game} 시작! %{players}\n미로 한가운데에 우승컵이 있습니다. 지도는 이 컨텐츠 방에서 볼 수 있습니다.\n턴마다 %{seconds}초 안에 이동할 곳을 골라 주세요."),
        F.new(key: 'msg_ask', type: :text, group: 'messages', label: 'DM: 이동 고르기',
              default: "%{turn}턴 | 이동할 곳을 골라 주세요. (최대 %{steps}칸)\n지도에서 칸을 누르거나 [%{move}/동/남] 처럼 보내 주세요.\n제자리: [%{stay}]\n보유: %{items}"),
        F.new(key: 'msg_rest', type: :text, group: 'messages', label: 'DM: 쉬는 턴', default: '이번 턴은 쉽니다.'),
        F.new(key: 'msg_chosen', type: :text, group: 'messages', label: 'DM: 선택 확인', default: '선택했습니다. 다른 참가자를 기다립니다.'),
        F.new(key: 'msg_bad_move', type: :text, group: 'messages', label: 'DM: 갈 수 없는 길', default: '갈 수 없는 길입니다. 지도에서 이동할 곳을 다시 골라 주세요.'),
        F.new(key: 'msg_wrong_time', type: :text, group: 'messages', label: 'DM: 지금은 할 수 없음', default: '지금은 할 수 없는 선택입니다.'),
        F.new(key: 'msg_no_item', type: :text, group: 'messages', label: 'DM: 아이템 없음', default: '%{item}{이가} 없습니다.'),
        F.new(key: 'msg_portkey', type: :text, group: 'messages', label: 'DM: 포트키 사용', default: '포트키가 우승컵의 방향을 가리킵니다: %{direction}'),
        F.new(key: 'msg_lumos', type: :text, group: 'messages', label: 'DM: 루모스 사용', default: '루모스! %{turns}턴 동안 시야가 넓어집니다.'),
        F.new(key: 'msg_fight_ask', type: :text, group: 'messages', label: 'DM: 마법 생물 대결',
              default: "%{creature}{과와} 마주쳤습니다!\n[%{attack}] · [%{disarm}] · [%{defend}] 중 하나를 골라 주세요."),
        F.new(key: 'msg_stance_ask', type: :text, group: 'messages', label: 'DM: 참가자와 마주침',
              default: "%{players}{과와} 마주쳤습니다.\n[%{cooperate}] 또는 [%{hinder}]를 골라 주세요."),
        F.new(key: 'msg_hostile_ask', type: :text, group: 'messages', label: 'DM: 적대자와 마주침',
              default: "적대하는 %{players}{과와} 마주쳤습니다!\n[%{attack}] · [%{disarm}] · [%{defend}] 중 하나를 골라 주세요."),
        F.new(key: 'msg_turn', type: :text, group: 'messages', label: '턴 결과', default: "%{turn}턴\n%{lines}"),
        F.new(key: 'msg_quiet', type: :text, group: 'messages', label: '조용한 턴', default: '모두 미로 속을 조심스럽게 나아갔습니다.'),
        F.new(key: 'msg_trap', type: :text, group: 'messages', label: '함정', default: '%{player}{이가} 함정을 밟았습니다. (1턴 쉼)'),
        F.new(key: 'msg_creature_win', type: :text, group: 'messages', label: '생물 물리침', default: '%{player}{이가} %{creature}{을를} 물리쳤습니다. (다음 턴 한 칸 더)'),
        F.new(key: 'msg_creature_lose', type: :text, group: 'messages', label: '생물에게 당함', default: '%{player}{이가} %{creature}에게 당해 부상을 입었습니다. (1턴 쉼)'),
        F.new(key: 'msg_creature_draw', type: :text, group: 'messages', label: '생물과 비김', default: '%{player}{이가} %{creature}{을를} 지나쳤습니다.'),
        F.new(key: 'msg_meet_coop', type: :text, group: 'messages', label: '만남: 서로 협력', default: '%{player}{과와} %{target}{이가} 지도를 나눴습니다.'),
        F.new(key: 'msg_meet_hinder', type: :text, group: 'messages', label: '만남: 한쪽 방해', default: '%{player}{이가} %{target}{을를} 방해했습니다. (%{target} 1턴 쉼)'),
        F.new(key: 'msg_meet_both', type: :text, group: 'messages', label: '만남: 서로 방해', default: '%{player}{과와} %{target}{이가} 서로를 방해했습니다. (둘 다 1턴 쉼)'),
        F.new(key: 'msg_fight_win', type: :text, group: 'messages', label: '적대 대결: 승리', default: '%{winner}{이가} %{loser}{을를} 제압하고 지도를 얻었습니다. (%{loser} 부상, 2턴 쉼)'),
        F.new(key: 'msg_fight_draw', type: :text, group: 'messages', label: '적대 대결: 무승부', default: '%{player}{과와} %{target}{의} 주문이 맞부딪혔습니다. (둘 다 1턴 쉼)'),
        F.new(key: 'msg_win', type: :text, group: 'messages', label: '우승', default: '%{winner}{이가} 우승컵을 손에 넣었습니다. %{turn}턴 만의 승리!'),
        F.new(key: 'msg_tie', type: :text, group: 'messages', label: '동시 도착', default: '%{players}{이가} 동시에 우승컵에 닿았습니다. 공동 우승이며 점수는 나눕니다.'),
        F.new(key: 'msg_limit', type: :text, group: 'messages', label: '최대 턴', default: '%{turns}턴이 지나도록 아무도 우승컵에 닿지 못했습니다. 무승부입니다.'),
      ] + Game::Events::Recruiting.fields(min: 2, max: 4)).freeze

      class << self
        def web?
          true
        end

        def spectatable?
          true
        end

        def max_opponents
          config['max_opponents'].to_i.clamp(1, 3)
        end

        # 시간 초과는 그 단계 선택을 못 한 것으로 (규칙의 일부)
        def continues_on_timeout?
          true
        end
      end

      def start!
        width = config['width'].to_i.clamp(7, 31)
        height = config['height'].to_i.clamp(7, 31)
        cup = [width / 2, height / 2]
        corners = [[0, 0], [width - 1, height - 1], [width - 1, 0], [0, height - 1]]
        positions = players.each_with_index.to_h { |player, index| [player.seat.to_s, corners[index]] }

        free = (0...width).to_a.product((0...height).to_a).shuffle - corners - [cup]
        take = ->(count) { free.shift(count.to_i.clamp(0, free.size)) }
        names = config['creature_names'].presence || ['마법 생물']

        state.merge!(
          'width' => width, 'height' => height, 'cells' => carve(width, height), 'cup' => cup, 'positions' => positions,
          'traps' => take.call(config['traps']),
          'creatures' => take.call(config['creatures']).map { |(x, y)| [x, y, names.sample] },
          'inventory' => players.to_h { |player| [player.seat.to_s, { 'portkey' => config['portkey'].to_i.clamp(0, 9), 'lumos' => config['lumos'].to_i.clamp(0, 9) }] },
          'status' => players.to_h { |player| [player.seat.to_s, {}] },
          'seen' => players.to_h { |player| [player.seat.to_s, []] },
          'known_traps' => players.to_h { |player| [player.seat.to_s, []] },
          'trails' => positions.transform_values { |position| [position] },
          'hint' => {}, 'hostile' => [], 'met' => {}, 'log' => [], 'turn_log' => [],
          'phase' => 'move', 'moves' => {}, 'paths' => {}, 'need' => {}, 'picks' => {}, 'fights' => {}, 'peers' => []
        )
        players.each { |player| reveal!(player.seat.to_s) }
        session.update!(turn: 1)
        post(render(config['msg_start'], players: players.map(&:name).join(', '), **Game::Config.turn_time))
        begin_turn!
      end

      def handle(player, command, args, status)
        action = ACTIONS.find { |key| config["cmd_#{key}"] == command }
        return false if action.nil?
        return true unless require_dm!(player, status)

        case action
        when 'move' then submit_path!(player, args)
        when 'stay' then submit_path!(player, [])
        when 'portkey' then use_portkey!(player)
        when 'lumos' then use_lumos!(player)
        when *STANCES then pick!(player, 'stance', action)
        else pick!(player, 'spell', action)
        end
        true
      end

      def timeout!
        proceed!
      end

      # 이 사람에게 보이는 미로 (웹 진행 화면)
      def view_for(player)
        return reveal_view(player) if player.nil? || session.status == 'finished'

        seat = player.seat.to_s
        x, y = state['positions'][seat]
        vision = vision_of(seat)
        visible = visible_indexes(x, y, vision)
        known = (state['seen'][seat] | visible)
        hint = state['hint'][seat]
        mine = state['inventory'][seat] || {}

        {
          width: state['width'], height: state['height'], me: seat.to_i, position: [x, y],
          cells: known.to_h { |index| [index, state['cells'][index]] },
          visible: visible,
          cup: known.include?(index_of(*state['cup'])) ? state['cup'] : nil,
          hint: hint && { direction: hint['dir'], turn: hint['turn'] },
          reachable: reachable(seat),
          creatures: state['creatures'].select { |cx, cy, _| visible.include?(index_of(cx, cy)) }.map { |cx, cy, name| { x: cx, y: cy, name: name } },
          traps: state['known_traps'][seat].map { |tx, ty| { x: tx, y: ty } },
          others: players.reject { |other| other.id == player.id }.filter_map do |other|
            ox, oy = state['positions'][other.seat.to_s]
            next unless visible.include?(index_of(ox, oy))

            { seat: other.seat, name: other.name, x: ox, y: oy, hostile: hostile?(pair_key(seat, other.seat.to_s)) }
          end,
          inventory: { portkey: mine['portkey'].to_i, lumos: mine['lumos'].to_i },
          planned: state.dig('moves', seat, 'path'),
          commands: ACTIONS.to_h { |key| [key, config["cmd_#{key}"]] },
          item_info: item_info,
          steps: max_steps(seat),
          vision: vision,
          stunned: state.dig('status', seat, 'stunned').to_i,
          lumos: state.dig('status', seat, 'lumos').to_i,
          phase: state['phase'],
          need: (state['need'][seat] || []).reject { |kind| state.dig('picks', seat, kind) },
          fight: state.dig('fights', seat)&.last,
          meet: meet_names(seat),
          submitted: state['phase'] == 'move' ? state['moves'].key?(seat) : !waiting_on.map { |other| other.seat.to_s }.include?(seat),
          waiting: waiting_on.map(&:name),
          turn: session.turn,
          deadline_at: session.deadline_at&.iso8601,
          log: state['log'],
          players: people, max_turns: config['max_turns'].to_i, revealed: false, status: session.status,
        }
      end

      # 관전자와 끝난 판: 지도 전체·우승컵·함정·생물·모든 사람의 위치와 지나온 길이 실시간으로 다 보인다
      def reveal_view(player)
        seat = player&.seat
        {
          width: state['width'], height: state['height'], me: seat, position: seat && state['positions'][seat.to_s],
          cells: state['cells'].each_with_index.to_h { |bits, index| [index, bits] },
          visible: (0...(state['width'] * state['height'])).to_a,
          cup: state['cup'], hint: nil, reachable: [],
          creatures: state['creatures'].map { |cx, cy, name| { x: cx, y: cy, name: name } },
          traps: state['traps'].map { |tx, ty| { x: tx, y: ty } },
          others: [], inventory: { portkey: 0, lumos: 0 }, planned: nil,
          commands: ACTIONS.to_h { |key| [key, config["cmd_#{key}"]] }, item_info: item_info,
          steps: 0, vision: 0, stunned: 0, lumos: 0, phase: state['phase'] || 'move', need: [], fight: nil, meet: [], submitted: true,
          waiting: waiting_on.map(&:name), turn: session.turn, deadline_at: session.deadline_at&.iso8601, log: state['log'],
          players: people(positions: true), trails: state['trails'] || {}, hostile: state['hostile'] || [],
          max_turns: config['max_turns'].to_i, revealed: true, spectator: player.nil?, status: session.status,
        }
      end

      # 화면 맨 위 참가자 목록 (아바타는 컨트롤러가 붙인다). positions: 위치까지 (관전·끝난 판)
      def people(positions: false)
        players.map do |other|
          seat = other.seat.to_s
          entry = { seat: other.seat, name: other.name, account_id: other.account_id, stunned: state.dig('status', seat, 'stunned').to_i,
                    boost: state.dig('status', seat, 'boost') ? true : false, lumos: state.dig('status', seat, 'lumos').to_i }
          entry.merge!(x: state['positions'][seat][0], y: state['positions'][seat][1]) if positions
          entry
        end
      end

      # 카드(툿·방 맨 위): 위치·우승컵·함정은 담지 않는다. 쉬는 사람·적대 표시·루모스만 공개.
      def card_data
        {
          'width' => state['width'], 'height' => state['height'], 'max_turns' => config['max_turns'].to_i,
          'log' => state['log'] || [],
          'status' => (state['status'] || {}).transform_values { |value| value.slice('stunned', 'boost', 'lumos') },
          'hostile' => state['hostile'] || [],
          'phase' => state['phase'],
          'web' => true,
        }
      end

      def pending_seats
        waiting_on.map(&:seat)
      end

      # 웹 방 입력창 위 버튼: 이동·아이템은 지도 화면에서 하고, 여기엔 제자리·마주침 선택을 둔다
      def card_actions
        seats = pending_seats
        return [] if seats.empty?

        case state['phase']
        when 'move'
          [Game::Card.action(config['cmd_stay'], seats: seats, dm: true)]
        else
          spells = seats.select { |seat| state['need'][seat.to_s]&.include?('spell') }
          stances = seats.select { |seat| state['need'][seat.to_s]&.include?('stance') }
          actions = []
          actions += SPELLS.map { |key| Game::Card.action(config["cmd_#{key}"], seats: spells, dm: true) } if spells.any?
          actions += STANCES.map { |key| Game::Card.action(config["cmd_#{key}"], seats: stances, dm: true, row: 2) } if stances.any?
          actions
        end
      end

      def max_turns
        config['max_turns'].to_i
      end

      private

      def dims
        [state['width'], state['height']]
      end

      def max_steps(seat)
        base = config['steps'].to_i.clamp(1, 4)
        state.dig('status', seat, 'boost') ? base + 1 : base
      end

      def vision_of(seat)
        base = config['vision'].to_i.clamp(1, 5)
        state.dig('status', seat, 'lumos').to_i.positive? ? base + config['lumos_bonus'].to_i.clamp(0, 3) : base
      end

      def stunned?(seat)
        state.dig('status', seat, 'stunned').to_i.positive?
      end

      def stun!(seat, turns)
        state['status'][seat]['stunned'] = [state['status'][seat]['stunned'].to_i, turns].max
      end

      def player_of(seat)
        players.find { |player| player.seat.to_s == seat.to_s }
      end

      def pair_key(seat_a, seat_b)
        [seat_a.to_i, seat_b.to_i].sort.join('-')
      end

      def hostile?(key)
        state['hostile'].include?(key)
      end

      def index_of(x, y)
        (y * state['width']) + x
      end

      def visible_indexes(x, y, vision)
        width, height = dims
        ((y - vision)..(y + vision)).flat_map do |cy|
          ((x - vision)..(x + vision)).filter_map { |cx| (cy * width) + cx if cx.between?(0, width - 1) && cy.between?(0, height - 1) }
        end
      end

      def reveal!(seat)
        x, y = state['positions'][seat]
        state['seen'][seat] = (state['seen'][seat] | visible_indexes(x, y, vision_of(seat)))
      end

      def direction_to(x, y, tx, ty)
        { [0, -1] => '↑', [1, -1] => '↗', [1, 0] => '→', [1, 1] => '↘', [0, 1] => '↓', [-1, 1] => '↙', [-1, 0] => '←', [-1, -1] => '↖', [0, 0] => '★' }[[tx <=> x, ty <=> y]]
      end

      def open?(x, y, dir)
        (state['cells'][index_of(x, y)] & DIRS[dir][2]).positive?
      end

      # 아직 이번 단계 선택을 안 낸 사람 (쉬는 사람 제외)
      def waiting_on
        if state['phase'] == 'move'
          players.reject { |player| stunned?(player.seat.to_s) || state['moves'].key?(player.seat.to_s) }
        else
          players.select { |player| (state['need'][player.seat.to_s] || []).any? { |kind| !state.dig('picks', player.seat.to_s, kind) } }
        end
      end

      def spell_commands
        SPELLS.to_h { |key| [key.to_sym, config["cmd_#{key}"]] }
      end

      # 아이템에 마우스를 올리면 보이는 효과
      def item_info
        {
          portkey: "#{config['cmd_portkey']}: 우승컵이 있는 방향을 한 번 알려 줍니다. (화살표가 남습니다)",
          lumos: "#{config['cmd_lumos']}: #{config['lumos_turns'].to_i.clamp(1, 10)}턴 동안 시야가 #{config['lumos_bonus'].to_i.clamp(0, 3)}칸 넓어집니다.",
        }
      end

      def items_text(seat)
        mine = state['inventory'][seat] || {}
        "#{config['cmd_portkey']} #{mine['portkey'].to_i}개 · #{config['cmd_lumos']} #{mine['lumos'].to_i}개"
      end

      # ── 턴 시작: 이동 고르기 DM ──
      def begin_turn!
        state['phase'] = 'move'
        state['moves'] = {}
        state['picks'] = {}
        state['need'] = {}
        players.each do |player|
          seat = player.seat.to_s
          if stunned?(seat)
            dm(player, render(config['msg_rest']))
          else
            dm(player, render(config['msg_ask'], turn: session.turn, steps: max_steps(seat), move: config['cmd_move'], stay: config['cmd_stay'], items: items_text(seat)))
          end
        end
        session.save!
        wait_for_turn!
        proceed! if waiting_on.empty?
      end

      def proceed!
        case state['phase']
        when 'move' then start_moving!
        when 'fight' then resolve_fights!
        when 'meet' then resolve_meets!
        end
      end

      # ── ① 이동 ──
      def parse_path(seat, args)
        tokens = Array(args).flat_map { |arg| arg.to_s.strip.chars }
        dirs = tokens.map { |token| DIR_NAMES[token] || (token.upcase if DIRS.key?(token.upcase)) }
        return if dirs.any?(&:nil?) || dirs.size > max_steps(seat)

        x, y = state['positions'][seat]
        dirs.each do |dir|
          return nil unless open?(x, y, dir)

          x += DIRS[dir][0]
          y += DIRS[dir][1]
        end
        dirs
      end

      def submit_path!(player, args)
        seat = player.seat.to_s
        return dm(player, render(config['msg_wrong_time'])) unless state['phase'] == 'move' && !stunned?(seat)

        path = parse_path(seat, args)
        return dm(player, render(config['msg_bad_move'])) if path.nil?

        state['moves'][seat] = { 'path' => path }
        session.save!
        dm(player, render(config['msg_chosen']))
        proceed! if waiting_on.empty?
      end

      def use_portkey!(player)
        seat = player.seat.to_s
        return dm(player, render(config['msg_wrong_time'])) unless state['phase'] == 'move'
        return dm(player, render(config['msg_no_item'], item: config['cmd_portkey'])) unless state['inventory'][seat]['portkey'].to_i.positive?

        state['inventory'][seat]['portkey'] -= 1
        x, y = state['positions'][seat]
        arrow = direction_to(x, y, *state['cup'])
        state['hint'][seat] = { 'dir' => arrow, 'turn' => session.turn }
        session.save!
        dm(player, render(config['msg_portkey'], direction: arrow))
      end

      def use_lumos!(player)
        seat = player.seat.to_s
        return dm(player, render(config['msg_wrong_time'])) unless state['phase'] == 'move'
        return dm(player, render(config['msg_no_item'], item: config['cmd_lumos'])) unless state['inventory'][seat]['lumos'].to_i.positive?

        turns = config['lumos_turns'].to_i.clamp(1, 10)
        state['inventory'][seat]['lumos'] -= 1
        state['status'][seat]['lumos'] = turns
        session.save!
        dm(player, render(config['msg_lumos'], turns: turns))
      end

      def start_moving!
        state['turn_log'] = []
        paths = {}
        players.each do |player|
          seat = player.seat.to_s
          if stunned?(seat)
            state['status'][seat]['stunned'] -= 1
            next
          end

          state['status'][seat].delete('boost')
          paths[seat] = state.dig('moves', seat, 'path') || []
        end
        state['paths'] = paths
        state['moves'] = {}
        run_paths!
      end

      # 남은 경로를 따라 모두 걷는다. 마법 생물 칸에 닿으면 거기서 멈추고 대결을 기다린다.
      def run_paths!
        log = state['turn_log']
        fights = {}
        players.each do |player|
          seat = player.seat.to_s
          path = state['paths'][seat] || []
          until path.empty?
            dir = path.shift
            x, y = state['positions'][seat]
            unless open?(x, y, dir)
              path.clear
              break
            end

            nx = x + DIRS[dir][0]
            ny = y + DIRS[dir][1]
            state['positions'][seat] = [nx, ny]
            trails = (state['trails'] ||= {})
            (trails[seat] ||= [[x, y]]) << [nx, ny]

            if state['traps'].include?([nx, ny])
              state['known_traps'][seat] |= [[nx, ny]]
              stun!(seat, 1)
              log << render(config['msg_trap'], player: player)
              path.clear
              break
            end

            creature = state['creatures'].find { |cx, cy, _| cx == nx && cy == ny }
            if creature
              fights[seat] = creature
              break
            end

            path.clear if [nx, ny] == state['cup']
          end
          state['paths'][seat] = path
        end

        return begin_meet! if fights.empty?

        state['fights'] = fights
        state['phase'] = 'fight'
        state['need'] = fights.keys.to_h { |seat| [seat, ['spell']] }
        state['picks'] = {}
        fights.each { |seat, creature| dm(player_of(seat), render(config['msg_fight_ask'], creature: creature[2], **spell_commands)) }
        session.save!
        wait_for_turn!
      end

      def pick!(player, kind, value)
        seat = player.seat.to_s
        phase_ok = %w(fight meet).include?(state['phase']) && state['need'][seat]&.include?(kind)
        return dm(player, render(config['msg_wrong_time'])) unless phase_ok

        (state['picks'][seat] ||= {})[kind] = value
        session.save!
        dm(player, render(config['msg_chosen']))
        proceed! if waiting_on.empty?
      end

      # 주문 가위바위보: :win / :lose / :draw (고르지 않으면 진다, 둘 다 안 골랐으면 비김)
      def clash(mine, theirs)
        return :draw if mine == theirs
        return :lose if mine.nil?
        return :win if theirs.nil?

        BEATS[mine] == theirs ? :win : :lose
      end

      # ── ② 마법 생물 ──
      def creature_spell
        SPELLS.sample
      end

      def resolve_fights!
        log = state['turn_log']
        state['fights'].each do |seat, creature|
          player = player_of(seat)
          outcome = clash(state.dig('picks', seat, 'spell'), creature_spell)
          case outcome
          when :win
            state['creatures'].delete(creature)
            state['status'][seat]['boost'] = true
            log << render(config['msg_creature_win'], player: player, creature: creature[2])
          when :lose
            stun!(seat, 1)
            state['paths'][seat] = []
            log << render(config['msg_creature_lose'], player: player, creature: creature[2])
          else
            log << render(config['msg_creature_draw'], player: player, creature: creature[2])
          end
        end
        state['fights'] = {}
        state['need'] = {}
        state['picks'] = {}
        run_paths!
      end

      # ── ③ 다른 참가자와의 만남 ──
      def begin_meet!
        peers = []
        players.to_a.combination(2).each do |a, b|
          ax, ay = state['positions'][a.seat.to_s]
          bx, by = state['positions'][b.seat.to_s]
          next if (ax - bx).abs + (ay - by).abs > 1

          key = pair_key(a.seat, b.seat)
          next if state['met'][key] && session.turn - state['met'][key] < MEET_COOLDOWN

          peers << [a.seat.to_s, b.seat.to_s, hostile?(key)]
        end
        # 우승컵에 닿은 사람이 있으면 만남 없이 바로 승패를 가린다
        return end_turn! if peers.empty? || players.any? { |player| state['positions'][player.seat.to_s] == state['cup'] }

        need = {}
        peers.each do |seat_a, seat_b, hostile|
          [seat_a, seat_b].each { |seat| (need[seat] ||= []) << (hostile ? 'spell' : 'stance') }
        end
        state['peers'] = peers
        state['need'] = need.transform_values(&:uniq)
        state['picks'] = {}
        state['phase'] = 'meet'
        state['need'].each_key do |seat|
          player = player_of(seat)
          friends = meet_names(seat, hostile: false)
          enemies = meet_names(seat, hostile: true)
          dm(player, render(config['msg_stance_ask'], players: friends.join(', '), **STANCES.to_h { |key| [key.to_sym, config["cmd_#{key}"]] })) if friends.any?
          dm(player, render(config['msg_hostile_ask'], players: enemies.join(', '), **spell_commands)) if enemies.any?
        end
        session.save!
        wait_for_turn!
      end

      # 이 사람이 지금 마주친 사람 이름 (hostile: nil 이면 전부)
      def meet_names(seat, hostile: nil)
        (state['peers'] || []).filter_map do |seat_a, seat_b, enemy|
          next if !hostile.nil? && enemy != hostile
          next unless [seat_a, seat_b].include?(seat)

          player_of(seat_a == seat ? seat_b : seat_a).name
        end
      end

      def resolve_meets!
        log = state['turn_log']
        state['peers'].each do |seat_a, seat_b, enemy|
          a = player_of(seat_a)
          b = player_of(seat_b)
          key = pair_key(seat_a, seat_b)
          state['met'][key] = session.turn
          enemy ? fight!(a, b, log) : stance!(a, b, key, log)
        end
        state['peers'] = []
        state['need'] = {}
        state['picks'] = {}
        end_turn!
      end

      def stance_of(seat)
        state.dig('picks', seat, 'stance') || 'cooperate'
      end

      def stance!(a, b, key, log)
        seat_a = a.seat.to_s
        seat_b = b.seat.to_s
        stance_a = stance_of(seat_a)
        stance_b = stance_of(seat_b)
        if stance_a == 'cooperate' && stance_b == 'cooperate'
          shared = state['seen'][seat_a] | state['seen'][seat_b]
          state['seen'][seat_a] = shared
          state['seen'][seat_b] = shared.dup
          log << render(config['msg_meet_coop'], player: a, target: b)
        elsif stance_a == 'hinder' && stance_b == 'hinder'
          stun!(seat_a, 1)
          stun!(seat_b, 1)
          state['hostile'] |= [key]
          log << render(config['msg_meet_both'], player: a, target: b)
        else
          hinderer, victim = stance_a == 'hinder' ? [a, b] : [b, a]
          stun!(victim.seat.to_s, 1)
          state['hostile'] |= [key]
          log << render(config['msg_meet_hinder'], player: hinderer, target: victim)
        end
      end

      def fight!(a, b, log)
        seat_a = a.seat.to_s
        seat_b = b.seat.to_s
        case clash(state.dig('picks', seat_a, 'spell'), state.dig('picks', seat_b, 'spell'))
        when :win then fight_won!(a, b, log)
        when :lose then fight_won!(b, a, log)
        else
          stun!(seat_a, 1)
          stun!(seat_b, 1)
          log << render(config['msg_fight_draw'], player: a, target: b)
        end
      end

      def fight_won!(winner, loser, log)
        state['seen'][winner.seat.to_s] = state['seen'][winner.seat.to_s] | state['seen'][loser.seat.to_s]
        stun!(loser.seat.to_s, 2)
        log << render(config['msg_fight_win'], winner: winner, loser: loser)
      end

      # ── 턴 끝: 승패 확인 ──
      def end_turn!
        players.each do |player|
          seat = player.seat.to_s
          reveal!(seat)
          state['status'][seat]['lumos'] -= 1 if state['status'][seat]['lumos'].to_i.positive?
        end
        state['log'] = state['turn_log']
        state['phase'] = 'move'

        reached = players.select { |player| state['positions'][player.seat.to_s] == state['cup'] }
        lines = state['log'].presence || [render(config['msg_quiet'])]
        turn_text = render(config['msg_turn'], turn: session.turn, lines: lines.join("\n"))

        if reached.size == 1
          finish!(winner: reached.first, message: "#{turn_text}\n\n#{render(config['msg_win'], winner: reached.first, turn: session.turn)}")
        elsif reached.size > 1
          finish!(winners: reached, split_points: true, message: "#{turn_text}\n\n#{render(config['msg_tie'], players: reached.map(&:name).join(', '))}")
        elsif session.turn >= config['max_turns'].to_i
          finish!(draw: true, message: "#{turn_text}\n\n#{render(config['msg_limit'], turns: session.turn)}")
        else
          post(turn_text)
          session.update!(turn: session.turn + 1)
          begin_turn!
        end
      end

      # 클릭할 수 있는 칸: 시야 안에서 열린 길로 최대 N칸 (보이는 마법 생물 칸은 거기까지만)
      def reachable(seat)
        return [] if state['phase'] != 'move' || stunned?(seat)

        x, y = state['positions'][seat]
        vision = vision_of(seat)
        inside = ->(cx, cy) { (cx - x).abs <= vision && (cy - y).abs <= vision }
        blockers = state['creatures'].select { |cx, cy, _| inside.call(cx, cy) }.map { |cx, cy, _| [cx, cy] }
        best = { [x, y] => [] }
        queue = [[x, y]]
        until queue.empty?
          cx, cy = queue.shift
          path = best[[cx, cy]]
          next if path.size >= max_steps(seat) || (blockers.include?([cx, cy]) && path.any?)

          DIRS.each do |dir, (dx, dy, _, _)|
            nx = cx + dx
            ny = cy + dy
            next unless nx.between?(0, state['width'] - 1) && ny.between?(0, state['height'] - 1)
            next unless open?(cx, cy, dir) && inside.call(nx, ny) && !best.key?([nx, ny])

            best[[nx, ny]] = path + [dir]
            queue << [nx, ny]
          end
        end
        best.reject { |cell, _| cell == [x, y] }.map { |(rx, ry), path| { x: rx, y: ry, path: path } }
      end

      # 미로 만들기: 길 파기(깊이 우선) + 벽 몇 개를 더 터서 갈림길. cells[i] = 열린 방향 비트 (N1 E2 S4 W8)
      def carve(width, height)
        cells = Array.new(width * height, 0)
        visited = Array.new(width * height, false)
        stack = [[rand(width), rand(height)]]
        visited[(stack[0][1] * width) + stack[0][0]] = true
        until stack.empty?
          x, y = stack.last
          options = DIRS.values.filter_map do |dx, dy, bit, back|
            nx = x + dx
            ny = y + dy
            [nx, ny, bit, back] if nx.between?(0, width - 1) && ny.between?(0, height - 1) && !visited[(ny * width) + nx]
          end
          if options.empty?
            stack.pop
            next
          end
          nx, ny, bit, back = options.sample
          cells[(y * width) + x] |= bit
          cells[(ny * width) + nx] |= back
          visited[(ny * width) + nx] = true
          stack << [nx, ny]
        end

        (width * height / 10).times do
          x = rand(width - 1)
          y = rand(height - 1)
          dx, dy, bit, back = DIRS[%w(E S).sample]
          cells[(y * width) + x] |= bit
          cells[((y + dy) * width) + x + dx] |= back
        end
        cells
      end
    end
  end
end
