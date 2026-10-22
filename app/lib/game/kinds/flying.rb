# frozen_string_literal: true

module Game
  module Kinds
    # 비행 대결 (이벤트, 웹 전용, 3~20명): 출발선에 선 토큰들이 라운드마다 앞길(참가자보다 적은 수) 중 하나를 고른다.
    # 혼자 고른 길만 무사히 통과하고, 같은 길을 고른 사람끼리는 부딪혀 내구도가 1 깎인다(길을 고르지 못한 사람도 1).
    # 내구도가 0이 되면 추락(탈락). 매 라운드 길 하나는 '금빛 고리'라서 혼자 통과하면 내구도 +1 (처음 값까지만).
    # 살아 있는 사람이 모두 한꺼번에 추락하게 되면 그 라운드는 무효로 하고 다시 고른다.
    # 살아 있는 사람이 2명 이하가 되면 끝: 남은 사람이 순위를 차지하고(내구도가 같으면 공동), 나머지는 추락한 라운드가 늦을수록 높은 순위.
    #
    #   state['alive'] 살아 있는 자리(문자열), state['out'] 자리 → 추락한 라운드, state['choices'] 이번 라운드 자리 → 길 번호(1부터)
    #   state['durability'] 처음 내구도, state['hp'] 자리 → 지금 내구도, state['ring'] 이번 라운드 금빛 고리 길 번호
    #   state['history'] 라운드마다 { round, lanes, routes, ring, alive_before, hp_before, hp_after, choices, results(자리 → pass/crash/idle), ring_gain, fell, void }
    #   끝나면 state['ranks'] (등수 묶음), state['mvp'] (가장 바보 같았던 장면)
    class Flying < Base
      KEY = 'flying'

      include Game::Events::Recruiting

      FIELDS = (base_fields(name: '비행 대결', command: '비행대결', points_win: 15, points_draw: 5) + [
        F.new(key: 'min_players', type: :integer, default: 3, group: 'rules', label: '최소 인원', hint: '3~10명'),
        F.new(key: 'max_players', type: :integer, default: 6, group: 'rules', label: '최대 인원', hint: '최대 20명'),
        F.new(key: 'round_seconds', type: :integer, default: 30, group: 'rules', label: '라운드 제한 시간 (초)', hint: '시간이 지나면 고르지 못한 사람은 떨어집니다 (5~300)'),
        F.new(key: 'durability', type: :integer, default: 2, group: 'rules', label: '내구도', hint: '처음 내구도 (1~9). 충돌하면 1 깎이고 0이 되면 추락합니다'),
        F.new(key: 'ring_route', type: :boolean, default: true, group: 'rules', label: '특수 경로 (금빛 고리)', hint: '매 라운드 길 하나가 금빛 고리가 됩니다. 혼자 통과하면 내구도 +1 (처음 값까지만)'),
        F.new(key: 'routes', type: :lines, group: 'flavors', label: '경로 이름 (줄마다 하나)',
              default: ['천문탑 우회', '검은 호수 위 저공비행', '금지된 숲 가장자리', '퀴디치 경기장 상공', '온실 지붕 위', '부엉이장 옆 바람길', '시계탑 사이', '해그리드 오두막 위', '지하 감옥 굴뚝', '그리핀도르 탑 위']),
        F.new(key: 'cmd_fly', type: :string, default: '비행', group: 'commands', label: '경로 고르기 명령어', hint: '웹 버튼이 [비행/번호]로 보냅니다'),
        F.new(key: 'msg_start', type: :text, group: 'messages', label: '시작', default: '%{game} 시작! 출발선에 서서 라운드마다 겹치지 않는 길을 고르세요.'),
        F.new(key: 'msg_result', type: :text, group: 'messages', label: '라운드 결과', default: "%{round}라운드 결과\n\n%{lines}"),
        F.new(key: 'msg_success', type: :text, group: 'messages', label: '통과', default: '%{route}: %{player} 통과'),
        F.new(key: 'msg_ring', type: :text, group: 'messages', label: '금빛 고리 통과', default: '%{route}: %{player} 금빛 고리를 통과해 내구도 +1'),
        F.new(key: 'msg_crash', type: :text, group: 'messages', label: '충돌', default: '%{route}: %{players} 충돌 (내구도 -1)'),
        F.new(key: 'msg_idle', type: :text, group: 'messages', label: '시간 초과', default: '%{players}: 길을 고르지 못해 내구도 -1'),
        F.new(key: 'msg_fall', type: :text, group: 'messages', label: '추락', default: '%{players}: 내구도가 0이 되어 추락했습니다.'),
        F.new(key: 'msg_void', type: :text, group: 'messages', label: '무효 라운드', default: '살아 있는 모두가 추락하게 되어 이 라운드는 무효입니다. 길을 다시 고릅니다.'),
        F.new(key: 'msg_winner', type: :text, group: 'messages', label: '우승', default: '%{winner}의 우승!'),
        F.new(key: 'msg_winners', type: :text, group: 'messages', label: '공동 우승', default: '%{winner}의 공동 우승!'),
      ] + Game::Events::Recruiting.fields(min: 3, max: 20)).freeze

      class << self
        def web?
          true
        end

        def spectatable?
          true
        end

        # 시간 초과는 길을 고르지 못한 것으로 (규칙의 일부)
        def continues_on_timeout?
          true
        end

        # 신청자를 포함한 인원 범위 (개인전)
        def max_total
          config['max_players'].to_i.clamp(3, 20)
        end

        def min_total
          config['min_players'].to_i.clamp(3, max_total)
        end

        def max_opponents
          max_total - 1
        end

        def min_opponents
          min_total - 1
        end

        def invite_error(total, _args = [])
          return if total >= min_total

          Game::Text.render(config['msg_players'] || '%{game}은 신청자를 포함해 %{min}~%{max}명이 필요합니다.', game: display_name, min: min_total, max: max_total)
        end
      end

      def start!
        seats = players.map { |player| player.seat.to_s }
        state.merge!('round' => 1, 'alive' => seats, 'out' => {}, 'choices' => {}, 'history' => [], 'durability' => durability, 'hp' => seats.to_h { |seat| [seat, durability] })
        session.update!(turn: 1)
        post(render(config['msg_start']))
        new_round!
      end

      # 웹 버튼: [비행/번호]. 탈락한 사람과 라운드가 끝난 뒤의 선택은 무시한다
      def handle(player, command, args, _status)
        return false unless command == config['cmd_fly']

        seat = player.seat.to_s
        lane = Integer(args.first.to_s, exception: false)
        return true unless alive.include?(seat) && lane&.between?(1, state['lanes'].to_i)

        state['choices'][seat] = lane
        session.save!
        resolve! if alive.all? { |each| state['choices'].key?(each) }
        true
      end

      def timeout!
        resolve!
      end

      def max_turns
        nil
      end

      # 동시에 고르는 컨텐츠: 아직 고르지 않은 살아 있는 자리들
      def pending_seats
        alive.reject { |seat| (state['choices'] || {}).key?(seat) }.map(&:to_i)
      end

      def card_data
        {
          'scores' => {},
          'round' => state['round'],
          'rounds' => state['round'],
          'hp' => state['hp'] || {},
          'routes' => state['routes'] || [],
          'chosen' => (state['choices'] || {}).keys,
          'last_round' => nil,
          'history' => Array(state['history']),
        }
      end

      def card_actions
        []
      end

      # 이 사람에게 보이는 비행 대결 (웹 진행 화면). 이번 라운드의 선택은 누가 골랐는지만 보이고, 끝난 라운드는 모두 공개된다.
      def view_for(player)
        seat = player&.seat
        out = state['out'] || {}
        choices = state['choices'] || {}
        finished = session.status == 'finished'

        {
          status: session.status, round: state['round'].to_i, lanes: state['lanes'].to_i, routes: state['routes'] || [],
          deadline_at: session.deadline_at&.iso8601, now: Time.current.iso8601(3),
          round_seconds: round_seconds, me: seat, spectator: player.nil?, commands: { fly: config['cmd_fly'] },
          my_choice: seat && choices[seat.to_s],
          durability: durability, ring: state['ring'],
          players: players.map do |other|
            key = other.seat.to_s
            house = other.character.group
            {
              seat: other.seat, account_id: other.account_id, name: other.name, house: house && { name: house.name, color: house.color },
              alive: alive.include?(key), out_round: out[key], chosen: choices.key?(key), result: other.result, hp: alive.include?(key) ? hp_of(key) : 0
            }
          end,
          history: Array(state['history']),
          finish: finished ? finish_view : nil,
        }
      end

      private

      def alive
        Array(state['alive'])
      end

      def round_seconds
        config['round_seconds'].to_i.clamp(5, 300)
      end

      # 처음 내구도 (시작할 때 판에 적어 두어, 게임 중에 설정을 바꿔도 이 판은 그대로)
      def durability
        (state['durability'] || config['durability']).to_i.clamp(1, 9)
      end

      def hp_of(seat)
        (state['hp'] || {}).fetch(seat.to_s, durability).to_i
      end

      # 살아 있는 사람보다 하나 적은 길 (최소 1개)
      def new_round!
        lanes = [alive.size - 1, 1].max
        names = config['routes'].presence || %w(왼쪽 가운데 오른쪽)
        state['lanes'] = lanes
        state['routes'] = names.sample(lanes)
        state['ring'] = config['ring_route'] == false ? nil : rand(1..lanes)
        state['choices'] = {}
        session.save!
        Game::Engine.set_deadline_in!(session, round_seconds.seconds)
      end

      def name_of(seat)
        players.find { |player| player.seat.to_s == seat.to_s }&.name.to_s
      end

      def resolve!
        before = alive.dup
        choices = state['choices'] || {}
        hp = before.to_h { |seat| [seat, hp_of(seat)] }
        results = {}
        ring_gain = []
        lines = []
        before.group_by { |seat| choices[seat] }.each do |lane, seats|
          route = lane && state['routes'][lane - 1]
          if lane.nil?
            seats.each do |seat|
              results[seat] = 'idle'
              hp[seat] -= 1
            end
            lines << render(config['msg_idle'], players: seats.map { |seat| name_of(seat) }.join(', '))
          elsif seats.size == 1
            seat = seats.first
            results[seat] = 'pass'
            if lane == state['ring'] && hp[seat] < durability
              hp[seat] += 1
              ring_gain << seat
              lines << render(config['msg_ring'], route: route, player: name_of(seat))
            else
              lines << render(config['msg_success'], route: route, player: name_of(seat))
            end
          else
            seats.each do |seat|
              results[seat] = 'crash'
              hp[seat] -= 1
            end
            lines << render(config['msg_crash'], route: route, players: seats.map { |seat| name_of(seat) }.join('·'))
          end
        end

        fell = before.select { |seat| hp[seat] <= 0 }
        void = fell.size == before.size
        hp_before = before.to_h { |seat| [seat, hp_of(seat)] }
        hp_after = void ? hp_before : hp.transform_values { |value| [value, 0].max }
        state['history'] = Array(state['history']) + [{
          'round' => state['round'], 'lanes' => state['lanes'], 'routes' => state['routes'], 'ring' => state['ring'], 'alive_before' => before, 'choices' => choices, 'results' => results,
          'hp_before' => hp_before, 'hp_after' => hp_after, 'ring_gain' => ring_gain, 'fell' => void ? [] : fell, 'void' => void
        }]

        # 모두 한꺼번에 추락하게 되면 그 라운드는 없던 일로 하고 길을 다시 고른다
        if void
          post(render(config['msg_result'], round: state['round'], lines: [*lines, render(config['msg_void'])].join("\n")))
          return next_round!
        end

        lines << render(config['msg_fall'], players: fell.map { |seat| name_of(seat) }.join(', ')) if fell.any?
        result = render(config['msg_result'], round: state['round'], lines: lines.join("\n"))
        fell.each { |seat| state['out'][seat] = state['round'] }
        state['hp'] = hp_after.reject { |seat, _| fell.include?(seat) }
        state['alive'] = before - fell
        return finish_race!(result) if alive.size <= 2

        post(result)
        next_round!
      end

      def next_round!
        state['round'] += 1
        session.update!(turn: session.turn + 1)
        new_round!
      end

      # 끝: 남은 사람(1~2명)이 내구도가 높은 순으로 순위를 차지하고(같으면 공동), 나머지는 추락한 라운드가 늦을수록 높은 순위
      def finish_race!(result)
        survivors = alive.group_by { |seat| hp_of(seat) }.sort_by { |value, _| -value }.map { |_, seats| seats }
        fallen = (state['out'] || {}).group_by { |_, round| round }.sort_by { |round, _| -round.to_i }.map { |_, pairs| pairs.map(&:first) }
        state['ranks'] = (survivors + fallen).each_with_index.map { |seats, index| { 'rank' => index + 1, 'seats' => seats.map(&:to_i).sort } }
        state['mvp'] = Game::FlyingScenes.call(state['history'], players)
        session.save!

        winners = players.select { |player| survivors.first.include?(player.seat.to_s) }
        names = winners.map(&:name).join(', ')
        message = render(config[winners.size > 1 ? 'msg_winners' : 'msg_winner'], winner: names)
        finish!(winners: winners, message: "#{result}\n\n#{message}", split_points: false)
      end

      # 끝난 뒤 보여 줄 것: 등수 묶음, 사람마다 받은 점수·재화·아이템, 가장 바보 같았던 장면
      def finish_view
        {
          ranks: state['ranks'] || [], mvp: state['mvp'] || [], currency: common['currency_name'], test: session.test?,
          rewards: players.to_h do |player|
            outcome = player.result.to_s
            [player.seat, session.test? || outcome.blank? ? nil : {
              result: outcome, points: config["points_#{outcome}"].to_i, money: config["reward_money_#{outcome}"].to_i,
              items: outcome == 'win' ? Array(config['reward_items_win']).filter_map { |line| line.to_s.split('|').first.to_s.strip.presence } : []
            }]
          end,
        }
      end
    end
  end
end
