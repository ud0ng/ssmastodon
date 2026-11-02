# frozen_string_literal: true

module Game
  module Kinds
    # 구슬 홀짝 (블러핑 + 베팅, 1:1): 각자 구슬 10개로 시작한다. 라운드마다 역할을 번갈아,
    #   ① 숨기는 사람이 DM 으로 손에 쥘 구슬 수를 몰래 정하고 (1개 이상, 가진 만큼까지)
    #   ② 맞히는 사람이 공개로 [홀/건 수] 또는 [짝/건 수] 를 말한다 (내 구슬과 상대 구슬 중 적은 쪽까지).
    #   맞히면 건 만큼 상대에게서 가져오고, 틀리면 건 만큼 내준다. 구슬을 다 잃으면 패배.
    #   시간 초과: 숨기는 사람은 무작위로 쥐고, 맞히는 사람은 1개를 걸고 틀린 것으로 친다.
    #   최대 라운드가 지나면 구슬이 많은 쪽 승리 (같으면 무승부).
    class Marbles < Base
      KEY = 'marbles'

      FIELDS = (base_fields(name: '구슬 홀짝', command: '홀짝', points_win: 5, points_draw: 2) + [
        F.new(key: 'marbles', type: :integer, default: 10, group: 'rules', label: '시작 구슬 수'),
        F.new(key: 'max_rounds', type: :integer, default: 20, group: 'rules', label: '최대 라운드', hint: '넘으면 구슬이 많은 쪽 승리'),
        F.new(key: 'cmd_hide', type: :string, default: '쥐기', group: 'commands', label: '쥐기 명령어 (숨기는 사람, DM)', hint: '[쥐기/숫자]'),
        F.new(key: 'cmd_odd', type: :string, default: '홀', group: 'commands', label: '홀 명령어 (맞히는 사람)', hint: '[홀/건 수]'),
        F.new(key: 'cmd_even', type: :string, default: '짝', group: 'commands', label: '짝 명령어 (맞히는 사람)', hint: '[짝/건 수]'),
        F.new(key: 'msg_start', type: :text, group: 'messages', label: '시작',
              default: "%{game} 시작! 각자 구슬 %{marbles}개로 시작합니다.\n숨기는 사람은 DM 으로 [%{hide}/숫자], 맞히는 사람은 [%{odd}/건 수] 또는 [%{even}/건 수] 로 답해 주세요. 역할은 라운드마다 바뀝니다."),
        F.new(key: 'msg_hide_ask', type: :text, group: 'messages', label: 'DM: 쥘 구슬 고르기',
              default: "%{round}라운드 | 숨기는 차례입니다. 손에 쥘 구슬 수를 [%{hide}/숫자] 로 보내 주세요. (1~%{max})"),
        F.new(key: 'msg_hidden', type: :text, group: 'messages', label: 'DM: 쥐기 확인', default: '구슬 %{count}개를 손에 쥐었습니다.'),
        F.new(key: 'msg_bad_hide', type: :text, group: 'messages', label: 'DM: 잘못된 숫자', default: '1부터 %{max}까지의 숫자로 보내 주세요.'),
        F.new(key: 'msg_guess_ask', type: :text, group: 'messages', label: '맞히기 차례',
              default: "%{round}라운드 | %{hider}{이가} 구슬을 손에 쥐었습니다.\n%{guesser}{은는} [%{odd}/건 수] 또는 [%{even}/건 수] 로 맞혀 주세요. (1~%{max}개까지 걸 수 있습니다)"),
        F.new(key: 'msg_bad_bet', type: :text, group: 'messages', label: '잘못된 베팅', default: '1부터 %{max}까지 걸 수 있습니다.'),
        F.new(key: 'msg_not_turn', type: :text, group: 'messages', label: '차례 아님', default: '지금은 %{player}의 차례입니다.'),
        F.new(key: 'msg_round', type: :text, group: 'messages', label: '라운드 결과',
              default: "%{round}라운드\n%{guesser}: %{guess} · %{bet}개 걸기\n%{hider}의 손에는 구슬 %{count}개 (%{answer})\n%{outcome}\n\n구슬 %{board}"),
        F.new(key: 'msg_right', type: :text, group: 'messages', label: '맞힘', default: '맞혔습니다! %{guesser}{이가} %{bet}개를 가져갑니다.'),
        F.new(key: 'msg_wrong', type: :text, group: 'messages', label: '틀림', default: '틀렸습니다! %{guesser}{이가} %{bet}개를 내줍니다.'),
        F.new(key: 'msg_timeout_guess', type: :text, group: 'messages', label: '맞히기 시간 초과', default: '시간 안에 맞히지 못했습니다'),
        F.new(key: 'msg_win', type: :text, group: 'messages', label: '승리', default: '%{loser}{이가} 구슬을 모두 잃었습니다. %{winner}의 승리!'),
        F.new(key: 'msg_limit', type: :text, group: 'messages', label: '최대 라운드', default: '%{rounds}라운드가 끝났습니다. %{outcome}'),
        F.new(key: 'msg_limit_win', type: :text, group: 'messages', label: '최대 라운드 승리', default: '구슬이 더 많은 %{winner}의 승리!'),
        F.new(key: 'msg_draw', type: :text, group: 'messages', label: '무승부', default: '구슬 수가 같아 무승부입니다.'),
      ]).freeze

      def self.continues_on_timeout?
        true
      end

      def start!
        count = config['marbles'].to_i.clamp(1, 99)
        state.merge!('marbles' => players.to_h { |player| [player.seat.to_s, count] }, 'hider' => players.map(&:seat).sample, 'phase' => 'hide', 'hidden' => nil, 'rounds' => [])
        session.update!(turn: 1)
        post(render(config['msg_start'], marbles: count, hide: config['cmd_hide'], odd: config['cmd_odd'], even: config['cmd_even']))
        ask_hide!
      end

      def handle(player, command, args, status)
        action = { config['cmd_hide'] => :hide, config['cmd_odd'] => :odd, config['cmd_even'] => :even }[command]
        return false if action.nil?

        action == :hide ? hide!(player, args, status) : guess!(player, action, args, status)
        true
      end

      def timeout!
        if state['phase'] == 'hide'
          state['hidden'] = rand(1..marbles_of(hider))
          state['phase'] = 'guess'
          session.save!
          ask_guess!
        else
          settle!(nil, 1)
        end
      end

      def max_turns
        config['max_rounds'].to_i.clamp(1, 99)
      end

      # 숨긴 수는 끝날 때까지 공개하지 않는다 (지난 라운드 결과에만)
      def card_data
        {
          'marbles' => state['marbles'] || {}, 'max_marbles' => config['marbles'].to_i * players.size,
          'phase' => state['phase'], 'hider_seat' => state['hider'], 'guesser_seat' => guesser&.seat,
          'last_round' => Array(state['rounds']).last,
        }
      end

      def card_actions
        return [] unless %w(hide guess).include?(state['phase'])

        if state['phase'] == 'hide'
          [Game::Card.action(config['cmd_hide'], seats: [state['hider']], dm: true, hint: "[#{config['cmd_hide']}/숫자]")]
        else
          %w(odd even).map { |key| Game::Card.action(config["cmd_#{key}"], seats: [guesser.seat], hint: "[#{config["cmd_#{key}"]}/건 수]") }
        end
      end

      def pending_seats
        case state['phase']
        when 'hide' then [state['hider']]
        when 'guess' then [guesser.seat]
        else []
        end
      end

      private

      def hider
        players.find { |player| player.seat == state['hider'] }
      end

      def guesser
        players.find { |player| player.seat != state['hider'] }
      end

      def marbles_of(player)
        state['marbles'][player.seat.to_s]
      end

      def max_bet
        [marbles_of(guesser), marbles_of(hider)].min
      end

      def board
        players.map { |player| "#{player.name} #{marbles_of(player)}" }.join(' · ')
      end

      def ask_hide!
        dm(hider, render(config['msg_hide_ask'], round: session.turn, hide: config['cmd_hide'], max: marbles_of(hider)))
        wait_for_turn!
      end

      def ask_guess!
        post(render(config['msg_guess_ask'], round: session.turn, hider: hider, guesser: guesser, odd: config['cmd_odd'], even: config['cmd_even'], max: max_bet))
        wait_for_turn!
      end

      def hide!(player, args, status)
        return post(render(config['msg_not_turn'], player: state['phase'] == 'hide' ? hider : guesser)) unless state['phase'] == 'hide' && player.seat == state['hider']
        return unless require_dm!(player, status)

        count = number_arg(args, status)
        return dm(player, render(config['msg_bad_hide'], max: marbles_of(player))) if count.nil? || !count.between?(1, marbles_of(player))

        state['hidden'] = count
        state['phase'] = 'guess'
        session.save!
        dm(player, render(config['msg_hidden'], count: count))
        ask_guess!
      end

      def guess!(player, parity, args, status)
        return post(render(config['msg_not_turn'], player: state['phase'] == 'hide' ? hider : guesser)) unless state['phase'] == 'guess' && player.seat == guesser.seat

        bet = number_arg(args, status)
        return post(render(config['msg_bad_bet'], max: max_bet)) if bet.nil? || !bet.between?(1, max_bet)

        settle!(parity.to_s, bet)
      end

      # parity: 'odd' / 'even' / nil(시간 초과 = 틀림)
      def settle!(parity, bet)
        count = state['hidden'].to_i
        answer = count.odd? ? 'odd' : 'even'
        right = parity == answer
        taker, giver = right ? [guesser, hider] : [hider, guesser]
        bet = [bet, marbles_of(giver)].min
        state['marbles'][taker.seat.to_s] += bet
        state['marbles'][giver.seat.to_s] -= bet

        guess_label = parity ? config["cmd_#{parity}"] : render(config['msg_timeout_guess'])
        outcome = render(config[right ? 'msg_right' : 'msg_wrong'], guesser: guesser, bet: bet)
        state['rounds'] << { 'round' => session.turn, 'hider_seat' => hider.seat, 'count' => count, 'guess' => parity, 'bet' => bet, 'right' => right }
        text = render(config['msg_round'], round: session.turn, guesser: guesser, guess: guess_label, bet: bet, hider: hider, count: count,
                                           answer: config["cmd_#{answer}"], outcome: outcome, board: board)

        broke = players.find { |player| marbles_of(player) <= 0 }
        if broke
          state['phase'] = 'done'
          winner = session.opponent_of(broke)
          finish!(winner: winner, message: "#{text}\n\n#{render(config['msg_win'], winner: winner, loser: broke)}")
        elsif session.turn >= max_turns
          state['phase'] = 'done'
          a, b = players
          if marbles_of(a) == marbles_of(b)
            finish!(draw: true, message: "#{text}\n\n#{render(config['msg_limit'], rounds: max_turns, outcome: render(config['msg_draw']))}")
          else
            winner = marbles_of(a) > marbles_of(b) ? a : b
            finish!(winner: winner, message: "#{text}\n\n#{render(config['msg_limit'], rounds: max_turns, outcome: render(config['msg_limit_win'], winner: winner))}")
          end
        else
          post(text)
          state['hider'] = guesser.seat # 역할 바꾸기
          state['hidden'] = nil
          state['phase'] = 'hide'
          session.update!(turn: session.turn + 1)
          ask_hide!
        end
      end
    end
  end
end
