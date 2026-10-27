# frozen_string_literal: true

module Game
  module Web
    # 그린고츠 (웹 전용 이벤트, 4~24명 개인전, 로우볼 숫자 게임): 그린고츠 고블린이 "가장 낮은 값을 부른 사람, 단 혼자 부른 사람에게만" 금화를 준다.
    # 탈락 없이 정해진 라운드를 모두 한다. 서버는 단계가 바뀔 때만 계산하고(모두 냈을 때 / 시간이 끝났을 때), 화면은 2.5초마다 읽는다.
    #
    #   매 라운드 각자 1 ~ (인원 + number_extra) 사이 숫자 하나를 비밀 제출한다 (pick_seconds).
    #   혼자만 고른 숫자 중 가장 작은 3개를 낸 사람이 1·2·3위 (+3 / +2 / +1점). 혼자 고른 숫자가 없으면 그 라운드는 아무도 점수를 못 받는다.
    #   고블린의 세금: 가장 많은 사람이 고른 숫자(2명 이상)를 낸 사람들은 -1점 (같은 인원이 몰린 숫자가 여럿이면 모두).
    #   시간 안에 못 낸 사람은 그 라운드에 빠진다 (숫자가 없으니 점수도 세금도 없고, 남들의 계산에도 들어가지 않는다).
    #   끝: 정해진 라운드 뒤 점수 1위 (동점이면 공동 우승). 점수·보상은 공통 처리(finish!) (테스트 플레이는 점수·보상 없음)
    #   단계: pick(숫자 비밀 제출) → reveal(금고 문이 숫자 순서대로 열리는 연출) → 다음 라운드 pick … → finished
    #
    # state: mode=event, phase, round, picks{seat=>number}, scores{seat=>점수}, results[{round,picks,counts,ranks[{seat,number,points}],tax[{seat,number}],taxed_numbers,absent}], winner_seats, log[]
    class Greengotts < Game::Kinds::Base
      KEY = 'greengotts'

      include Game::Events::Recruiting

      FIELDS = (base_fields(name: '그린고츠', command: '그린고츠', points_win: 10) + [
        F.new(key: 'rounds', type: :integer, default: 10, group: 'rules', label: '라운드 수', hint: '1~30'),
        F.new(key: 'number_extra', type: :integer, default: 5, group: 'rules', label: '고를 수 있는 숫자 범위', hint: '1 ~ (인원 + 이 값). 기본 5'),
        F.new(key: 'points_first', type: :integer, default: 3, group: 'rules', label: '1위 점수 (가장 작은 혼자 숫자)'),
        F.new(key: 'points_second', type: :integer, default: 2, group: 'rules', label: '2위 점수'),
        F.new(key: 'points_third', type: :integer, default: 1, group: 'rules', label: '3위 점수'),
        F.new(key: 'tax_points', type: :integer, default: 1, group: 'rules', label: '고블린의 세금 (감점)', hint: '가장 많은 사람이 고른 숫자를 낸 사람들이 깎이는 점수 (0이면 세금 없음)'),
        F.new(key: 'pick_seconds', type: :integer, default: 20, group: 'time', label: '숫자 고르는 시간 (초)', hint: '못 낸 사람은 그 라운드에 빠집니다'),
        F.new(key: 'reveal_seconds', type: :integer, default: 16, group: 'time', label: '금고 공개 시간 (초)', hint: '금고 문이 차례로 열리는 연출을 볼 시간'),
        F.new(key: 'first_turn_bonus', type: :integer, default: 25, group: 'time', label: '첫 라운드 추가 시간 (초)', hint: '오프닝·규칙 안내를 보는 시간'),
        F.new(key: 'goblin_name', type: :string, default: '그린고츠 고블린', group: 'roles', label: '고블린 이름'),
        F.new(key: 'cmd_pick', type: :string, default: '입찰', group: 'commands', label: '숫자 제출', hint: '[입찰/7] 웹 화면에서는 숫자 금고를 누릅니다'),
        F.new(key: 'msg_start', type: :text, group: 'messages', label: '시작', default: "%{game} 시작! %{count}명이 %{rounds}라운드를 겨룹니다.\n%{goblin}{은는} 혼자 부른 가장 작은 숫자에게 금화를 줍니다."),
        F.new(key: 'msg_round', type: :text, group: 'messages', label: '라운드 결과', default: '라운드 %{round}: %{ranks}'),
        F.new(key: 'msg_round_none', type: :text, group: 'messages', label: '라운드 결과 (혼자 고른 숫자 없음)', default: '라운드 %{round}: 혼자 고른 숫자가 없어 아무도 금화를 받지 못했습니다.'),
        F.new(key: 'msg_win', type: :text, group: 'messages', label: '종료', default: "%{game} 종료! 우승: %{winners}\n\n%{ranking}"),
      ] + Game::Events::Recruiting.fields(min: 4, max: 24)).freeze

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

        # 4~24명이 하는 컨텐츠라 여럿이 하는 컨텐츠로 센다 (신청이 아니라 이벤트로 연다)
        def max_opponents
          [config['event_max_players'].to_i.clamp(4, 24) - 1, 3].max
        end

        def chat_keep
          800
        end

        def invite_error(_total, _args = [])
          '그린고츠는 이벤트로 엽니다. 모집 안내를 기다려 주세요.'
        end
      end

      def event_min_players
        [super, 4].max
      end

      def event_max_players
        [super, event_min_players].max.clamp(4, 24)
      end

      # ── 시작 ──
      def start!
        state.merge!('round' => 1, 'picks' => {}, 'scores' => players.to_h { |player| [player.seat.to_s, 0] }, 'results' => [], 'log' => [], 'started_at' => Time.current.iso8601)
        session.update!(turn: 1)
        post(render(config['msg_start'], count: players.size, rounds: rounds, goblin: config['goblin_name']))
        begin_pick!(first: true)
      end

      # ── 명령 (웹 화면에서 보낸다) ──
      def handle(player, command, args, _status)
        return false unless command == config['cmd_pick']

        pick!(player, Integer(args.first.to_s, exception: false))
        true
      end

      # 단계 마감 (Game::TimeoutWorker)
      def timeout!
        case state['phase']
        when 'pick' then resolve_round!
        when 'reveal' then after_reveal!
        end
      end

      # 이 이벤트는 탈락이 없다: [기권]은 받지 않는다
      def forfeit!(_player); end

      def pending_seats
        state['phase'] == 'pick' ? players.map(&:seat) - state['picks'].keys.map(&:to_i) : []
      end

      def max_turns
        rounds
      end

      def team_of(_player)
        nil
      end

      def can_chat?(player)
        session.status != 'active' || player.present?
      end

      def card_data
        { 'phase' => state['phase'], 'round' => state['round'].to_i, 'rounds' => rounds, 'web' => true }
      end

      def card_actions
        []
      end

      # 이 사람에게 보이는 화면. 이번 라운드의 숫자는 공개 전까지 자기 것만 보인다 (관전자는 낸 사람 수만).
      def view_for(player, staff: false)
        seat = player&.seat
        phase = state['phase']
        finished = session.status == 'finished'
        scores = state['scores'] || {}
        revealing = %w(reveal finished).include?(phase)

        {
          phase: phase, status: session.status, round: state['round'].to_i, rounds: rounds, max_number: max_number,
          deadline_at: session.deadline_at&.iso8601, now: Time.current.iso8601(3),
          me: seat, spectator: player.nil?, spectator_staff: player.nil? && staff,
          goblin_name: config['goblin_name'], reveal_seconds: config['reveal_seconds'].to_i, points: [config['points_first'].to_i, config['points_second'].to_i, config['points_third'].to_i], tax_points: config['tax_points'].to_i,
          players: players.map do |other|
            { seat: other.seat, name: other.name, account_id: other.account_id, score: scores[other.seat.to_s].to_i, submitted: state['picks'].key?(other.seat.to_s) }
          end,
          my_pick: seat && phase == 'pick' ? state['picks'][seat.to_s] : nil,
          submitted_count: state['picks'].size,
          # 막 끝난 라운드: 모두의 숫자와 금고 순서 (공개 단계에서만)
          reveal: revealing ? latest_result : nil,
          history: Array(state['results']).map { |result| result.slice('round', 'ranks', 'tax') },
          winner_seats: finished ? Array(state['winner_seats']) : nil,
          commands: { 'pick' => config['cmd_pick'], 'join' => config['cmd_join'] },
          min_players: event_min_players, max_players: event_max_players,
        }
      end

      private

      def rounds
        config['rounds'].to_i.clamp(1, 30)
      end

      def max_number
        players.size + config['number_extra'].to_i.clamp(1, 50)
      end

      def latest_result
        Array(state['results']).last
      end

      def set_phase!(phase, seconds)
        state['phase'] = phase
        session.save!
        Game::Engine.set_deadline_in!(session, seconds.to_i.clamp(1, 24 * 3600).seconds)
      end

      def name_of(seat)
        players.find { |player| player.seat == seat.to_i }&.name.to_s
      end

      # ── 숫자 고르기 ──
      def begin_pick!(first: false)
        state['picks'] = {}
        extra = first ? config['first_turn_bonus'].to_i.clamp(0, 180) : 0
        set_phase!('pick', config['pick_seconds'].to_i + extra)
      end

      def pick!(player, number)
        return unless state['phase'] == 'pick'
        return if number.nil? || number < 1 || number > max_number

        state['picks'][player.seat.to_s] = number
        session.save!
        resolve_round! if state['picks'].size >= players.size
      end

      # 라운드 계산: 혼자 고른 숫자 중 작은 3개가 1~3위, 가장 많이 몰린 숫자(2명 이상)는 세금. 못 낸 사람은 빠진다.
      def resolve_round!
        picks = state['picks'].transform_values(&:to_i)
        counts = picks.values.tally
        point_table = [config['points_first'].to_i, config['points_second'].to_i, config['points_third'].to_i]
        ranks = counts.select { |_, count| count == 1 }.keys.sort.first(3).each_with_index.map do |number, index|
          { 'seat' => picks.key(number).to_i, 'number' => number, 'points' => point_table[index] }
        end
        top = counts.values.max.to_i
        taxed_numbers = top >= 2 && config['tax_points'].to_i.positive? ? counts.select { |_, count| count == top }.keys.sort : []
        tax = picks.select { |_, number| taxed_numbers.include?(number) }.map { |seat, number| { 'seat' => seat.to_i, 'number' => number } }

        scores = state['scores']
        ranks.each { |rank| scores[rank['seat'].to_s] = scores[rank['seat'].to_s].to_i + rank['points'] }
        tax.each { |entry| scores[entry['seat'].to_s] = scores[entry['seat'].to_s].to_i - config['tax_points'].to_i }

        result = { 'round' => state['round'].to_i, 'picks' => picks, 'counts' => counts.transform_keys(&:to_s), 'ranks' => ranks, 'tax' => tax, 'taxed_numbers' => taxed_numbers,
                   'absent' => players.map(&:seat) - picks.keys.map(&:to_i) }
        state['results'] = Array(state['results']) << result
        post_round(result)
        set_phase!('reveal', config['reveal_seconds'])
      end

      def post_round(result)
        if result['ranks'].empty?
          post(render(config['msg_round_none'], round: result['round']))
        else
          line = result['ranks'].each_with_index.map { |rank, index| "#{index + 1}위 #{name_of(rank['seat'])}(#{rank['number']}, +#{rank['points']})" }.join(' · ')
          post(render(config['msg_round'], round: result['round'], ranks: line))
        end
      end

      def after_reveal!
        if state['round'].to_i >= rounds
          finish_game!
        else
          state['round'] = state['round'].to_i + 1
          begin_pick!
        end
      end

      # ── 끝 ──
      def finish_game!
        scores = state['scores']
        ordered = players.sort_by { |player| [-scores[player.seat.to_s].to_i, player.seat] }
        top = scores[ordered.first.seat.to_s].to_i
        winners = ordered.select { |player| scores[player.seat.to_s].to_i == top }
        state['phase'] = 'finished'
        state['winner_seats'] = winners.map(&:seat)
        ranking = ordered.each_with_index.map { |player, index| "#{index + 1}위 #{player.name} — #{scores[player.seat.to_s].to_i}점" }.join("\n")
        finish!(winners: winners, split_points: winners.size > 1,
                message: render(config['msg_win'], winners: winners.map(&:name).join(', '), ranking: ranking))
      end
    end
  end
end
