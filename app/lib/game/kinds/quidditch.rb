# frozen_string_literal: true

module Game
  module Kinds
    # 퀴디치: 1:1 또는 팀전 (2·4·6명). 매 턴 DM 으로 행동을 고르고 동시에 공개.
    #   팀: 신청자 + 앞에 태그한 사람들이 한 팀, 나머지 절반이 상대 팀 (예: @론 @드레이코 @고일 → 신청자·론 vs 드레이코·고일)
    #   추격: 쿼플 득점 시도 (성공하면 팀 +10)
    #   몰이: 블러저로 상대 팀 한 명의 이번 턴 행동을 막을 확률
    #   수색: 스니치 찾기 (처음 확률에서 수색할 때마다 올라감, 사람마다). 잡으면 팀 +150 하고 경기 끝
    # 스니치를 잡거나 최대 턴이 지나면 점수가 높은 팀 승리 (그 팀 모두 승리).
    class Quidditch < Base
      KEY = 'quidditch'

      ACTIONS = %w(chase beat seek).freeze
      TEAMS = %w(A B).freeze

      FIELDS = (base_fields(name: '퀴디치', command: '퀴디치', points_win: 15, points_draw: 5) + [
        F.new(key: 'cmd_chase', type: :string, default: '추격', group: 'commands', label: '추격 명령어'),
        F.new(key: 'cmd_beat', type: :string, default: '몰이', group: 'commands', label: '몰이 명령어'),
        F.new(key: 'cmd_seek', type: :string, default: '수색', group: 'commands', label: '수색 명령어'),
        F.new(key: 'min_players', type: :integer, default: 4, group: 'rules', label: '최소 인원',
              hint: '신청자를 포함한 전체 인원. 팀 대결이라 1:1은 할 수 없고, 양 팀 인원이 같아야 하므로 짝수로 맞춰집니다 (최소 4명).'),
        F.new(key: 'max_players', type: :integer, default: 6, group: 'rules', label: '최대 인원',
              hint: '신청자를 포함한 전체 인원 (짝수로 맞춰집니다, 최대 12명).'),
        F.new(key: 'team_a_name', type: :string, default: '신청 팀', group: 'rules', label: '신청자 팀 이름'),
        F.new(key: 'team_b_name', type: :string, default: '상대 팀', group: 'rules', label: '상대 팀 이름'),
        F.new(key: 'max_turns', type: :integer, default: 15, group: 'rules', label: '최대 턴'),
        F.new(key: 'chase_rate', type: :integer, default: 50, group: 'rules', label: '쿼플 득점 확률 (%)'),
        F.new(key: 'chase_score', type: :integer, default: 10, group: 'rules', label: '쿼플 점수'),
        F.new(key: 'beat_rate', type: :integer, default: 50, group: 'rules', label: '블러저로 막을 확률 (%)'),
        F.new(key: 'seek_start', type: :integer, default: 10, group: 'rules', label: '스니치 처음 확률 (%)'),
        F.new(key: 'seek_step', type: :integer, default: 5, group: 'rules', label: '수색할 때마다 오르는 확률 (%)'),
        F.new(key: 'snitch_score', type: :integer, default: 150, group: 'rules', label: '스니치 점수'),
        F.new(key: 'msg_start', type: :text, group: 'messages', label: '시작',
              default: "%{game} 시작! 최대 %{turns}턴.\n%{teams}\n\n매 턴 시스템 계정이 보내는 DM에 [%{chase}] [%{beat}] [%{seek}] 중 하나로 답해 주세요.\n모든 인원이 행동을 고르면 결과가 공개됩니다."),
        F.new(key: 'msg_uneven', type: :text, group: 'messages', label: '팀 인원이 맞지 않음',
              default: '%{game}은 팀 대결입니다. 신청자를 포함해 %{min}~%{max}명, 양 팀 인원이 같도록 팀원과 상대 팀을 태그해 주세요.'),
        F.new(key: 'msg_ask', type: :text, group: 'messages', label: 'DM: 행동 고르기',
              default: "%{turn}턴 | 행동을 골라 주세요.\n[%{chase}] 쿼플 득점 · [%{beat}] 블러저로 방해 · [%{seek}] 스니치 찾기 (현재 확률 %{seek_rate}%)"),
        F.new(key: 'msg_chosen', type: :text, group: 'messages', label: 'DM: 선택 확인', default: "행동을 정했습니다. 다른 사람을 기다립니다."),
        F.new(key: 'msg_goal', type: :text, group: 'messages', label: '쿼플 골', default: '%{player}{이가} 쿼플을 골대에 꽂았다! +%{score}'),
        F.new(key: 'msg_no_goal', type: :text, group: 'messages', label: '쿼플 실패', default: '%{player}의 쿼플이 파수꾼에게 막혔다.'),
        F.new(key: 'msg_beat_hit', type: :text, group: 'messages', label: '블러저 명중', default: '%{player}의 블러저가 %{target}{을를} 덮쳤다! %{target}의 행동 무효'),
        F.new(key: 'msg_beat_miss', type: :text, group: 'messages', label: '블러저 빗나감', default: '%{player}의 블러저가 허공을 갈랐다.'),
        F.new(key: 'msg_seek_fail', type: :text, group: 'messages', label: '스니치 놓침', default: '%{player}{이가} 금빛을 쫓았지만 놓쳤다.'),
        F.new(key: 'msg_snitch', type: :text, group: 'messages', label: '스니치', default: "%{player}{이가} 골든 스니치를 잡았다! +%{score}"),
        F.new(key: 'msg_blocked', type: :text, group: 'messages', label: '행동 무효', default: '%{player}{은는} 블러저를 피하느라 아무것도 하지 못했다.'),
        F.new(key: 'msg_idle', type: :text, group: 'messages', label: '시간 초과', default: '%{player}{은는} 빗자루 위에서 멍하니 있었다.'),
        F.new(key: 'msg_turn', type: :text, group: 'messages', label: '턴 결과', default: "%{turn}턴\n\n%{lines}"),
        F.new(key: 'msg_end', type: :text, group: 'messages', label: '경기 끝', default: "경기가 종료되었습니다.\n%{outcome}"),
        F.new(key: 'msg_winner', type: :text, group: 'messages', label: '승리', default: '%{winner}의 승리!'),
        F.new(key: 'msg_draw', type: :text, group: 'messages', label: '무승부', default: "동점으로 무승부입니다."),
      ]).freeze

      class << self
        def continues_on_timeout?
          true
        end

        # 신청자를 포함한 인원 범위: 팀 대결이라 짝수, 1:1 불가 (최소 4명, 최대 12명)
        def min_total
          value = [config['min_players'].to_i, 4].max
          value.odd? ? value + 1 : value
        end

        def max_total
          value = config['max_players'].to_i.clamp(min_total, 12)
          value.odd? ? value - 1 : value
        end

        def max_opponents
          max_total - 1
        end

        def min_opponents
          min_total - 1
        end

        def team_game?
          true
        end

        def invite_error(total)
          return if total.even? && total.between?(min_total, max_total)

          Game::Text.render(config['msg_uneven'], game: display_name, min: min_total, max: max_total)
        end
      end

      def start!
        half = players.size / 2
        teams = players.each_with_index.to_h { |player, index| [player.seat.to_s, index < [half, 1].max ? 'A' : 'B'] }
        state.merge!('teams' => teams, 'scores' => TEAMS.index_with(0), 'seek' => seats_to(config['seek_start'].to_i), 'choices' => {})
        session.update!(turn: 1)
        post(render(config['msg_start'], turns: max_turns, teams: team_lines, **commands))
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

      # 최대 턴 (방 맨 위 '1턴 / 15턴')
      def max_turns
        config['max_turns'].to_i.clamp(1, 50)
      end

      # 카드: 사람마다 자기 팀 점수 (scores), 팀 구성 (teams, team_names)
      def card_data
        {
          'scores' => players.to_h { |player| [player.seat.to_s, team_score(player)] },
          'teams' => team? ? state['teams'] : nil,
          'team_names' => team? ? team_names : nil,
          'team_scores' => team? ? TEAMS.index_with { |team| state.dig('scores', team).to_i } : nil,
          'seek' => state['seek'] || {},
          'max_turns' => max_turns,
          'chosen' => (state['choices'] || {}).keys,
          'last_round' => state['last_round'],
          'history' => state['history'] || [],
          # 자리별 팀 키 (1:1 도 A/B): 턴 트랙의 득점 색을 맞추는 데 쓴다
          'sides' => players.to_h { |player| [player.seat.to_s, team_of(player)] },
        }.compact
      end

      def card_actions
        seats = pending_seats
        return [] if seats.empty?

        ACTIONS.map { |key| Game::Card.action(config["cmd_#{key}"], seats: seats, dm: true) }
      end

      private

      def commands
        ACTIONS.to_h { |key| [key.to_sym, config["cmd_#{key}"]] }
      end

      def seats_to(value)
        players.to_h { |player| [player.seat.to_s, value] }
      end

      # 기권하면 상대 팀이 이긴다 (1:1 이면 상대)
      def forfeit_winners(player)
        team? ? players.reject { |other| team_of(other) == team_of(player) } : super
      end

      # 팀전인가 (3명 이상)
      def team?
        players.size > 2
      end

      def team_names
        { 'A' => config['team_a_name'], 'B' => config['team_b_name'] }
      end

      # 팀 키 (예전 1:1 판은 teams 가 없어 자리 번호가 곧 팀)
      def team_of(player)
        state.dig('teams', player.seat.to_s) || player.seat.to_s
      end

      def team_keys
        players.map { |player| team_of(player) }.uniq
      end

      def team_score(player)
        state.dig('scores', team_of(player)).to_i
      end

      def members(team)
        players.select { |player| team_of(player) == team }
      end

      # 팀 이름 (1:1 이면 사람 이름)
      def team_label(team)
        return members(team).first&.name.to_s unless team?

        "#{team_names[team]}(#{members(team).map(&:name).join('·')})"
      end

      def team_lines
        return '' unless team?

        team_keys.map { |team| team_label(team) }.join(' vs ')
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
        gained = Hash.new(0)

        # 몰이 먼저: 상대 팀 한 명의 행동을 막을 수 있다
        players.each do |player|
          next unless choices[player.seat.to_s] == 'beat'

          target = players.reject { |other| team_of(other) == team_of(player) }.sample
          next if target.nil?

          if chance?(config['beat_rate'])
            blocked << target.seat.to_s
            lines << render(config['msg_beat_hit'], player: player, target: target)
          else
            lines << render(config['msg_beat_miss'], player: player)
          end
        end

        caught = []
        players.each do |player|
          seat = player.seat.to_s
          team = team_of(player)
          action = choices[seat]
          if action.nil?
            lines << render(config['msg_idle'], player: player)
          elsif blocked.include?(seat)
            lines << render(config['msg_blocked'], player: player)
          elsif action == 'chase'
            if chance?(config['chase_rate'])
              state['scores'][team] = state['scores'][team].to_i + config['chase_score'].to_i
              gained[team] += config['chase_score'].to_i
              lines << render(config['msg_goal'], player: player, score: config['chase_score'])
            else
              lines << render(config['msg_no_goal'], player: player)
            end
          elsif action == 'seek'
            if chance?(state['seek'][seat])
              state['scores'][team] = state['scores'][team].to_i + config['snitch_score'].to_i
              gained[team] += config['snitch_score'].to_i
              caught << player
              lines << render(config['msg_snitch'], player: player, score: config['snitch_score'])
            else
              state['seek'][seat] += config['seek_step'].to_i
              lines << render(config['msg_seek_fail'], player: player)
            end
          end
        end

        board = team_keys.map { |team| "#{team_label(team)} #{state['scores'][team].to_i}" }.join(' : ')
        turn_text = render(config['msg_turn'], turn: session.turn, lines: lines.join("\n"), board: board)
        state['last_round'] = { 'choices' => choices.transform_values { |action| config["cmd_#{action}"] }, 'blocked' => blocked, 'caught' => caught.map(&:seat) }
        # 턴마다 팀이 얻은 점수: 웹 방 맨 위 턴 트랙의 색 (고른 행동은 담지 않는다)
        state['history'] = Array(state['history']) + [{ 'turn' => session.turn, 'gained' => gained.to_h }]
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
        scores = team_keys.to_h { |team| [team, state['scores'][team].to_i] }
        if scores.values.uniq.size == 1
          finish!(draw: true, message: "#{turn_text}\n\n#{render(config['msg_end'], outcome: render(config['msg_draw']))}")
        else
          top = scores.max_by { |_, score| score }.first
          winners = members(top)
          winner_name = team? ? team_label(top) : winners.first
          finish!(winners: winners, message: "#{turn_text}\n\n#{render(config['msg_end'], outcome: render(config['msg_winner'], winner: winner_name))}")
        end
      end
    end
  end
end
