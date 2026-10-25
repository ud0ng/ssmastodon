# frozen_string_literal: true

module Game
  module Web
    # 트라이위저드 미로 (웹 전용 이벤트, 2~24명, 불의 잔). 안개 낀 미로를 모두 동시에 탐험해 우승컵에 먼저 닿는 경쟁.
    #
    #   인원별: 2~4명 15×15 (각자 다른 입구, 가짜 우승컵 0, 25턴) / 5~10명 21×21 (입구 4곳 무작위, 가짜 1, 30턴) / 11~24명 27×27 (입구 8곳, 가짜 2, 40턴)
    #   모드: 개인전 / 기숙사 팀전 (설정 team_mode). 팀전은 소속(기숙사)이 한 팀(최대 6명, 넘으면 나눈다), 팀원끼리는 지도를 늘 함께 쓰고 마주쳐도 협력한다.
    #   미로는 판마다 새로 만든다. 진짜 우승컵은 한가운데 근처, 가짜 우승컵(포트키 함정)은 똑같이 생겼고 잡으면 무작위 입구로 날아간다 (남은 그 자리가 가짜였는지 모른다).
    #   시야는 주변 2칸 (루모스 +1, 3턴), 지나온 곳은 내 지도에 남는다.
    #   턴: 모두 동시에 1~2칸 길을 고른다 (2분, 안 고르면 제자리). 함정은 밟아야 알고 1턴 정지.
    #   마법 생물: 만나면 힌트를 보고 주문을 고른다 (생물마다 통하는 주문이 하나). 틀리면 2턴 정지, 맞히면 생물이 사라진다.
    #   아이템(미로에 떨어져 있다, 밟으면 줍는다): 포인트 미 (진짜 우승컵 방향 1번) · 루모스 (시야 +1, 3턴)
    #   조우: 턴이 끝날 때 같은 칸·옆 칸에 다른 참가자가 있으면 조우 단계 (30초) — 각자 몰래 협력 또는 방해(1명).
    #         협력한 사람끼리 지도를 나눈다. 방해받으면 1턴 정지 (여럿에게 받아도 1턴). 방해한 사람에게는 그 상대에 대한 '적대' 표시가 모두에게 보인다.
    #   붉은 불꽃: 기권 (그 자리에서 탈락).
    #   끝: 진짜 우승컵에 처음 닿은 사람이 우승 (같은 턴이면 공동). 나머지는 우승컵까지의 최단 거리 순. 최대 턴이 지나면 무승부(거리 순위만).
    #       팀전은 우승자의 팀이 승리, 나머지 팀은 팀원 순위 점수의 합으로. 점수·보상은 공통 처리(finish!)로 (테스트 플레이·하루 보상 제한도 같다).
    class Maze < Game::Kinds::Base
      KEY = 'maze'

      include Game::Events::Recruiting

      DIRS = { 'N' => [0, -1, 1, 4], 'E' => [1, 0, 2, 8], 'S' => [0, 1, 4, 1], 'W' => [-1, 0, 8, 2] }.freeze
      DIR_NAMES = { '북' => 'N', '동' => 'E', '남' => 'S', '서' => 'W' }.freeze

      # 인원별 미로 (크기 · 입구 수(nil = 사람마다 다른 입구) · 가짜 우승컵 · 최대 턴)
      TIERS = [
        { upto: 4, size: 15, entrances: nil, fakes: 0, turns: 25 },
        { upto: 10, size: 21, entrances: 4, fakes: 1, turns: 30 },
        { upto: 24, size: 27, entrances: 8, fakes: 2, turns: 40 },
      ].freeze

      # 마법 생물: 통하는 주문 하나와 힌트 (힌트만 보여 준다)
      CREATURES = {
        'boggart' => { name: '보가트', spell: 'riddikulus', hint: '가장 두려워하는 모습으로 변한다. 웃음이 약점이다.' },
        'skrewt' => { name: '폭발꼬리 스크루트', spell: 'impedimenta', hint: '엄청난 속도로 돌진해 온다. 움직임을 늦추면 빠져나갈 수 있다.' },
        'acromantula' => { name: '아크로맨투라', spell: 'arania', hint: '거대한 거미. 거미만 쫓아내는 주문이 따로 있다.' },
        'dementor' => { name: '디멘터', spell: 'patronum', hint: '행복한 기억이 빠져나간다. 빛나는 수호령만이 막아 낸다.' },
        'sphinx' => { name: '스핑크스', spell: 'stupefy', hint: '길을 막고 선 거대한 수호자. 잠시 기절시키면 지나갈 수 있다.' },
      }.freeze
      SPELLS = {
        'riddikulus' => '리디큘러스', 'impedimenta' => '임페디멘타', 'arania' => '아라니아 엑숨네이', 'patronum' => '익스펙토 패트로눔', 'stupefy' => '스투페파이',
      }.freeze
      ITEMS = %w(pointme lumos).freeze
      # 같은 사람과 다시 조우하기까지 쉬는 턴 (만난 턴 포함): 함께 걷는 동안 매 턴 조우하지 않게
      MEET_COOLDOWN = 3
      TEAM_MAX = 6

      FIELDS = (base_fields(name: '트라이위저드 미로', command: '미로', points_win: 10) + [
        F.new(key: 'team_mode', type: :boolean, default: false, group: 'rules', label: '기숙사 팀전', hint: '켜면 소속(기숙사)이 한 팀 (최대 6명, 넘으면 나눕니다). 팀원끼리 지도를 함께 쓰고 마주쳐도 협력합니다'),
        F.new(key: 'steps', type: :integer, default: 2, group: 'rules', label: '한 턴에 움직이는 칸 수', hint: '1~3'),
        F.new(key: 'vision', type: :integer, default: 2, group: 'rules', label: '시야 (칸)'),
        F.new(key: 'turn_seconds', type: :integer, default: 120, group: 'rules', label: '턴 시간 (초)', hint: '안 고르면 제자리'),
        F.new(key: 'encounter_seconds', type: :integer, default: 30, group: 'rules', label: '조우·마법 생물 대응 시간 (초)'),
        F.new(key: 'first_turn_bonus', type: :integer, default: 30, group: 'rules', label: '첫 턴 추가 시간 (초)', hint: '오프닝을 보는 동안 첫 턴이 줄지 않게 (0~120)'),
        F.new(key: 'trap_rate', type: :integer, default: 3, group: 'rules', label: '함정 (100칸당)'),
        F.new(key: 'creature_rate', type: :integer, default: 2, group: 'rules', label: '마법 생물 (100칸당)'),
        F.new(key: 'item_rate', type: :integer, default: 2, group: 'rules', label: '아이템 (100칸당)', hint: '포인트 미와 루모스를 반씩'),
        F.new(key: 'lumos_bonus', type: :integer, default: 1, group: 'rules', label: '루모스 시야 증가 (칸)'),
        F.new(key: 'lumos_turns', type: :integer, default: 3, group: 'rules', label: '루모스 지속 (턴)'),
        F.new(key: 'creature_stun', type: :integer, default: 2, group: 'rules', label: '마법 생물에게 지면 정지 (턴)'),
        F.new(key: 'cmd_move', type: :string, default: '이동', group: 'commands', label: '이동 명령어', hint: '웹 미로에서 칸을 누르면 [이동/동/남] 처럼 보냅니다'),
        F.new(key: 'cmd_stay', type: :string, default: '대기', group: 'commands', label: '제자리 명령어'),
        F.new(key: 'cmd_pointme', type: :string, default: '포인트미', group: 'commands', label: '포인트 미 명령어'),
        F.new(key: 'cmd_lumos', type: :string, default: '루모스', group: 'commands', label: '루모스 명령어'),
        F.new(key: 'cmd_spell', type: :string, default: '주문', group: 'commands', label: '주문 명령어 (마법 생물)', hint: '[주문/리디큘러스]'),
        F.new(key: 'cmd_cooperate', type: :string, default: '협력', group: 'commands', label: '협력 명령어'),
        F.new(key: 'cmd_hinder', type: :string, default: '방해', group: 'commands', label: '방해 명령어', hint: '[방해] @누구'),
        F.new(key: 'cmd_flare', type: :string, default: '붉은불꽃', group: 'commands', label: '붉은 불꽃(기권) 명령어'),
        F.new(key: 'msg_start', type: :text, group: 'messages', label: '시작', default: "%{game} 시작! %{count}명이 안개 낀 %{size}×%{size} 미로에 들어섭니다.\n미로 한가운데 어딘가에 진짜 우승컵이 있습니다. (최대 %{turns}턴)"),
        F.new(key: 'msg_turn', type: :text, group: 'messages', label: '턴 결과', default: "%{turn}턴\n%{lines}"),
        F.new(key: 'msg_quiet', type: :text, group: 'messages', label: '조용한 턴', default: '안개 속에서 발소리만 들려옵니다.'),
        F.new(key: 'msg_trap', type: :text, group: 'messages', label: '함정', default: '%{player}{이가} 함정에 걸렸습니다. (1턴 정지)'),
        F.new(key: 'msg_creature_win', type: :text, group: 'messages', label: '생물 물리침', default: '%{player}{이가} %{spell}{으로로} %{creature}{을를} 물리쳤습니다.'),
        F.new(key: 'msg_creature_lose', type: :text, group: 'messages', label: '생물에게 당함', default: '%{player}{이가} %{creature}에게 당했습니다. (%{turns}턴 정지)'),
        F.new(key: 'msg_coop', type: :text, group: 'messages', label: '조우: 협력', default: '%{players}{이가} 서로 지도를 나눴습니다.'),
        F.new(key: 'msg_hinder', type: :text, group: 'messages', label: '조우: 방해', default: '%{player}{이가} %{target}{을를} 방해했습니다. (%{target} 1턴 정지)'),
        F.new(key: 'msg_flare', type: :text, group: 'messages', label: '붉은 불꽃 (기권)', default: '%{player}{이가} 붉은 불꽃을 쏘아 올렸습니다. (탈락)'),
        F.new(key: 'msg_win', type: :text, group: 'messages', label: '우승', default: '%{winner}{이가} 우승컵을 잡았습니다! %{turn}턴 만의 우승!'),
        F.new(key: 'msg_tie', type: :text, group: 'messages', label: '공동 우승', default: '%{players}{이가} 같은 턴에 우승컵에 닿았습니다. 공동 우승!'),
        F.new(key: 'msg_team_win', type: :text, group: 'messages', label: '팀 우승', default: '%{winner}{이가} 우승컵을 잡았습니다! %{team} 팀의 우승!'),
        F.new(key: 'msg_limit', type: :text, group: 'messages', label: '최대 턴', default: '%{turns}턴이 지나도록 아무도 우승컵에 닿지 못했습니다. 무승부입니다.'),
        F.new(key: 'msg_all_out', type: :text, group: 'messages', label: '모두 기권', default: '모두 붉은 불꽃을 쏘아 올렸습니다. 우승자 없이 끝납니다.'),
      ] + Game::Events::Recruiting.fields(min: 2, max: 24)).freeze

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

        def continues_on_timeout?
          true
        end

        def max_opponents
          [config['event_max_players'].to_i.clamp(2, 24) - 1, 1].max
        end

        def invite_error(_total, _args = [])
          '트라이위저드 미로는 이벤트로 엽니다. 모집 안내를 기다려 주세요.'
        end

        def tier(total)
          TIERS.find { |tier| total <= tier[:upto] } || TIERS.last
        end
      end

      def event_max_players
        super.clamp(2, 24)
      end

      # ── 시작 ──
      def start!
        tier = self.class.tier(players.size)
        size = tier[:size]
        mid = size / 2
        cells = carve(size)
        gates = gates_for(size, tier[:entrances])
        cup = [mid + rand(-1..1), mid + rand(-1..1)]
        fakes = fake_spots(size, cup, gates, tier[:fakes])

        positions = {}
        if tier[:entrances].nil?
          gates.shuffle.first(players.size).each_with_index { |gate, index| positions[players[index].seat.to_s] = gate }
        else
          players.each { |player| positions[player.seat.to_s] = gates.sample }
        end

        blocked = (gates.flat_map { |gx, gy| around(gx, gy, 1, size) } + [cup] + fakes).uniq
        free = (0...size).to_a.product((0...size).to_a).shuffle - blocked
        take = ->(rate) { free.shift(((size * size) * rate.to_i.clamp(0, 20) / 100.0).round.clamp(0, free.size)) }
        traps = take.call(config['trap_rate'])
        creatures = take.call(config['creature_rate']).map { |x, y| { 'x' => x, 'y' => y, 'kind' => CREATURES.keys.sample } }
        items = take.call(config['item_rate']).each_with_index.map { |(x, y), index| { 'x' => x, 'y' => y, 'kind' => ITEMS[index % 2] } }

        teams = config['team_mode'] ? house_teams : {}
        state.merge!(
          'size' => size, 'cells' => cells, 'gates' => gates, 'cup' => cup, 'fakes' => fakes, 'traps' => traps, 'creatures' => creatures, 'items' => items,
          'positions' => positions, 'starts' => positions.dup, 'trails' => positions.transform_values { |spot| [spot] },
          'seen' => players.to_h { |player| [player.seat.to_s, []] }, 'known_traps' => players.to_h { |player| [player.seat.to_s, []] },
          'grabbed' => players.to_h { |player| [player.seat.to_s, []] },
          'status' => players.to_h { |player| [player.seat.to_s, {}] }, 'inventory' => players.to_h { |player| [player.seat.to_s, {}] },
          'hint' => {}, 'hostile' => [], 'met' => {}, 'out' => [], 'teams' => teams.transform_values { |team| team[:key] },
          'team_info' => teams.values.uniq { |team| team[:key] }.to_h { |team| [team[:key], team.slice(:name, :color).transform_keys(&:to_s)] },
          'max_turns' => tier[:turns], 'phase' => 'move', 'moves' => {}, 'encounter' => nil, 'last' => nil, 'log' => [], 'history' => [], 'reached' => []
        )
        players.each { |player| reveal!(player.seat.to_s) }
        share_team_maps!
        session.update!(turn: 1)
        post(render(config['msg_start'], count: players.size, size: size, turns: tier[:turns]))
        begin_turn!
      end

      # ── 명령 ──
      def handle(player, command, args, status)
        action = { config['cmd_move'] => :move, config['cmd_stay'] => :stay, config['cmd_pointme'] => :pointme, config['cmd_lumos'] => :lumos,
                   config['cmd_spell'] => :spell, config['cmd_cooperate'] => :cooperate, config['cmd_hinder'] => :hinder, config['cmd_flare'] => :flare }[command]
        return false if action.nil?
        return true if out?(player.seat.to_s)

        case action
        when :move then submit_path!(player, args)
        when :stay then submit_path!(player, [])
        when :pointme then use_pointme!(player)
        when :lumos then use_lumos!(player)
        when :spell then pick!(player, 'spell', SPELLS.keys.find { |key| [key, SPELLS[key]].include?(args.first.to_s.strip) })
        when :cooperate then pick!(player, 'stance', 'cooperate')
        when :hinder then pick!(player, 'stance', 'hinder', target: target_in(status, args))
        else forfeit!(player)
        end
        true
      end

      def timeout!
        state['phase'] == 'encounter' ? resolve_encounter! : resolve_moves!
      end

      def max_turns
        state['max_turns'].to_i
      end

      # 붉은 불꽃: 판을 끝내지 않고 그 사람만 탈락. 모두 탈락하면 우승자 없이 끝난다
      def forfeit!(player)
        seat = player.seat.to_s
        return if out?(seat) || session.status != 'active'

        state['out'] << player.seat
        state['moves'].delete(seat)
        (state['log'] ||= []) << render(config['msg_flare'], player: player)
        post(render(config['msg_flare'], player: player))
        return finish_maze!([], render(config['msg_all_out'])) if active_players.empty?

        session.save!
        proceed_if_ready!
      end

      def pending_seats
        waiting_on.map(&:seat)
      end

      def card_data
        {
          'size' => state['size'], 'max_turns' => max_turns, 'log' => state['log'] || [],
          'status' => (state['status'] || {}).transform_values { |value| value.slice('stunned', 'lumos') },
          'hostile' => Array(state['hostile']).map { |from, to| "#{from}-#{to}" },
          'phase' => state['phase'], 'web' => true,
        }
      end

      def card_actions
        []
      end

      # 팀전: 팀 채팅이 닿는 팀
      def team_of(player)
        state.dig('teams', player.seat.to_s)
      end

      # ── 보이는 것 ──
      # 참가자: 내(팀) 지도와 시야 안 / 관전자·끝난 판·탈락자: 전부
      def view_for(player)
        return nil if state['cells'].nil?

        seat = player&.seat&.to_s
        full = player.nil? || session.status == 'finished' || (seat && out?(seat))
        full ? full_view(player) : player_view(player, seat)
      end

      private

      # ── 도움 ──
      def size
        state['size']
      end

      def index_of(x, y)
        (y * size) + x
      end

      def open_side?(x, y, dir)
        (state['cells'][index_of(x, y)] & DIRS[dir][2]).positive?
      end

      def around(x, y, radius, limit = size)
        ((y - radius)..(y + radius)).flat_map do |cy|
          ((x - radius)..(x + radius)).filter_map { |cx| [cx, cy] if cx.between?(0, limit - 1) && cy.between?(0, limit - 1) }
        end
      end

      def player_of(seat)
        players.find { |player| player.seat.to_s == seat.to_s }
      end

      def out?(seat)
        Array(state['out']).include?(seat.to_i)
      end

      def active_players
        players.reject { |player| out?(player.seat) }
      end

      def stunned?(seat)
        state.dig('status', seat, 'stunned').to_i.positive?
      end

      def stun!(seat, turns)
        state['status'][seat]['stunned'] = [state['status'][seat]['stunned'].to_i, turns].max
      end

      def steps
        config['steps'].to_i.clamp(1, 3)
      end

      def vision_of(seat)
        base = config['vision'].to_i.clamp(1, 5)
        state.dig('status', seat, 'lumos').to_i.positive? ? base + config['lumos_bonus'].to_i.clamp(0, 3) : base
      end

      def visible_cells(seat)
        x, y = state['positions'][seat]
        around(x, y, vision_of(seat))
      end

      def reveal!(seat)
        state['seen'][seat] = state['seen'][seat] | visible_cells(seat).map { |cx, cy| index_of(cx, cy) }
      end

      def teammates(seat)
        team = state.dig('teams', seat)
        return [] if team.nil?

        state['teams'].select { |other, key| key == team && other != seat }.keys
      end

      # 팀원끼리 지도·알게 된 함정을 늘 함께 쓴다
      def share_team_maps!
        state['teams'].values.uniq.each do |team|
          seats = state['teams'].select { |_, key| key == team }.keys
          seen = seats.map { |seat| state['seen'][seat] }.reduce(:|)
          traps = seats.map { |seat| state['known_traps'][seat] }.reduce(:|)
          seats.each do |seat|
            state['seen'][seat] = seen.dup
            state['known_traps'][seat] = traps.dup
          end
        end
      end

      # 팀전: 소속(기숙사)마다 한 팀, 6명을 넘으면 나눈다 (그리핀도르 1·2)
      def house_teams
        groups = players.group_by { |player| player.character.group }
        groups.flat_map do |house, members|
          chunks = members.shuffle.each_slice(TEAM_MAX).to_a
          chunks.each_with_index.flat_map do |chunk, index|
            key = "#{house&.id || 'none'}-#{index}"
            name = [house&.name || '무소속', (chunks.size > 1 ? (index + 1).to_s : nil)].compact.join(' ')
            chunk.map { |player| [player.seat.to_s, { key: key, name: name, color: house&.color }] }
          end
        end.to_h
      end

      def same_team?(seat_a, seat_b)
        team = state.dig('teams', seat_a)
        team.present? && team == state.dig('teams', seat_b)
      end

      def pair_key(seat_a, seat_b)
        [seat_a.to_i, seat_b.to_i].sort.join('-')
      end

      def target_in(status, args)
        names = Array(args).map { |word| word.to_s.strip.delete_prefix('@') }.compact_blank
        by_name = names.filter_map { |name| players.find { |other| [other.account.username, other.account.acct].include?(name) } }
        by_mention = Array(status&.mentions).filter_map { |mention| players.find { |other| other.account_id == mention.account_id } }
        (by_name + by_mention).first
      end

      # 8방향 화살표 (포인트 미)
      def arrow(from_x, from_y, to_x, to_y)
        { [0, -1] => '↑', [1, -1] => '↗', [1, 0] => '→', [1, 1] => '↘', [0, 1] => '↓', [-1, 1] => '↙', [-1, 0] => '←', [-1, -1] => '↖', [0, 0] => '★' }[[to_x <=> from_x, to_y <=> from_y]]
      end

      # ── 턴 ──
      def turn_seconds
        config['turn_seconds'].to_i.clamp(15, 600)
      end

      def begin_turn!
        state['phase'] = 'move'
        state['moves'] = {}
        state['encounter'] = nil
        session.save!
        extra = session.turn == 1 ? config['first_turn_bonus'].to_i.clamp(0, 120) : 0
        Game::Engine.set_deadline_in!(session, (turn_seconds + extra).seconds)
        proceed_if_ready!
      end

      # 아직 이번 단계에 할 일을 안 한 사람
      def waiting_on
        if state['phase'] == 'encounter'
          encounter = state['encounter'] || {}
          active_players.select { |player| needs(player.seat.to_s).any? { |kind| !encounter.dig('picks', player.seat.to_s, kind) } }
        else
          active_players.reject { |player| stunned?(player.seat.to_s) || state['moves'].key?(player.seat.to_s) }
        end
      end

      def proceed_if_ready!
        return unless waiting_on.empty?

        state['phase'] == 'encounter' ? resolve_encounter! : resolve_moves!
      end

      def parse_path(seat, args)
        tokens = Array(args).flat_map { |arg| arg.to_s.strip.split(/[\s,]+|(?=[북동남서])/).flat_map { |token| token.length > 1 && token.match?(/\A[NESW]+\z/i) ? token.chars : [token] } }.compact_blank
        dirs = tokens.map { |token| DIR_NAMES[token] || (token.upcase if DIRS.key?(token.upcase)) }
        return if dirs.any?(&:nil?) || dirs.size > steps

        x, y = state['positions'][seat]
        dirs.each do |dir|
          return nil unless open_side?(x, y, dir)

          x += DIRS[dir][0]
          y += DIRS[dir][1]
        end
        dirs
      end

      def submit_path!(player, args)
        seat = player.seat.to_s
        return dm(player, '지금은 길을 고를 수 없습니다.') unless state['phase'] == 'move' && !stunned?(seat)

        path = parse_path(seat, args)
        return dm(player, '갈 수 없는 길입니다.') if path.nil?

        state['moves'][seat] = path
        session.save!
        proceed_if_ready!
      end

      def use_pointme!(player)
        seat = player.seat.to_s
        return unless state['phase'] == 'move' && state.dig('inventory', seat, 'pointme').to_i.positive?

        state['inventory'][seat]['pointme'] -= 1
        x, y = state['positions'][seat]
        state['hint'][seat] = { 'dir' => arrow(x, y, *state['cup']), 'turn' => session.turn, 'from' => [x, y] }
        session.save!
      end

      def use_lumos!(player)
        seat = player.seat.to_s
        return unless state['phase'] == 'move' && state.dig('inventory', seat, 'lumos').to_i.positive?

        state['inventory'][seat]['lumos'] -= 1
        state['status'][seat]['lumos'] = config['lumos_turns'].to_i.clamp(1, 10)
        reveal!(seat)
        session.save!
      end

      # ── ① 모두 함께 걷는다 ──
      def resolve_moves!
        log = []
        last = { 'turn' => session.turn, 'moves' => {}, 'events' => [] }
        creatures_met = {}
        active_players.each do |player|
          seat = player.seat.to_s
          if stunned?(seat)
            state['status'][seat]['stunned'] -= 1
            next
          end

          from = state['positions'][seat]
          walked = [from]
          Array(state['moves'][seat]).each do |dir|
            x, y = state['positions'][seat]
            break unless open_side?(x, y, dir)

            spot = [x + DIRS[dir][0], y + DIRS[dir][1]]
            state['positions'][seat] = spot
            walked << spot
            (state['trails'][seat] ||= []) << spot

            item = state['items'].find { |each| [each['x'], each['y']] == spot }
            if item
              state['items'].delete(item)
              state['inventory'][seat][item['kind']] = state['inventory'][seat][item['kind']].to_i + 1
              last['events'] << { 'kind' => 'item', 'seat' => player.seat, 'item' => item['kind'], 'at' => spot, 'private' => true }
            end
            if state['traps'].include?(spot)
              state['known_traps'][seat] |= [spot]
              stun!(seat, 1)
              log << render(config['msg_trap'], player: player)
              last['events'] << { 'kind' => 'trap', 'seat' => player.seat, 'at' => spot }
              break
            end
            if spot == state['cup']
              state['reached'] |= [player.seat]
              last['events'] << { 'kind' => 'cup', 'seat' => player.seat, 'at' => spot }
              break
            end
            if state['fakes'].include?(spot)
              # 가짜 우승컵(포트키): 무작위 입구로. 잡은 사람만 가짜였다는 걸 안다
              gate = state['gates'].sample
              state['grabbed'][seat] |= [spot]
              state['positions'][seat] = gate
              walked << gate
              state['trails'][seat] << gate
              last['events'] << { 'kind' => 'fake', 'seat' => player.seat, 'at' => spot, 'to' => gate, 'private' => true }
              break
            end
            creature = state['creatures'].find { |each| [each['x'], each['y']] == spot }
            if creature
              creatures_met[seat] = creature
              break
            end
          end
          last['moves'][seat] = walked
          reveal!(player.seat.to_s)
        end
        state['moves'] = {}
        share_team_maps!

        return finish_reached!(log, last) if state['reached'].any?

        groups = encounter_groups
        if creatures_met.empty? && groups.empty?
          end_turn!(log, last)
          return
        end

        state['phase'] = 'encounter'
        state['encounter'] = { 'creatures' => creatures_met, 'groups' => groups, 'picks' => {}, 'log' => log, 'last' => last }
        session.save!
        Game::Engine.set_deadline_in!(session, config['encounter_seconds'].to_i.clamp(10, 180).seconds)
      end

      # 같은 칸·옆 칸(상하좌우)의 참가자 무리 (팀원끼리는 조우하지 않는다, 같은 사람과는 몇 턴 쉬었다가)
      def encounter_groups
        links = Hash.new { |hash, key| hash[key] = [] }
        active_players.to_a.combination(2).each do |a, b|
          sa = a.seat.to_s
          sb = b.seat.to_s
          ax, ay = state['positions'][sa]
          bx, by = state['positions'][sb]
          next if (ax - bx).abs + (ay - by).abs > 1 || same_team?(sa, sb)

          met = state['met'][pair_key(sa, sb)]
          next if met && session.turn - met < MEET_COOLDOWN

          links[sa] << sb
          links[sb] << sa
        end
        seen = []
        links.keys.filter_map do |seat|
          next if seen.include?(seat)

          group = []
          queue = [seat]
          until queue.empty?
            current = queue.shift
            next if group.include?(current)

            group << current
            queue.concat(links[current])
          end
          seen.concat(group)
          group.sort_by(&:to_i)
        end
      end

      def needs(seat)
        encounter = state['encounter'] || {}
        list = []
        list << 'spell' if encounter.dig('creatures', seat)
        list << 'stance' if Array(encounter['groups']).any? { |group| group.include?(seat) }
        list
      end

      def pick!(player, kind, value, target: nil)
        seat = player.seat.to_s
        return unless state['phase'] == 'encounter' && needs(seat).include?(kind) && value

        if kind == 'stance' && value == 'hinder'
          group = Array(state['encounter']['groups']).find { |each| each.include?(seat) } || []
          return if target.nil? || target.seat.to_s == seat || group.exclude?(target.seat.to_s)
        end
        picks = (state['encounter']['picks'][seat] ||= {})
        picks[kind] = value
        picks['target'] = target.seat if target
        session.save!
        proceed_if_ready!
      end

      # ── ② 조우·마법 생물 결과 ──
      def resolve_encounter!
        encounter = state['encounter'] || {}
        log = encounter['log'] || []
        last = encounter['last'] || { 'turn' => session.turn, 'moves' => {}, 'events' => [] }
        picks = encounter['picks'] || {}

        (encounter['creatures'] || {}).each do |seat, creature|
          player = player_of(seat)
          info = CREATURES[creature['kind']]
          spell = picks.dig(seat, 'spell')
          if spell == info[:spell]
            state['creatures'].reject! { |each| each['x'] == creature['x'] && each['y'] == creature['y'] }
            log << render(config['msg_creature_win'], player: player, spell: SPELLS[spell], creature: info[:name])
            last['events'] << { 'kind' => 'creature_win', 'seat' => player.seat, 'creature' => creature['kind'], 'spell' => spell, 'at' => [creature['x'], creature['y']] }
          else
            turns = config['creature_stun'].to_i.clamp(1, 5)
            stun!(seat, turns)
            log << render(config['msg_creature_lose'], player: player, creature: info[:name], turns: turns)
            last['events'] << { 'kind' => 'creature_lose', 'seat' => player.seat, 'creature' => creature['kind'], 'spell' => spell, 'at' => [creature['x'], creature['y']] }
          end
        end

        (encounter['groups'] || []).each do |group|
          group.combination(2).each { |a, b| state['met'][pair_key(a, b)] = session.turn }
          friends = group.select { |seat| picks.dig(seat, 'stance') != 'hinder' }
          if friends.size >= 2
            seen = friends.map { |seat| state['seen'][seat] }.reduce(:|)
            traps = friends.map { |seat| state['known_traps'][seat] }.reduce(:|)
            friends.each do |seat|
              state['seen'][seat] = seen.dup
              state['known_traps'][seat] = traps.dup
            end
            log << render(config['msg_coop'], players: friends.map { |seat| player_of(seat).name }.join(', '))
            last['events'] << { 'kind' => 'coop', 'seats' => friends.map(&:to_i) }
          end
          group.each do |seat|
            next unless picks.dig(seat, 'stance') == 'hinder'

            target = picks.dig(seat, 'target').to_s
            next unless group.include?(target)

            stun!(target, 1)
            state['hostile'] |= [[seat.to_i, target.to_i]]
            log << render(config['msg_hinder'], player: player_of(seat), target: player_of(target))
            last['events'] << { 'kind' => 'hinder', 'seat' => seat.to_i, 'target' => target.to_i }
          end
        end
        share_team_maps!
        state['encounter'] = nil
        end_turn!(log, last)
      end

      # ── ③ 턴 끝 ──
      def end_turn!(log, last)
        active_players.each do |player|
          seat = player.seat.to_s
          reveal!(seat)
          state['status'][seat]['lumos'] -= 1 if state['status'][seat]['lumos'].to_i.positive?
        end
        share_team_maps!
        state['last'] = last
        state['log'] = log
        state['history'] << { 'turn' => session.turn, 'positions' => state['positions'].dup }
        text = render(config['msg_turn'], turn: session.turn, lines: (log.presence || [render(config['msg_quiet'])]).join("\n"))
        if session.turn >= max_turns
          finish_maze!([], "#{text}\n\n#{render(config['msg_limit'], turns: session.turn)}")
        else
          post(text)
          session.update!(turn: session.turn + 1)
          begin_turn!
        end
      end

      def finish_reached!(log, last)
        state['last'] = last
        state['log'] = log
        state['history'] << { 'turn' => session.turn, 'positions' => state['positions'].dup }
        reached = state['reached'].filter_map { |seat| player_of(seat) }
        text = render(config['msg_turn'], turn: session.turn, lines: (log.presence || [render(config['msg_quiet'])]).join("\n"))
        ending = if state['teams'].any?
                   render(config['msg_team_win'], winner: reached.first, team: state.dig('team_info', team_of(reached.first), 'name'))
                 elsif reached.size == 1
                   render(config['msg_win'], winner: reached.first, turn: session.turn)
                 else
                   render(config['msg_tie'], players: reached.map(&:name).join(', '))
                 end
        finish_maze!(reached, "#{text}\n\n#{ending}")
      end

      # 끝: 순위(우승컵까지의 최단 거리)를 정하고 점수·보상은 공통 처리(finish!)로
      def finish_maze!(reached, message)
        distances = distances_from(state['cup'])
        rows = players.map do |player|
          seat = player.seat.to_s
          x, y = state['positions'][seat]
          { 'seat' => player.seat, 'dist' => reached.include?(player) ? 0 : distances[index_of(x, y)], 'out' => out?(seat) }
        end
        sorted = rows.sort_by { |row| [row['out'] ? 1 : 0, row['dist'] || 9_999] }
        rank = 0
        previous = nil
        sorted.each_with_index do |row, index|
          key = [row['out'], row['dist']]
          rank = index + 1 unless key == previous
          previous = key
          row['rank'] = rank
        end
        state['ranks'] = sorted
        state['team_ranks'] = team_ranks(sorted, reached) if state['teams'].any?
        state['phase'] = 'finished'
        session.save!

        winners = if reached.empty? then []
                  elsif state['teams'].any? then players.select { |player| reached.map { |each| team_of(each) }.include?(team_of(player)) }
                  else reached
                  end
        if winners.empty?
          finish!(draw: true, message: message)
        else
          finish!(winners: winners, split_points: state['teams'].empty? && winners.size > 1, message: message)
        end
      end

      # 팀전 순위: 우승자의 팀이 1위, 나머지는 팀원 순위 점수(인원 - 순위 + 1)의 합
      def team_ranks(sorted, reached)
        total = players.size
        scores = Hash.new(0)
        sorted.each { |row| scores[state.dig('teams', row['seat'].to_s)] += total - row['rank'] + 1 }
        winners = reached.map { |player| team_of(player) }
        scores.keys.sort_by { |key| [winners.include?(key) ? 0 : 1, -scores[key]] }.each_with_index.map do |key, index|
          { 'team' => key, 'name' => state.dig('team_info', key, 'name'), 'color' => state.dig('team_info', key, 'color'), 'score' => scores[key], 'rank' => index + 1 }
        end
      end

      # 한 칸에서 미로 길로 모든 칸까지의 거리 (BFS)
      def distances_from(spot)
        dist = Array.new(size * size)
        dist[index_of(*spot)] = 0
        queue = [spot]
        until queue.empty?
          x, y = queue.shift
          DIRS.each do |dir, (dx, dy, _, _)|
            next unless open_side?(x, y, dir)

            nx = x + dx
            ny = y + dy
            next unless nx.between?(0, size - 1) && ny.between?(0, size - 1) && dist[index_of(nx, ny)].nil?

            dist[index_of(nx, ny)] = dist[index_of(x, y)] + 1
            queue << [nx, ny]
          end
        end
        dist
      end

      # ── 화면 데이터 ──
      # 누를 수 있는 칸: 아는 칸 안에서 열린 길로 최대 N칸 (보이는 마법 생물·우승컵 칸은 거기까지)
      def reachable(seat)
        return [] if state['phase'] != 'move' || stunned?(seat)

        x, y = state['positions'][seat]
        known = (state['seen'][seat] | visible_cells(seat).map { |cx, cy| index_of(cx, cy) })
        stops = state['creatures'].map { |each| [each['x'], each['y']] } + [state['cup']] + state['fakes']
        best = { [x, y] => [] }
        queue = [[x, y]]
        until queue.empty?
          cx, cy = queue.shift
          path = best[[cx, cy]]
          next if path.size >= steps || (path.any? && stops.include?([cx, cy]))

          DIRS.each do |dir, (dx, dy, _, _)|
            nx = cx + dx
            ny = cy + dy
            next unless nx.between?(0, size - 1) && ny.between?(0, size - 1)
            next unless open_side?(cx, cy, dir) && known.include?(index_of(nx, ny)) && !best.key?([nx, ny])

            best[[nx, ny]] = path + [dir]
            queue << [nx, ny]
          end
        end
        best.reject { |cell, _| cell == [x, y] }.map { |(rx, ry), path| { x: rx, y: ry, path: path } }
      end

      def people
        players.map do |other|
          seat = other.seat.to_s
          {
            seat: other.seat, name: other.name, account_id: other.account_id, team: state.dig('teams', seat),
            stunned: state.dig('status', seat, 'stunned').to_i, lumos: state.dig('status', seat, 'lumos').to_i, out: out?(seat),
            chosen: state['phase'] == 'move' ? state['moves'].key?(seat) || stunned?(seat) : needs(seat).all? { |kind| state.dig('encounter', 'picks', seat, kind) },
          }
        end
      end

      def common_view
        {
          status: session.status, turn: session.turn, max_turns: max_turns, phase: state['phase'], size: size,
          deadline_at: session.deadline_at&.iso8601, now: Time.current.iso8601(3),
          team_mode: state['teams'].any?, teams: state['team_info'] || {},
          hostile: Array(state['hostile']).map { |from, to| { from: from, to: to } },
          players: people, log: state['log'] || [], waiting: waiting_on.map(&:name),
          commands: { move: config['cmd_move'], stay: config['cmd_stay'], pointme: config['cmd_pointme'], lumos: config['cmd_lumos'],
                      spell: config['cmd_spell'], cooperate: config['cmd_cooperate'], hinder: config['cmd_hinder'], flare: config['cmd_flare'] },
          spells: SPELLS.map { |key, name| { key: key, name: name } },
          lumos_turns: config['lumos_turns'].to_i, steps: steps,
          finish: session.status == 'finished' ? { ranks: state['ranks'] || [], team_ranks: state['team_ranks'] || [], reached: state['reached'] || [], test: session.test? } : nil,
        }
      end

      def player_view(player, seat)
        visible = visible_cells(seat).map { |x, y| index_of(x, y) }
        known = state['seen'][seat] | visible
        mates = teammates(seat)
        cups = ([state['cup']] + state['fakes']).select { |x, y| known.include?(index_of(x, y)) }
        encounter = state['encounter']
        my_creature = encounter&.dig('creatures', seat)
        my_group = Array(encounter&.dig('groups')).find { |group| group.include?(seat) }
        common_view.merge(
          me: player.seat, spectator: false, full: false, position: state['positions'][seat], vision: vision_of(seat),
          cells: known.to_h { |index| [index, state['cells'][index]] }, visible: visible,
          cups: cups.map { |x, y| { x: x, y: y, broken: state['grabbed'][seat].include?([x, y]) } },
          traps: state['known_traps'][seat].map { |x, y| { x: x, y: y } },
          creatures: state['creatures'].select { |each| visible.include?(index_of(each['x'], each['y'])) }.map { |each| creature_view(each) },
          items: state['items'].select { |each| visible.include?(index_of(each['x'], each['y'])) },
          tokens: players.filter_map do |other|
            other_seat = other.seat.to_s
            next if out?(other_seat) && other_seat != seat
            x, y = state['positions'][other_seat]
            next unless other_seat == seat || mates.include?(other_seat) || visible.include?(index_of(x, y))

            { seat: other.seat, x: x, y: y }
          end,
          trails: ([seat] + mates).to_h { |each| [each, state['trails'][each] || []] },
          gates: state['gates'],
          hint: state['hint'][seat],
          inventory: { pointme: state.dig('inventory', seat, 'pointme').to_i, lumos: state.dig('inventory', seat, 'lumos').to_i },
          stunned: state.dig('status', seat, 'stunned').to_i, lumos: state.dig('status', seat, 'lumos').to_i,
          reachable: reachable(seat), planned: state['moves'][seat],
          submitted: state['phase'] == 'move' ? state['moves'].key?(seat) || stunned?(seat) : needs(seat).all? { |kind| encounter&.dig('picks', seat, kind) },
          encounter: encounter && (my_creature || my_group) ? {
            creature: my_creature && creature_view(my_creature, hint: true),
            group: my_group&.map(&:to_i),
            picks: encounter.dig('picks', seat) || {},
          } : nil,
          last: last_for(seat, visible, mates)
        )
      end

      # 관전자·끝난 판·탈락자: 미로 전체와 진짜·가짜 우승컵, 모든 위치
      def full_view(player)
        all = (0...(size * size)).to_a
        common_view.merge(
          me: player&.seat, spectator: player.nil?, full: true, position: player && state['positions'][player.seat.to_s], vision: 0,
          cells: all.to_h { |index| [index, state['cells'][index]] }, visible: all,
          cups: [{ x: state['cup'][0], y: state['cup'][1], real: true }] + state['fakes'].map { |x, y| { x: x, y: y, real: false } },
          traps: state['traps'].map { |x, y| { x: x, y: y } },
          creatures: state['creatures'].map { |each| creature_view(each, hint: true) },
          items: state['items'],
          tokens: players.reject { |other| out?(other.seat) }.map { |other| { seat: other.seat, x: state['positions'][other.seat.to_s][0], y: state['positions'][other.seat.to_s][1] } },
          trails: state['trails'] || {}, gates: state['gates'], hint: nil, inventory: { pointme: 0, lumos: 0 },
          stunned: 0, lumos: 0, reachable: [], planned: nil, submitted: true, encounter: nil,
          last: state['last']
        )
      end

      def creature_view(creature, hint: false)
        info = CREATURES[creature['kind']]
        { x: creature['x'], y: creature['y'], kind: creature['kind'], name: info[:name], hint: hint ? info[:hint] : nil }
      end

      # 지난 턴 움직임(애니메이션): 나와 팀원, 지금 보이는 사람만. 가짜 우승컵·아이템처럼 혼자만 아는 일은 본인(팀원)에게만
      def last_for(seat, visible, mates)
        last = state['last']
        return nil if last.nil?

        mine = [seat] + mates
        moves = last['moves'].select do |other, path|
          mine.include?(other) || Array(path).any? { |x, y| visible.include?(index_of(x, y)) }
        end
        events = last['events'].select { |event| !event['private'] || mine.include?(event['seat'].to_s) }
        last.merge('moves' => moves, 'events' => events)
      end

      # ── 미로 만들기 ──
      # 길 파기(깊이 우선) + 벽 몇 개를 더 터서 갈림길. cells[i] = 열린 방향 비트 (N1 E2 S4 W8)
      def carve(size)
        cells = Array.new(size * size, 0)
        visited = Array.new(size * size, false)
        start = [size / 2, size / 2]
        stack = [start]
        visited[(start[1] * size) + start[0]] = true
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

        (size * size / 9).times do
          x = rand(size - 1)
          y = rand(size - 1)
          dx, dy, bit, back = DIRS[%w(E S).sample]
          cells[(y * size) + x] |= bit
          cells[((y + dy) * size) + x + dx] |= back
        end
        cells
      end

      # 입구: 네 변 가운데 (+ 네 모서리). nil = 2~4명용 네 변 가운데
      def gates_for(size, count)
        mid = size / 2
        sides = [[mid, 0], [size - 1, mid], [mid, size - 1], [0, mid]]
        corners = [[0, 0], [size - 1, 0], [size - 1, size - 1], [0, size - 1]]
        count.to_i >= 8 ? sides + corners : sides
      end

      # 가짜 우승컵: 한가운데에서 조금 떨어진 곳 (진짜처럼 보이게 너무 멀지 않게)
      def fake_spots(size, cup, gates, count)
        mid = size / 2
        near = (0...size).to_a.product((0...size).to_a).select do |x, y|
          distance = [(x - mid).abs, (y - mid).abs].max
          distance.between?(size / 6, size / 3) && [x, y] != cup && gates.exclude?([x, y])
        end
        near.sample(count)
      end
    end
  end
end
