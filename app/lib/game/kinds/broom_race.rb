# frozen_string_literal: true

module Game
  module Kinds
    # 빗자루 경주 (자원 배분, 1:1): 각자 체력 15를 5바퀴에 나눠 쓴다. 바퀴마다 DM 으로 투입량을 몰래 내고 동시에 공개,
    # 많이 넣은 쪽이 그 바퀴를 이긴다 (같으면 아무도 못 이김). 3바퀴를 먼저 이기면 승리. 남은 체력은 모두에게 공개. 운 요소 없음.
    #   시간 안에 안 내면 0 을 낸 것으로 친다. 5바퀴가 끝나도 3승이 없으면 이긴 바퀴가 많은 쪽 승리 (같으면 무승부).
    class BroomRace < Base
      KEY = 'broom_race'

      FIELDS = (base_fields(name: '빗자루 경주', command: '경주', points_win: 5, points_draw: 2) + [
        F.new(key: 'stamina', type: :integer, default: 15, group: 'rules', label: '시작 체력'),
        F.new(key: 'laps', type: :integer, default: 5, group: 'rules', label: '바퀴 수'),
        F.new(key: 'wins_needed', type: :integer, default: 3, group: 'rules', label: '이기는 데 필요한 바퀴 수'),
        F.new(key: 'cmd_push', type: :string, default: '투입', group: 'commands', label: '투입 명령어', hint: '[투입/숫자] 를 DM 으로'),
        F.new(key: 'msg_start', type: :text, group: 'messages', label: '시작',
              default: "%{game} 시작! 각자 체력 %{stamina}로 %{laps}바퀴를 돕니다. %{wins}바퀴를 먼저 이기면 승리!\n바퀴마다 시스템 계정이 보내는 DM 에 [%{push}/숫자] 로 이번 바퀴에 쓸 체력을 답해 주세요."),
        F.new(key: 'msg_ask', type: :text, group: 'messages', label: 'DM: 투입량 고르기',
              default: "%{lap}바퀴 | 이번 바퀴에 쓸 체력을 [%{push}/숫자] 로 보내 주세요. (0~%{left})\n남은 체력: %{board}"),
        F.new(key: 'msg_chosen', type: :text, group: 'messages', label: 'DM: 선택 확인', default: '%{amount}만큼 쓰기로 했습니다. 상대를 기다립니다.'),
        F.new(key: 'msg_bad_amount', type: :text, group: 'messages', label: 'DM: 잘못된 숫자', default: '0부터 남은 체력(%{left})까지의 숫자로 보내 주세요.'),
        F.new(key: 'msg_lap', type: :text, group: 'messages', label: '바퀴 결과',
              default: "%{lap}바퀴\n%{player_a} %{amount_a} : %{amount_b} %{player_b}\n%{outcome}\n\n이긴 바퀴 %{score} · 남은 체력 %{board}"),
        F.new(key: 'msg_lap_win', type: :text, group: 'messages', label: '바퀴 승리', default: '%{winner}{이가} 앞서 나갔습니다!'),
        F.new(key: 'msg_lap_tie', type: :text, group: 'messages', label: '바퀴 동률', default: '나란히 결승선을 통과했습니다. 이번 바퀴는 아무도 못 이겼습니다.'),
        F.new(key: 'msg_win', type: :text, group: 'messages', label: '승리', default: '%{winner}{이가} %{wins}바퀴를 이겨 우승했습니다!'),
        F.new(key: 'msg_end', type: :text, group: 'messages', label: '마지막 바퀴 뒤 승리', default: '%{laps}바퀴가 끝났습니다. 더 많은 바퀴를 이긴 %{winner}의 승리!'),
        F.new(key: 'msg_draw', type: :text, group: 'messages', label: '무승부', default: '%{laps}바퀴가 끝났습니다. 이긴 바퀴 수가 같아 무승부입니다.'),
      ]).freeze

      def self.continues_on_timeout?
        true
      end

      def start!
        stamina = config['stamina'].to_i.clamp(1, 99)
        state.merge!('stamina' => players.to_h { |player| [player.seat.to_s, stamina] }, 'wins' => players.to_h { |player| [player.seat.to_s, 0] }, 'choices' => {}, 'laps' => [])
        session.update!(turn: 1)
        post(render(config['msg_start'], stamina: stamina, laps: laps, wins: wins_needed, push: config['cmd_push']))
        ask_all!
      end

      def handle(player, command, args, status)
        return false unless command == config['cmd_push']
        return true unless require_dm!(player, status)

        seat = player.seat.to_s
        left = state['stamina'][seat]
        amount = Integer(args.first.to_s.strip, exception: false)
        if amount.nil? || !amount.between?(0, left)
          dm(player, render(config['msg_bad_amount'], left: left))
          return true
        end

        state['choices'][seat] = amount
        session.save!
        dm(player, render(config['msg_chosen'], amount: amount))
        resolve! if state['choices'].size == players.size
        true
      end

      # 시간 안에 안 낸 사람은 0
      def timeout!
        resolve!
      end

      def max_turns
        laps
      end

      def card_data
        {
          'stamina' => state['stamina'] || {}, 'max_stamina' => config['stamina'].to_i,
          'wins' => state['wins'] || {}, 'wins_needed' => wins_needed, 'laps' => laps,
          'chosen' => (state['choices'] || {}).keys, 'last_lap' => Array(state['laps']).last,
        }
      end

      def card_actions
        seats = pending_seats
        seats.empty? ? [] : [Game::Card.action(config['cmd_push'], seats: seats, dm: true, hint: "[#{config['cmd_push']}/숫자]")]
      end

      private

      def laps
        config['laps'].to_i.clamp(1, 15)
      end

      def wins_needed
        config['wins_needed'].to_i.clamp(1, laps)
      end

      def board
        players.map { |player| "#{player.name} #{state['stamina'][player.seat.to_s]}" }.join(' · ')
      end

      def ask_all!
        players.each do |player|
          dm(player, render(config['msg_ask'], lap: session.turn, push: config['cmd_push'], left: state['stamina'][player.seat.to_s], board: board))
        end
        wait_for_turn!
      end

      def resolve!
        a, b = players
        amount_a = state['choices'][a.seat.to_s].to_i
        amount_b = state['choices'][b.seat.to_s].to_i
        state['stamina'][a.seat.to_s] -= amount_a
        state['stamina'][b.seat.to_s] -= amount_b
        winner = if amount_a > amount_b then a
                 elsif amount_b > amount_a then b
                 end
        state['wins'][winner.seat.to_s] += 1 if winner
        state['laps'] << { 'lap' => session.turn, 'amounts' => { a.seat.to_s => amount_a, b.seat.to_s => amount_b }, 'winner_seat' => winner&.seat }
        state['choices'] = {}

        outcome = winner ? render(config['msg_lap_win'], winner: winner) : render(config['msg_lap_tie'])
        score = players.map { |player| "#{player.name} #{state['wins'][player.seat.to_s]}" }.join(' · ')
        text = render(config['msg_lap'], lap: session.turn, player_a: a, player_b: b, amount_a: amount_a, amount_b: amount_b, outcome: outcome, score: score, board: board)

        champion = players.find { |player| state['wins'][player.seat.to_s] >= wins_needed }
        if champion
          finish!(winner: champion, message: "#{text}\n\n#{render(config['msg_win'], winner: champion, wins: wins_needed)}")
        elsif session.turn >= laps
          wins_a = state['wins'][a.seat.to_s]
          wins_b = state['wins'][b.seat.to_s]
          if wins_a == wins_b
            finish!(draw: true, message: "#{text}\n\n#{render(config['msg_draw'], laps: laps)}")
          else
            leader = wins_a > wins_b ? a : b
            finish!(winner: leader, message: "#{text}\n\n#{render(config['msg_end'], laps: laps, winner: leader)}")
          end
        else
          post(text)
          session.update!(turn: session.turn + 1)
          ask_all!
        end
      end
    end
  end
end
