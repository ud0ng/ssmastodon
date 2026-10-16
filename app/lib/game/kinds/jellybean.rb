# frozen_string_literal: true

module Game
  module Kinds
    # 젤리빈 룰렛: 봉지에서 번갈아 젤리빈을 꺼내 먹는다. 최악의 맛을 먹으면 패배.
    class Jellybean < Base
      KEY = 'jellybean'

      FIELDS = (base_fields(name: '젤리빈 룰렛', command: '젤리빈', points_win: 5) + [
        F.new(key: 'cmd_eat', type: :string, default: '먹기', group: 'commands', label: '먹기 명령어', hint: '[먹기] 또는 [먹기/개수]'),
        F.new(key: 'beans', type: :integer, default: 10, group: 'rules', label: '젤리빈 수'),
        F.new(key: 'worst_count', type: :integer, default: 1, group: 'rules', label: '최악의 맛 수'),
        F.new(key: 'max_per_turn', type: :integer, default: 3, group: 'rules', label: '한 번에 먹을 수 있는 수'),
        F.new(key: 'worst_flavor', type: :string, default: '토사물 맛', group: 'flavors', label: '최악의 맛'),
        F.new(key: 'flavors', type: :lines, group: 'flavors', label: '보통 맛 (줄마다 하나)', hint: '연출용. 이 중에서 무작위로 나온다',
              default: %w(딸기\ 맛 잘린\ 풀\ 맛 비누\ 맛 귀지\ 맛 정어리\ 맛 후추\ 맛 코딱지\ 맛 버터맥주\ 맛 시금치\ 맛 바닐라\ 맛 썩은\ 달걀\ 맛 마멀레이드\ 맛)),
        F.new(key: 'msg_start', type: :text, group: 'messages', label: '시작',
              default: "%{game} 시작!\n봉지에 들어있는 젤리빈 %{count}개, 그중 최악의 맛이 %{worst}개 숨어 있습니다.\n\n[%{eat}] 또는 [%{eat}/개수]로 답해 주세요. (한 번에 %{max}개까지)"),
        F.new(key: 'msg_eat', type: :text, group: 'messages', label: '먹기 한 개', hint: '{먹은 젤리빈} 자리에 이 문구가 먹은 개수만큼 줄마다 그대로 들어갑니다', default: "%{player}{이가} [%{flavor}] 젤리빈을 먹습니다."),
        F.new(key: 'msg_turn', type: :text, group: 'messages', label: '턴 결과',
              default: "%{eaten}\n남은 젤리빈은 %{remaining}개입니다."),
        F.new(key: 'msg_worst', type: :text, group: 'messages', label: '최악의 맛',
              default: "%{eaten}\n%{player}{이가} 최악의 맛을 먹었습니다!\n%{winner}의 승리!"),
        F.new(key: 'msg_not_turn', type: :text, group: 'messages', label: '차례 아님', default: '지금은 %{player}의 차례입니다.'),
        F.new(key: 'msg_timeout', type: :text, group: 'messages', label: '시간 초과',
              default: "%{player}{이가} %{seconds}초 동안 젤리빈을 고르지 못했습니다.\n%{winner}의 승리!"),
      ]).freeze

      def start!
        count = config['beans'].to_i.clamp(2, 100)
        worst = config['worst_count'].to_i.clamp(1, count - 1)
        flavors = config['flavors'].presence || ['알 수 없는 맛']
        bag = Array.new(worst) { { 'flavor' => config['worst_flavor'], 'worst' => true } } +
              Array.new(count - worst) { { 'flavor' => flavors.sample, 'worst' => false } }

        state.merge!('bag' => bag.shuffle, 'seat' => players.map(&:seat).sample, 'total' => count, 'worst_total' => worst)
        session.update!(turn: 1)
        post(render(config['msg_start'], count: count, worst: worst, player: current, eat: config['cmd_eat'], max: config['max_per_turn']))
        wait_for_turn!
      end

      def handle(player, command, args, _status)
        return false unless command == config['cmd_eat']

        if player.seat != state['seat']
          post(render(config['msg_not_turn'], player: current))
          return true
        end

        bag = state['bag']
        count = args.first.to_i.clamp(1, [config['max_per_turn'].to_i, 1].max)
        count = [count, bag.size].min
        eaten = []
        worst = false
        state['last_eaten'] = { 'seat' => player.seat, 'beans' => [] }
        state['eaten_log'] ||= []
        count.times do
          bean = bag.shift
          state['last_eaten']['beans'] << bean
          state['eaten_log'] << { 'seat' => player.seat, 'worst' => bean['worst'], 'flavor' => bean['flavor'] }
          eaten << render(config['msg_eat'], player: player, flavor: bean['flavor'])
          if bean['worst']
            worst = true
            break
          end
        end

        if worst
          winner = session.opponent_of(player)
          finish!(winner: winner, message: render(config['msg_worst'], turn: session.turn, eaten: eaten.join("\n"), player: player, winner: winner))
        else
          state['seat'] = session.opponent_of(player).seat
          post(render(config['msg_turn'], turn: session.turn, eaten: eaten.join("\n"), remaining: bag.size, next: current))
          session.update!(turn: session.turn + 1)
          wait_for_turn!
        end
        true
      end

      def card_data
        bag = state['bag'] || []
        {
          'remaining' => bag.size,
          'total' => state['total'] || config['beans'].to_i,
          'worst_total' => state['worst_total'] || config['worst_count'].to_i,
          'worst_flavor' => config['worst_flavor'],
          'current_seat' => state['seat'],
          'last_eaten' => state['last_eaten'],
          # 먹은 순서대로 누가 먹었는지 (웹 게임판: 젤리빈마다 먹은 사람 인장, 최악의 맛은 해골)
          'eaten' => state['eaten_log'] || [],
        }
      end

      def card_actions
        return [] if state['seat'].nil?

        max = [[config['max_per_turn'].to_i, 1].max, (state['bag'] || []).size].min
        (1..max).map do |count|
          command = count == 1 ? config['cmd_eat'] : "#{config['cmd_eat']}/#{count}"
          Game::Card.action(command, label: count == 1 ? config['cmd_eat'] : "#{config['cmd_eat']} #{count}", seats: [state['seat']], style: count == 1 ? 'primary' : 'secondary')
        end
      end

      # 차례인 사람이 시간 안에 먹지 않으면 패배
      def timeout!
        state['last_eaten'] = nil
        loser = current
        winner = session.opponent_of(loser)
        finish!(winner: winner, message: render(config['msg_timeout'], player: loser, winner: winner, **Game::Config.turn_time))
      end

      private

      def current
        players.find { |player| player.seat == state['seat'] }
      end
    end
  end
end
