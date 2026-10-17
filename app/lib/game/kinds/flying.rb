# frozen_string_literal: true

module Game
  module Kinds
    # 비행 대결 (여럿이, 2~6명, 예전 '비행' 수업): 라운드마다 참가자보다 조금 적은 경로 중 하나를 DM 으로 고른다.
    # 같은 경로를 고른 사람끼리 충돌(실패), 혼자 고른 사람은 통과. 정한 라운드가 끝나면 통과 횟수가 가장 많은 사람이 승리
    # (가장 많은 사람이 여럿이면 그 사람들이 함께 승리, 모두 같으면 무승부).
    class Flying < Base
      KEY = 'flying'

      FIELDS = (base_fields(name: '비행 대결', command: '비행대결', points_win: 15, points_draw: 5) + [
        F.new(key: 'min_players', type: :integer, default: 2, group: 'rules', label: '최소 인원', hint: '신청자를 포함한 전체 인원 (2~10명)'),
        F.new(key: 'max_players', type: :integer, default: 6, group: 'rules', label: '최대 인원', hint: '신청자를 포함한 전체 인원 (최대 10명)'),
        F.new(key: 'rounds', type: :integer, default: 3, group: 'rules', label: '라운드 수'),
        F.new(key: 'routes', type: :lines, group: 'flavors', label: '경로 (줄마다 하나)',
              default: ['천문탑 우회', '검은 호수 위 저공비행', '금지된 숲 가장자리', '퀴디치 경기장 상공', '온실 지붕 위', '부엉이장 옆 바람길', '시계탑 사이', '해그리드 오두막 위']),
        F.new(key: 'cmd_fly', type: :string, default: '비행', group: 'commands', label: '경로 고르기 명령어', hint: '[비행/번호] 또는 [비행/경로 이름]'),
        F.new(key: 'msg_players', type: :text, group: 'messages', label: '인원이 모자람', default: '%{game}은 신청자를 포함해 %{min}~%{max}명이 필요합니다. 상대를 더 태그해 주세요.'),
        F.new(key: 'msg_start', type: :text, group: 'messages', label: '시작', default: "%{game} 시작! %{rounds}라운드 동안 겹치지 않는 경로를 골라 비행합니다."),
        F.new(key: 'msg_round', type: :text, group: 'messages', label: '라운드 시작',
              default: "%{round}라운드 경로\n%{routes}\n\n시스템 계정에게 DM으로 [%{fly}/번호]를 보내 주세요.\n다른 사람과 경로가 겹치면 공중에서 충돌합니다."),
        F.new(key: 'msg_ask', type: :text, group: 'messages', label: 'DM: 경로 고르기', default: "%{round}라운드 경로\n%{routes}\n\n[%{fly}/번호]로 답해 주세요."),
        F.new(key: 'msg_chosen', type: :text, group: 'messages', label: 'DM: 선택 확인', default: "%{route} 경로로 비행합니다."),
        F.new(key: 'msg_bad_route', type: :text, group: 'messages', label: 'DM: 없는 경로', default: '그런 경로는 없습니다. [%{fly}/번호]로 골라 주세요.'),
        F.new(key: 'msg_result', type: :text, group: 'messages', label: '라운드 결과', default: "%{round}라운드 결과\n\n%{lines}"),
        F.new(key: 'msg_success', type: :text, group: 'messages', label: '통과', default: "%{route}: %{player} 통과"),
        F.new(key: 'msg_crash', type: :text, group: 'messages', label: '충돌', default: "%{route}: %{players} 충돌"),
        F.new(key: 'msg_idle', type: :text, group: 'messages', label: '시간 초과', default: "%{players}: 경로를 고르지 않아 출발하지 못했습니다."),
        F.new(key: 'msg_winner', type: :text, group: 'messages', label: '승리', default: "%{winner}의 승리!"),
        F.new(key: 'msg_draw', type: :text, group: 'messages', label: '무승부', default: '모두 같은 횟수로 무승부입니다.'),
      ]).freeze

      class << self
        def continues_on_timeout?
          true
        end

        # 신청자를 포함한 인원 범위 (개인전)
        def max_total
          config['max_players'].to_i.clamp(2, 10)
        end

        def min_total
          config['min_players'].to_i.clamp(2, max_total)
        end

        def max_opponents
          max_total - 1
        end

        def min_opponents
          min_total - 1
        end

        def invite_error(total)
          return if total >= min_total

          Game::Text.render(config['msg_players'], game: display_name, min: min_total, max: max_total)
        end
      end

      def start!
        state.merge!('round' => 1, 'wins' => players.to_h { |player| [player.seat.to_s, 0] }, 'choices' => {})
        session.update!(turn: 1)
        post(render(config['msg_start'], rounds: rounds))
        new_round!
      end

      def handle(player, command, args, status)
        return false unless command == config['cmd_fly']
        return true unless require_dm!(player, status)

        route = pick(args.first)
        if route.nil?
          dm(player, render(config['msg_bad_route'], fly: config['cmd_fly']))
          return true
        end

        state['choices'][player.seat.to_s] = route
        session.save!
        dm(player, render(config['msg_chosen'], route: route))
        resolve! if state['choices'].size == players.size
        true
      end

      def timeout!
        resolve!
      end

      # 카드: 사람마다 통과 횟수, 라운드, 이번 라운드 경로, 고른 사람
      def max_turns
        config['rounds'].to_i.clamp(1, 20)
      end

      def card_data
        {
          'scores' => state['wins'] || {},
          'round' => state['round'],
          'rounds' => rounds,
          'routes' => state['routes'] || [],
          'chosen' => (state['choices'] || {}).keys,
          'last_round' => state['last_round'],
          'history' => state['history'] || [],
        }
      end

      # 버튼: 경로마다 DM 으로 [비행/번호]
      def card_actions
        seats = pending_seats
        return [] if seats.empty?

        Array(state['routes']).each_with_index.map do |route, index|
          Game::Card.action("#{config['cmd_fly']}/#{index + 1}", seats: seats, label: route, dm: true)
        end
      end

      private

      def rounds
        config['rounds'].to_i.clamp(1, 10)
      end

      # 참가자보다 하나 적은 경로 (최소 2개)
      def new_round!
        all = config['routes'].presence || %w(왼쪽 가운데 오른쪽)
        state['routes'] = all.sample([[players.size - 1, 2].max, all.size].min)
        state['choices'] = {}
        listed = state['routes'].each_with_index.map { |route, index| "#{index + 1}. #{route}" }.join("\n")
        post(render(config['msg_round'], round: state['round'], routes: listed, fly: config['cmd_fly']))
        players.each { |player| dm(player, render(config['msg_ask'], round: state['round'], routes: listed, fly: config['cmd_fly'])) }
        wait_for_turn!
      end

      def pick(value)
        index = Integer(value.to_s, exception: false)
        return state['routes'][index - 1] if index&.between?(1, state['routes'].size)

        state['routes'].find { |route| route.delete(' ') == value.to_s.delete(' ') }
      end

      def resolve!
        by_route = players.group_by { |player| state['choices'][player.seat.to_s] }
        lines = []
        outcome = {}
        by_route.each do |route, group|
          if route.nil?
            group.each { |player| outcome[player.seat.to_s] = 'idle' }
            lines << render(config['msg_idle'], players: group.map(&:name).join(', '))
          elsif group.size == 1
            seat = group.first.seat.to_s
            state['wins'][seat] = state['wins'][seat].to_i + 1
            outcome[seat] = 'pass'
            lines << render(config['msg_success'], route: route, player: group.first)
          else
            group.each { |player| outcome[player.seat.to_s] = 'crash' }
            lines << render(config['msg_crash'], route: route, players: group.map(&:name).join('·'))
          end
        end
        state['last_round'] = { 'choices' => state['choices'].dup }
        # 라운드마다 통과·충돌·미선택 기록: 웹 방 맨 위 레인 그림 (선택한 경로는 담지 않는다)
        state['history'] = Array(state['history']) + [{ 'round' => state['round'], 'results' => outcome }]
        result = render(config['msg_result'], round: state['round'], lines: lines.join("\n"))

        if state['round'] >= rounds
          finish_race!(result)
        else
          post(result)
          state['round'] += 1
          session.update!(turn: session.turn + 1)
          new_round!
        end
      end

      def finish_race!(result)
        wins = players.to_h { |player| [player, state['wins'][player.seat.to_s].to_i] }
        best = wins.values.max
        top = wins.select { |_, count| count == best }.keys
        if top.size == players.size
          finish!(draw: true, message: "#{result}\n\n#{render(config['msg_draw'])}")
        else
          finish!(winners: top, message: "#{result}\n\n#{render(config['msg_winner'], winner: top.map(&:name).join(', '))}")
        end
      end
    end
  end
end
