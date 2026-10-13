# frozen_string_literal: true

module Game
  module Kinds
    # 미니 퀴디치: 매 턴 DM 으로 행동을 고르고 동시에 공개.
    #   추격: 쿼플 득점 시도 (성공하면 +10)
    #   몰이: 블러저로 상대의 이번 턴 행동을 막을 확률
    #   수색: 스니치 찾기 (처음 확률에서 수색할 때마다 올라감). 잡으면 +150 하고 경기 끝
    # 스니치를 잡거나 최대 턴이 지나면 점수가 높은 쪽 승리.
    class Quidditch < Base
      KEY = 'quidditch'

      ACTIONS = %w(chase beat seek).freeze

      FIELDS = (base_fields(name: '미니 퀴디치', command: '퀴디치', points_win: 15, points_draw: 5) + [
        F.new(key: 'cmd_chase', type: :string, default: '추격', group: 'commands', label: '추격 명령어'),
        F.new(key: 'cmd_beat', type: :string, default: '몰이', group: 'commands', label: '몰이 명령어'),
        F.new(key: 'cmd_seek', type: :string, default: '수색', group: 'commands', label: '수색 명령어'),
        F.new(key: 'max_turns', type: :integer, default: 15, group: 'rules', label: '최대 턴'),
        F.new(key: 'chase_rate', type: :integer, default: 50, group: 'rules', label: '쿼플 득점 확률 (%)'),
        F.new(key: 'chase_score', type: :integer, default: 10, group: 'rules', label: '쿼플 점수'),
        F.new(key: 'beat_rate', type: :integer, default: 50, group: 'rules', label: '블러저로 막을 확률 (%)'),
        F.new(key: 'seek_start', type: :integer, default: 10, group: 'rules', label: '스니치 처음 확률 (%)'),
        F.new(key: 'seek_step', type: :integer, default: 5, group: 'rules', label: '수색할 때마다 오르는 확률 (%)'),
        F.new(key: 'snitch_score', type: :integer, default: 150, group: 'rules', label: '스니치 점수'),
        F.new(key: 'msg_start', type: :text, group: 'messages', label: '시작',
              default: "🧹 %{game} 시작! 최대 %{turns}턴.\n\n매 턴 시스템 계정이 보내는 DM에 [%{chase}] [%{beat}] [%{seek}] 중 하나로 답해 주세요. 둘 다 고르면 여기서 결과를 발표합니다."),
        F.new(key: 'msg_ask', type: :text, group: 'messages', label: 'DM: 행동 고르기',
              default: "%{turn}턴 — 행동을 골라 주세요.\n[%{chase}] 쿼플 득점 · [%{beat}] 블러저로 방해 · [%{seek}] 스니치 찾기 (지금 %{seek_rate}%)"),
        F.new(key: 'msg_chosen', type: :text, group: 'messages', label: 'DM: 선택 확인', default: '✔ 행동을 정했습니다. 상대를 기다립니다.'),
        F.new(key: 'msg_goal', type: :text, group: 'messages', label: '쿼플 골', default: '%{player}{이가} 쿼플을 골대에 꽂았다! +%{score}'),
        F.new(key: 'msg_no_goal', type: :text, group: 'messages', label: '쿼플 실패', default: '%{player}의 쿼플이 파수꾼에게 막혔다.'),
        F.new(key: 'msg_beat_hit', type: :text, group: 'messages', label: '블러저 명중', default: '%{player}의 블러저가 %{target}{을를} 덮쳤다! %{target}의 행동 무효'),
        F.new(key: 'msg_beat_miss', type: :text, group: 'messages', label: '블러저 빗나감', default: '%{player}의 블러저가 허공을 갈랐다.'),
        F.new(key: 'msg_seek_fail', type: :text, group: 'messages', label: '스니치 놓침', default: '%{player}{이가} 금빛을 쫓았지만 놓쳤다.'),
        F.new(key: 'msg_snitch', type: :text, group: 'messages', label: '스니치', default: '✨ %{player}{이가} 골든 스니치를 잡았다! +%{score}'),
        F.new(key: 'msg_blocked', type: :text, group: 'messages', label: '행동 무효', default: '%{player}{은는} 블러저를 피하느라 아무것도 하지 못했다.'),
        F.new(key: 'msg_idle', type: :text, group: 'messages', label: '시간 초과', default: '%{player}{은는} 빗자루 위에서 멍하니 있었다.'),
        F.new(key: 'msg_turn', type: :text, group: 'messages', label: '턴 결과', default: "%{turn}턴\n\n%{lines}\n\n%{board}"),
        F.new(key: 'msg_end', type: :text, group: 'messages', label: '경기 끝', default: '경기 종료! %{outcome}'),
        F.new(key: 'msg_winner', type: :text, group: 'messages', label: '승리', default: '%{winner}의 승리!'),
        F.new(key: 'msg_draw', type: :text, group: 'messages', label: '무승부', default: '동점, 무승부입니다.'),
      ]).freeze

      def self.continues_on_timeout?
        true
      end

      def start!
        state.merge!('scores' => seats_to(0), 'seek' => seats_to(config['seek_start'].to_i), 'choices' => {})
        session.update!(turn: 1)
        post(render(config['msg_start'], turns: max_turns, **commands))
        ask_all!
      end

      def handle(player, command, _args, status)
        action = ACTIONS.find { |key| config["cmd_#{key}"] == command }
        return false if action.nil?
        return true unless require_dm!(player, status)

        state['choices'][player.seat.to_s] = action
        session.save!
        dm(player, render(config['msg_chosen']))
        resolve! if state['choices'].size == players.size
        true
      end

      def timeout!
        resolve!
      end

      private

      def max_turns
        config['max_turns'].to_i.clamp(1, 50)
      end

      def commands
        ACTIONS.to_h { |key| [key.to_sym, config["cmd_#{key}"]] }
      end

      def seats_to(value)
        players.to_h { |player| [player.seat.to_s, value] }
      end

      def ask_all!
        players.each do |player|
          dm(player, render(config['msg_ask'], turn: session.turn, seek_rate: state['seek'][player.seat.to_s], **commands))
        end
        wait_for_turn!
      end

      def chance?(percent)
        rand(100) < percent.to_i
      end

      def resolve!
        choices = state['choices']
        lines = []
        blocked = []

        # 몰이 먼저: 상대 행동을 막을 수 있다
        players.each do |player|
          next unless choices[player.seat.to_s] == 'beat'

          target = session.opponent_of(player)
          if chance?(config['beat_rate'])
            blocked << target.seat.to_s
            lines << render(config['msg_beat_hit'], player: player.name, target: target.name)
          else
            lines << render(config['msg_beat_miss'], player: player.name)
          end
        end

        caught = []
        players.each do |player|
          seat = player.seat.to_s
          action = choices[seat]
          if action.nil?
            lines << render(config['msg_idle'], player: player.name)
          elsif blocked.include?(seat)
            lines << render(config['msg_blocked'], player: player.name)
          elsif action == 'chase'
            if chance?(config['chase_rate'])
              state['scores'][seat] += config['chase_score'].to_i
              lines << render(config['msg_goal'], player: player.name, score: config['chase_score'])
            else
              lines << render(config['msg_no_goal'], player: player.name)
            end
          elsif action == 'seek'
            if chance?(state['seek'][seat])
              state['scores'][seat] += config['snitch_score'].to_i
              caught << player
              lines << render(config['msg_snitch'], player: player.name, score: config['snitch_score'])
            else
              state['seek'][seat] += config['seek_step'].to_i
              lines << render(config['msg_seek_fail'], player: player.name)
            end
          end
        end

        board = players.map { |player| "#{player.name} #{state['scores'][player.seat.to_s]}" }.join(' : ')
        turn_text = render(config['msg_turn'], turn: session.turn, lines: lines.join("\n"), board: board)
        state['choices'] = {}

        if caught.any? || session.turn >= max_turns
          finish_by_score!(turn_text)
        else
          post(turn_text)
          session.update!(turn: session.turn + 1)
          ask_all!
        end
      end

      def finish_by_score!(turn_text)
        scores = players.map { |player| state['scores'][player.seat.to_s] }
        if scores.uniq.size == 1
          finish!(draw: true, message: "#{turn_text}\n\n#{render(config['msg_end'], outcome: render(config['msg_draw']))}")
        else
          winner = players.max_by { |player| state['scores'][player.seat.to_s] }
          finish!(winner: winner, message: "#{turn_text}\n\n#{render(config['msg_end'], outcome: render(config['msg_winner'], winner: winner.name))}")
        end
      end
    end
  end
end
