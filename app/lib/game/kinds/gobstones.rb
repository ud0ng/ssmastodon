# frozen_string_literal: true

module Game
  module Kinds
    # 곱스톤: 번갈아 강도를 골라 상대 구슬을 맞힌다. 정해진 라운드 뒤 총점이 높은 쪽 승리.
    class Gobstones < Base
      KEY = 'gobstones'

      STRENGTHS = %w(weak mid strong).freeze

      FIELDS = (base_fields(name: '곱스톤', command: '곱스톤', points_win: 5, points_draw: 2) + [
        F.new(key: 'rounds', type: :integer, default: 5, group: 'rules', label: '라운드 수', hint: '한 사람이 던지는 횟수'),
        F.new(key: 'cmd_weak', type: :string, default: '약', group: 'commands', label: '약하게'),
        F.new(key: 'cmd_mid', type: :string, default: '중', group: 'commands', label: '중간'),
        F.new(key: 'cmd_strong', type: :string, default: '강', group: 'commands', label: '세게'),
        F.new(key: 'hit_weak', type: :integer, default: 70, group: 'rules', label: '약 명중률 (%)'),
        F.new(key: 'hit_mid', type: :integer, default: 45, group: 'rules', label: '중 명중률 (%)'),
        F.new(key: 'hit_strong', type: :integer, default: 25, group: 'rules', label: '강 명중률 (%)'),
        F.new(key: 'score_weak', type: :integer, default: 1, group: 'rules', label: '약 명중 점수'),
        F.new(key: 'score_mid', type: :integer, default: 2, group: 'rules', label: '중 명중 점수'),
        F.new(key: 'score_strong', type: :integer, default: 3, group: 'rules', label: '강 명중 점수'),
        F.new(key: 'miss_strong', type: :integer, default: -1, group: 'rules', label: '강 빗나감 점수', hint: '냄새나는 액체를 뒤집어씀'),
        F.new(key: 'msg_start', type: :text, group: 'messages', label: '시작',
              default: "%{game} 시작!\n한 사람당 %{rounds}번씩 던집니다.\n[%{weak}] [%{mid}] [%{strong}] 중 하나로 답해 주세요."),
        F.new(key: 'msg_hit', type: :text, group: 'messages', label: '명중', default: "%{player}{이가} [%{strength}]으로 튕겼다.\n명중! +%{score}점"),
        F.new(key: 'msg_miss', type: :text, group: 'messages', label: '빗나감', default: "%{player}{이가} [%{strength}]으로 튕겼다.\n빗나갔다!"),
        F.new(key: 'msg_splash', type: :text, group: 'messages', label: '강 빗나감',
              default: "%{player}{이가} [%{strength}]으로 튕겼다.\n구슬이 튀어 냄새나는 액체를 뒤집어썼다! %{score}점"),
        F.new(key: 'msg_timeout_throw', type: :text, group: 'messages', label: '시간 초과', default: "%{player}{은는} 시간 안에 던지지 못했다."),
        F.new(key: 'msg_turn', type: :text, group: 'messages', label: '턴 결과',
              default: "%{round}라운드\n\n%{result}"),
        F.new(key: 'msg_end', type: :text, group: 'messages', label: '끝',
              default: "%{round}라운드\n\n%{result}\n\n%{outcome}"),
        F.new(key: 'msg_winner', type: :text, group: 'messages', label: '승리', default: '%{winner}의 승리!'),
        F.new(key: 'msg_draw', type: :text, group: 'messages', label: '무승부', default: "동점으로 무승부입니다."),
        F.new(key: 'msg_not_turn', type: :text, group: 'messages', label: '차례 아님', default: '지금은 %{player}의 차례입니다.'),
      ]).freeze

      def self.continues_on_timeout?
        true
      end

      def start!
        state.merge!('seat' => players.map(&:seat).sample, 'throws' => 0, 'scores' => players.to_h { |player| [player.seat.to_s, 0] })
        state['first_seat'] = state['seat']
        session.update!(turn: 1)
        post(render(config['msg_start'], rounds: rounds, player: current, **command_names))
        wait_for_turn!
      end

      def handle(player, command, _args, _status)
        strength = STRENGTHS.find { |key| config["cmd_#{key}"] == command }
        return false if strength.nil?

        if player.seat != state['seat']
          post(render(config['msg_not_turn'], player: current))
          return true
        end

        throw!(player, strength)
        true
      end

      def max_turns
        rounds
      end

      def card_data
        {
          'scores' => state['scores'] || {},
          'rounds' => rounds,
          'throws' => state['throws'].to_i,
          'current_seat' => state['seat'],
          'last_throw' => state['last_throw'],
        }
      end

      def card_actions
        return [] if state['seat'].nil?

        STRENGTHS.map { |key| Game::Card.action(config["cmd_#{key}"], seats: [state['seat']]) }
      end

      # 시간 초과는 그 차례 0점으로 넘어간다
      def timeout!
        state['last_throw'] = { 'seat' => current.seat, 'strength' => nil, 'score' => 0, 'hit' => false }
        advance!(current, render(config['msg_timeout_throw'], player: current))
      end

      # 웹 기록판: 던질 때마다 고른 강도와 명중 여부, 그 뒤 점수
      def board_for(player)
        mine = player&.seat&.to_s
        columns = players.to_h do |each|
          seat = each.seat.to_s
          total = 0
          throws = Array(state['log']).select { |entry| entry['seat'].to_s == seat }
          rows = throws.map do |entry|
            score = entry['score'].to_i
            total += score
            result = if entry['hit'] then ["명중 +#{score}", 'good']
                     elsif score.negative? then [score.to_s, 'bad']
                     else %w(빗나감 zero)
                     end
            { round: entry['round'], cells: [[entry['strength'] || '시간 초과', entry['hit'] ? 'good' : nil]], chips: [result, ["#{total}점", 'note']] }
          end
          pending = if session.status == 'active' && state['seat'].to_s == seat
                      seat == mine ? '던질 차례' : '던지는 중…'
                    end
          [seat, { rows: rows, pending: pending, summary: { label: '점수', value: state.dig('scores', seat).to_i.to_s, note: "#{throws.size} / #{rounds}번 던짐", win: each.result == 'win' } }]
        end
        legend = STRENGTHS.map { |key| [config["cmd_#{key}"], "#{config["hit_#{key}"]}% · +#{config["score_#{key}"]}"] }
        { legend: legend, columns: columns, key: "#{config['cmd_strong']}으로 던져 빗나가면 #{config['miss_strong']}점" }
      end

      private

      def rounds
        config['rounds'].to_i.clamp(1, 20)
      end

      def command_names
        STRENGTHS.to_h { |key| [key.to_sym, config["cmd_#{key}"]] }
      end

      def current
        players.find { |player| player.seat == state['seat'] }
      end

      def throw!(player, strength)
        hit = rand(100) < config["hit_#{strength}"].to_i
        score = if hit
                  config["score_#{strength}"].to_i
                else
                  strength == 'strong' ? config['miss_strong'].to_i : 0
                end
        template = if hit
                     'msg_hit'
                   else
                     (score.negative? ? 'msg_splash' : 'msg_miss')
                   end
        state['scores'][player.seat.to_s] += score
        state['last_throw'] = { 'seat' => player.seat, 'strength' => config["cmd_#{strength}"], 'score' => score, 'hit' => hit }
        advance!(player, render(config[template], player: player, strength: config["cmd_#{strength}"], score: score))
      end

      def advance!(player, result)
        (state['log'] ||= []) << state['last_throw'].merge('round' => session.turn)
        state['throws'] += 1
        round = session.turn
        board = players.map { |each| "#{each.name} #{state['scores'][each.seat.to_s]}점" }.join(' · ')

        if state['throws'] >= rounds * players.size
          scores = players.map { |each| state['scores'][each.seat.to_s] }
          if scores.uniq.size == 1
            finish!(draw: true, message: render(config['msg_end'], round: round, result: result, board: board, outcome: render(config['msg_draw'])))
          else
            winner = players.max_by { |each| state['scores'][each.seat.to_s] }
            finish!(winner: winner, message: render(config['msg_end'], round: round, result: result, board: board, outcome: render(config['msg_winner'], winner: winner)))
          end
          return
        end

        state['seat'] = session.opponent_of(player).seat
        # 두 사람이 한 번씩 던지면 다음 라운드
        session.turn += 1 if (state['throws'] % players.size).zero?
        post(render(config['msg_turn'], round: round, result: result, board: board, next: current))
        session.save!
        wait_for_turn!
      end
    end
  end
end
