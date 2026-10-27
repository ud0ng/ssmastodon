# frozen_string_literal: true

module Game
  module Web
    # 덤블도어의 군대 (웹 전용 이벤트, 5~24명, 아발론형 추리·투표): 덤블도어의 군대(DA)가 비밀 임무를 수행하는데 엄브리지의 첩자가 섞여 있다.
    # 탈락 없이 모두 끝까지 참여한다. 서버는 단계가 바뀔 때만 계산하고(투표가 다 모이거나 시간이 끝났을 때), 화면은 2.5초마다 읽는다.
    #
    #   인원별 첩자 수(올림 1/3)와 임무별 대원 수는 TEAM_SIZES / team_sizes, 임무는 5개
    #   첩자끼리는 서로를 안다. 해리(DA 중 한 명)는 첩자가 누구인지 안다. 16명 이상이면 론이 추가된다 (해리가 누구인지 안다. 첩자는 둘을 헷갈릴 수 있다)
    #   단계: team(리더가 대원 고르기) → vote(전원 찬성/반대) → vote_result(공개 잠깐) → mission(대원이 성공/방해 비밀 제출) → result(카드 공개 잠깐)
    #         → 다음 임무 team … 3성공이면 assassin(첩자가 해리 지목) → finished
    #   투표: 반대가 과반이면 부결 (리더가 다음 사람으로), 5번 연속 부결이면 첩자 승리. 통과하면 연속 부결 수는 임무가 끝날 때 0
    #   임무: 방해 카드는 첩자만 낼 수 있다. 방해가 1장 이상이면 실패. 예외: 7명 이상 게임의 4번째 임무, 대원이 6명 이상인 임무는 2장 이상이어야 실패.
    #         방해 장수만 공개되고 누가 냈는지는 비공개 (카드 순서는 섞어서 보여 준다)
    #   끝: 임무 3실패 또는 5연속 부결 → 첩자 승리. 임무 3성공 → 첩자가 해리를 지목해 맞히면 첩자 역전승, 아니면 DA 승리.
    #   시간이 지나도 판이 멈추지 않는다: 리더가 안 고르면 무작위 대원, 투표를 안 하면 찬성, 카드를 안 내면 성공, 해리 지목을 안 하면 무작위 (모두 timeout!)
    #   점수·보상은 공통 처리(finish!). 이긴 쪽 전원이 승리 (테스트 플레이는 점수·보상 없음)
    #
    # state: mode=event, phase, roles{seat=>role}, order[seat](리더 순서), leader_index, mission(1~5), rejects, team[seat], votes{seat=>yes/no}, vote_result{yes,no,passed},
    #        cards{seat=>success/sabotage}, results[{no,team,leader,size,need,sabotage,success,cards[]}], guesses{spy=>target}, assassin{target,hit}, winner, reason, log[]
    class DumbledoresArmy < Game::Kinds::Base
      KEY = 'dumbledores_army'

      include Game::Events::Recruiting

      MISSIONS = 5
      TEAM_SIZES = { 5 => [2, 3, 2, 3, 3], 6 => [2, 3, 4, 3, 4], 7 => [2, 3, 3, 4, 4] }.freeze
      CHAT_LENGTH = 200

      FIELDS = (base_fields(name: '덤블도어의 군대', command: '덤블도어의군대', points_win: 10) + [
        F.new(key: 'reject_limit', type: :integer, default: 5, group: 'rules', label: '연속 부결 한도', hint: '이 횟수만큼 연속으로 부결되면 첩자 승리 (2~9)'),
        F.new(key: 'harry_guess', type: :boolean, default: true, group: 'rules', label: '임무 3성공 뒤 첩자의 해리 지목', hint: '끄면 임무 3성공으로 DA가 바로 승리합니다'),
        F.new(key: 'ron_from', type: :integer, default: 16, group: 'rules', label: '론이 추가되는 인원', hint: '이 인원 이상이면 론이 추가됩니다 (0이면 론 없음)'),
        F.new(key: 'team_seconds', type: :integer, default: 120, group: 'time', label: '대원 고르기 시간 (초)', hint: '시간이 지나면 무작위로 정해집니다'),
        F.new(key: 'vote_seconds', type: :integer, default: 90, group: 'time', label: '투표 시간 (초)', hint: '안 낸 사람은 찬성으로 셉니다'),
        F.new(key: 'mission_seconds', type: :integer, default: 60, group: 'time', label: '임무 카드 제출 시간 (초)', hint: '안 낸 사람은 성공 카드로 셉니다'),
        F.new(key: 'assassin_seconds', type: :integer, default: 180, group: 'time', label: '해리 지목 시간 (초)', hint: '시간이 지나면 정해진 표로 (없으면 무작위)'),
        F.new(key: 'pause_seconds', type: :integer, default: 7, group: 'time', label: '투표 결과 공개 시간 (초)'),
        F.new(key: 'reveal_seconds', type: :integer, default: 9, group: 'time', label: '임무 카드 공개 시간 (초)', hint: '카드가 한 장씩 뒤집히는 연출을 볼 시간 (대원 수만큼 더해집니다)'),
        F.new(key: 'first_turn_bonus', type: :integer, default: 30, group: 'time', label: '첫 대원 고르기 추가 시간 (초)', hint: '오프닝·규칙 안내를 보는 시간'),
        F.new(key: 'da_name', type: :string, default: '덤블도어의 군대', group: 'roles', label: '선한 진영 이름'),
        F.new(key: 'spy_name', type: :string, default: '엄브리지의 첩자', group: 'roles', label: '첩자 진영 이름'),
        F.new(key: 'role_harry', type: :string, default: '해리', group: 'roles', label: '해리 이름'),
        F.new(key: 'role_ron', type: :string, default: '론', group: 'roles', label: '론 이름'),
        F.new(key: 'role_da', type: :string, default: '대원', group: 'roles', label: '일반 대원 이름'),
        F.new(key: 'role_spy', type: :string, default: '첩자', group: 'roles', label: '첩자 이름'),
        F.new(key: 'cmd_team', type: :string, default: '대원', group: 'commands', label: '대원 정하기 (리더)', hint: '[대원/1/3] 웹 화면에서는 카드를 끌어다 놓습니다'),
        F.new(key: 'cmd_yes', type: :string, default: '찬성', group: 'commands', label: '찬성 투표'),
        F.new(key: 'cmd_no', type: :string, default: '반대', group: 'commands', label: '반대 투표'),
        F.new(key: 'cmd_success', type: :string, default: '성공', group: 'commands', label: '성공 카드 (대원)'),
        F.new(key: 'cmd_sabotage', type: :string, default: '방해', group: 'commands', label: '방해 카드 (첩자 대원)'),
        F.new(key: 'cmd_guess', type: :string, default: '지목', group: 'commands', label: '해리 지목 (첩자)', hint: '[지목/자리 번호]'),
        F.new(key: 'msg_start', type: :text, group: 'messages', label: '시작', default: "%{game} 시작! %{count}명 중 %{spies}명이 %{spy}입니다.\n임무는 %{missions}개, 3개를 성공하면 %{da}의 승리 후보입니다."),
        F.new(key: 'msg_team', type: :text, group: 'messages', label: '대원 제안', default: '%{leader}{이가} %{count}명으로 임무 %{mission}을 제안했습니다: %{team}'),
        F.new(key: 'msg_vote_passed', type: :text, group: 'messages', label: '투표 통과', default: '찬성 %{yes} · 반대 %{no} — 통과! 임무 %{mission}을 떠납니다.'),
        F.new(key: 'msg_vote_failed', type: :text, group: 'messages', label: '투표 부결', default: '찬성 %{yes} · 반대 %{no} — 부결 (연속 %{rejects}번). 리더가 %{next}{으로로} 바뀝니다.'),
        F.new(key: 'msg_mission_success', type: :text, group: 'messages', label: '임무 성공', default: '임무 %{mission} 성공! (방해 %{sabotage}장)'),
        F.new(key: 'msg_mission_fail', type: :text, group: 'messages', label: '임무 실패', default: '임무 %{mission} 실패… (방해 %{sabotage}장)'),
        F.new(key: 'msg_assassin', type: :text, group: 'messages', label: '해리 지목 시작', default: '%{da}{이가} 임무 3개를 성공했습니다! 이제 %{spy}들이 상의해 %{harry}{을를} 지목합니다.'),
        F.new(key: 'msg_win_da', type: :text, group: 'messages', label: 'DA 승리', default: "%{game} 종료! %{da}의 승리!\n\n%{roles}"),
        F.new(key: 'msg_win_spy_missions', type: :text, group: 'messages', label: '첩자 승리 (임무 3실패)', default: "%{game} 종료! 임무가 3번 실패했습니다. %{spy}의 승리!\n\n%{roles}"),
        F.new(key: 'msg_win_spy_rejects', type: :text, group: 'messages', label: '첩자 승리 (연속 부결)', default: "%{game} 종료! %{limit}번 연속 부결되어 %{spy}의 승리!\n\n%{roles}"),
        F.new(key: 'msg_win_spy_guess', type: :text, group: 'messages', label: '첩자 승리 (해리 지목)', default: "%{game} 종료! %{spy}들이 %{harry}{을를} 맞혔습니다. 역전승!\n\n%{roles}"),
        F.new(key: 'msg_da_guess', type: :text, group: 'messages', label: 'DA 승리 (해리 지목 실패)', default: "%{game} 종료! %{spy}들이 %{target}{을를} 지목했지만 %{harry}{이가} 아니었습니다. %{da}의 승리!\n\n%{roles}"),
      ] + Game::Events::Recruiting.fields(min: 5, max: 24)).freeze

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

        # 5~24명이 하는 컨텐츠라 여럿이 하는 컨텐츠로 센다 (신청이 아니라 이벤트로 연다)
        def max_opponents
          [config['event_max_players'].to_i.clamp(5, 24) - 1, 4].max
        end

        # 판 전체의 대화를 다시 볼 수 있게 채팅을 넉넉히 남긴다 (Game::Lobby.chat!)
        def chat_keep
          800
        end

        def invite_error(_total, _args = [])
          '덤블도어의 군대는 이벤트로 엽니다. 모집 안내를 기다려 주세요.'
        end

        # 인원별 임무마다 필요한 대원 수 [임무1..5]
        def team_sizes(total)
          TEAM_SIZES.fetch(total) do
            case total
            when 8..10 then [3, 4, 4, 5, 5]
            when 11..15 then [4, 5, 5, 6, 6]
            when 16..20 then [5, 6, 6, 7, 7]
            else [6, 7, 7, 8, 8]
            end
          end
        end

        # 첩자 수: 인원의 1/3 올림 (5→2, 7→3, 10→4, 15→5, 20→7, 24→8)
        def spy_count(total)
          (total / 3.0).ceil
        end

        # 이 임무가 실패하려면 필요한 방해 장수: 7명 이상 게임의 4번째 임무, 대원이 6명 이상인 임무는 2장
        def sabotage_needed(total, mission, size)
          (total >= 7 && mission == 4) || size >= 6 ? 2 : 1
        end
      end

      def event_min_players
        [super, 5].max
      end

      def event_max_players
        [super, event_min_players].max.clamp(5, 24)
      end

      # ── 시작 ──
      def start!
        roles = deal_roles
        order = players.map(&:seat).shuffle
        state.merge!('roles' => roles, 'order' => order, 'leader_index' => 0, 'mission' => 1, 'rejects' => 0, 'results' => [], 'team' => [], 'votes' => {}, 'cards' => {},
                     'guesses' => {}, 'log' => [], 'started_at' => Time.current.iso8601)
        session.update!(turn: 1)
        post(render(config['msg_start'], count: players.size, spies: spies.size, spy: config['spy_name'], missions: MISSIONS, da: config['da_name']))
        begin_team!(first: true)
      end

      # ── 명령 (웹 화면에서 보낸다) ──
      def handle(player, command, args, _status)
        action = { config['cmd_team'] => :team, config['cmd_yes'] => :yes, config['cmd_no'] => :no, config['cmd_success'] => :success,
                   config['cmd_sabotage'] => :sabotage, config['cmd_guess'] => :guess }[command]
        return false if action.nil?

        case action
        when :team then propose!(player, args)
        when :yes then vote!(player, 'yes')
        when :no then vote!(player, 'no')
        when :success then submit_card!(player, 'success')
        when :sabotage then submit_card!(player, 'sabotage')
        else guess!(player, Integer(args.first.to_s, exception: false))
        end
        true
      end

      # 단계 마감 (Game::TimeoutWorker): 시간이 지나면 정해진 대로 넘어간다
      def timeout!
        case state['phase']
        when 'team' then auto_team!
        when 'vote' then resolve_vote!(auto: true)
        when 'vote_result' then after_vote_result!
        when 'mission' then resolve_mission!(auto: true)
        when 'result' then after_result!
        when 'assassin' then resolve_assassin!(auto: true)
        end
      end

      # 이 이벤트는 탈락이 없다: [기권]은 받지 않는다
      def forfeit!(_player); end

      def pending_seats
        case state['phase']
        when 'team' then [leader_seat]
        when 'vote' then players.map(&:seat) - state['votes'].keys.map(&:to_i)
        when 'mission' then state['team'] - state['cards'].keys.map(&:to_i)
        when 'assassin' then spies.map(&:seat) - state['guesses'].keys.map(&:to_i)
        else []
        end
      end

      def max_turns
        MISSIONS
      end

      # 첩자 채팅(팀 채팅)이 닿는 팀: 첩자끼리만 보이는 채팅 ('spy'), 나머지는 전체 채팅
      def team_of(player)
        role_of(player.seat) == 'spy' ? 'spy' : nil
      end

      def can_chat?(player)
        session.status != 'active' || player.present?
      end

      def card_data
        {
          'phase' => state['phase'],
          'mission' => state['mission'].to_i,
          'results' => Array(state['results']).map { |result| result['success'] },
          'rejects' => state['rejects'].to_i,
          'web' => true,
        }
      end

      def card_actions
        []
      end

      # 이 사람에게 보이는 화면. player 가 nil 이면 관전: 운영진(staff)은 모든 역할이 보이고, 그 밖의 관전자는 공개된 것만 본다.
      def view_for(player, staff: false)
        seat = player&.seat
        roles = state['roles'] || {}
        role = roles[seat.to_s]
        finished = session.status == 'finished'
        watching_staff = player.nil? && staff
        reveal = finished || watching_staff
        phase = state['phase']
        voted_open = %w(vote_result).include?(phase) || reveal_votes?(phase)
        known = known_roles(role, reveal)

        {
          phase: phase, status: session.status, mission: state['mission'].to_i, missions: MISSIONS, rejects: state['rejects'].to_i, reject_limit: reject_limit,
          deadline_at: session.deadline_at&.iso8601, now: Time.current.iso8601(3), winner: state['winner'], reason: state['reason'],
          me: seat, spectator: player.nil?, spectator_staff: watching_staff,
          leader: leader_seat, size_needed: team_size, sabotage_needed: current_need, team: Array(state['team']),
          da_name: config['da_name'], spy_name: config['spy_name'], spy_count: spies.size,
          role_names: %w(harry ron da spy).to_h { |key| [key, role_name(key)] },
          players: players.map do |other|
            {
              seat: other.seat, name: other.name, account_id: other.account_id,
              role: known[other.seat.to_s], leader: other.seat == leader_seat, on_team: Array(state['team']).include?(other.seat),
              voted: state['votes'].key?(other.seat.to_s), vote: voted_open ? state['votes'][other.seat.to_s] : nil,
              card_in: phase == 'mission' ? state['cards'].key?(other.seat.to_s) : nil,
            }
          end,
          my_role: role && { key: role, name: role_name(role), spy: role == 'spy', how: how_text(role) },
          my_vote: seat && state['votes'][seat.to_s],
          my_card: seat && phase == 'mission' ? state['cards'][seat.to_s] : nil,
          can_sabotage: role == 'spy',
          on_team: seat.present? && Array(state['team']).include?(seat),
          cards_in: state['cards'].size,
          voted_count: state['votes'].size,
          vote_result: %w(vote_result mission result assassin).include?(phase) || finished ? state['vote_result'] : nil,
          # 임무 결과: 카드 장수만 (누가 냈는지는 비공개). 막 끝난 임무의 카드는 섞은 순서로 한 장씩 뒤집는다
          results: Array(state['results']).map { |result| result.slice('no', 'team', 'leader', 'size', 'need', 'sabotage', 'success', 'cards', 'rejects') },
          assassin: assassin_view(role, reveal),
          history: Array(state['history']),
          log: Array(state['log']).last(40),
          commands: %w(team yes no success sabotage guess join).to_h { |key| [key, config["cmd_#{key}"]] },
          min_players: event_min_players, max_players: event_max_players,
          roles_final: finished ? roles.to_h { |key, value| [key, role_name(value)] } : nil,
        }
      end

      private

      # ── 도움 ──
      def roles
        state['roles'] || {}
      end

      def role_of(seat)
        roles[seat.to_s]
      end

      def role_name(role)
        config["role_#{role}"].presence || role
      end

      def spies
        players.select { |player| role_of(player.seat) == 'spy' }
      end

      def reject_limit
        config['reject_limit'].to_i.clamp(2, 9)
      end

      def order
        state['order'] || []
      end

      def leader_seat
        return nil if order.empty?

        order[state['leader_index'].to_i % order.size]
      end

      def leader
        players.find { |player| player.seat == leader_seat }
      end

      def mission_no
        state['mission'].to_i
      end

      def team_size
        self.class.team_sizes(players.size)[mission_no - 1]
      end

      def current_need
        self.class.sabotage_needed(players.size, mission_no, team_size.to_i)
      end

      def names(seats)
        Array(seats).filter_map { |seat| players.find { |player| player.seat == seat.to_i }&.name }.join(', ')
      end

      # 역할 나누기: 첩자 수만큼 무작위 첩자, 나머지 중 해리 한 명(첩자가 아닌 사람), 인원이 충분하면 론 한 명
      def deal_roles
        seats = players.map(&:seat).shuffle
        list = {}
        seats.first(self.class.spy_count(seats.size)).each { |seat| list[seat.to_s] = 'spy' }
        rest = seats.drop(list.size)
        list[rest.shift.to_s] = 'harry'
        ron_from = config['ron_from'].to_i
        list[rest.shift.to_s] = 'ron' if ron_from.positive? && seats.size >= ron_from && rest.any?
        rest.each { |seat| list[seat.to_s] = 'da' }
        list
      end

      # 이 사람에게 보이는 다른 사람의 역할 { 자리 => 역할 }: 자기 자신, 첩자끼리(첩자 역할만), 해리는 첩자를, 론은 해리를. 끝났거나 운영진 관전이면 전부
      def known_roles(role, reveal)
        return roles if reveal

        shown = {}
        case role
        when 'spy' then spies.each { |player| shown[player.seat.to_s] = 'spy' }
        when 'harry' then spies.each { |player| shown[player.seat.to_s] = 'spy' }
        when 'ron' then roles.each { |seat, each| shown[seat] = 'harry' if each == 'harry' }
        end
        shown
      end

      def reveal_votes?(phase)
        %w(mission result assassin finished).include?(phase)
      end

      def how_text(role)
        case role
        when 'spy' then "#{config['da_name']} 사이에 숨은 #{role_name('spy')}입니다. 다른 #{role_name('spy')}가 누군지 압니다. 임무에서 방해 카드를 낼 수 있습니다."
        when 'harry' then "#{role_name('spy')}가 누구인지 압니다. 너무 티 나게 행동하면 마지막에 지목당합니다."
        when 'ron' then "#{role_name('harry')}가 누구인지 압니다. #{role_name('spy')}가 #{role_name('harry')}와 헷갈릴 수 있습니다."
        else "#{config['da_name']}의 대원입니다. 임무에서 성공 카드만 낼 수 있습니다."
        end
      end

      def assassin_view(role, reveal)
        return nil unless %w(assassin finished).include?(state['phase'])

        guesses = role == 'spy' || reveal ? state['guesses'] : {}
        { target: state.dig('assassin', 'target'), hit: state.dig('assassin', 'hit'), guesses: guesses, harry: reveal ? roles.key('harry')&.to_i : nil,
          guessed: state['guesses'].size, spies: spies.size }
      end

      def set_phase!(phase, seconds)
        state['phase'] = phase
        session.save!
        Game::Engine.set_deadline_in!(session, seconds.to_i.clamp(1, 24 * 3600).seconds)
      end

      def history!(entry)
        state['history'] = Array(state['history']) << entry
      end

      # ── 대원 고르기 ──
      def begin_team!(first: false)
        state.merge!('team' => [], 'votes' => {}, 'cards' => {}, 'vote_result' => nil)
        extra = first ? config['first_turn_bonus'].to_i.clamp(0, 180) : 0
        set_phase!('team', config['team_seconds'].to_i + extra)
      end

      def propose!(player, args)
        return unless state['phase'] == 'team' && player.seat == leader_seat

        seats = Array(args).filter_map { |value| Integer(value.to_s, exception: false) }.uniq
        return unless seats.size == team_size && (seats - players.map(&:seat)).empty?

        start_vote!(seats.sort)
      end

      # 리더가 시간 안에 못 정하면 무작위로 (리더 자신을 넣는다)
      def auto_team!
        others = (players.map(&:seat) - [leader_seat]).shuffle
        start_vote!(([leader_seat] + others).first(team_size).sort)
      end

      def start_vote!(seats)
        state['team'] = seats
        state['votes'] = {}
        post(render(config['msg_team'], leader: leader, count: seats.size, mission: mission_no, team: names(seats)))
        set_phase!('vote', config['vote_seconds'])
      end

      # ── 투표 ──
      def vote!(player, choice)
        return unless state['phase'] == 'vote'

        state['votes'][player.seat.to_s] = choice
        session.save!
        resolve_vote! if state['votes'].size >= players.size
      end

      # 투표 결과: 반대가 과반이면 부결. 안 낸 사람은 찬성 (시간이 끝났을 때)
      def resolve_vote!(auto: false)
        players.each { |player| state['votes'][player.seat.to_s] ||= 'yes' } if auto
        yes = state['votes'].select { |_, value| value == 'yes' }.keys.map(&:to_i).sort
        no = state['votes'].select { |_, value| value == 'no' }.keys.map(&:to_i).sort
        passed = (no.size * 2) <= players.size
        state['vote_result'] = { 'yes' => yes, 'no' => no, 'passed' => passed, 'mission' => mission_no, 'leader' => leader_seat, 'team' => state['team'] }
        history!(state['vote_result'].merge('kind' => 'vote'))
        if passed
          post(render(config['msg_vote_passed'], yes: yes.size, no: no.size, mission: mission_no))
        else
          state['rejects'] = state['rejects'].to_i + 1
          next_leader = players.find { |player| player.seat == order[(state['leader_index'].to_i + 1) % order.size] }
          post(render(config['msg_vote_failed'], yes: yes.size, no: no.size, rejects: state['rejects'], next: next_leader))
        end
        set_phase!('vote_result', config['pause_seconds'])
      end

      def after_vote_result!
        if state.dig('vote_result', 'passed')
          begin_mission!
        elsif state['rejects'].to_i >= reject_limit
          finish_game!('spy', 'rejects')
        else
          state['leader_index'] = state['leader_index'].to_i + 1
          begin_team!
        end
      end

      # ── 임무 ──
      def begin_mission!
        state['cards'] = {}
        set_phase!('mission', config['mission_seconds'])
      end

      def submit_card!(player, card)
        return unless state['phase'] == 'mission' && state['team'].include?(player.seat)
        return if card == 'sabotage' && role_of(player.seat) != 'spy'
        return if state['cards'].key?(player.seat.to_s)

        state['cards'][player.seat.to_s] = card
        session.save!
        resolve_mission! if state['cards'].size >= state['team'].size
      end

      def resolve_mission!(auto: false)
        state['team'].each { |seat| state['cards'][seat.to_s] ||= 'success' } if auto
        sabotage = state['cards'].values.count('sabotage')
        need = current_need
        success = sabotage < need
        # 누가 냈는지 알 수 없게 섞은 카드 순서 (화면이 한 장씩 뒤집는다)
        cards = state['cards'].values.shuffle
        result = { 'no' => mission_no, 'team' => state['team'], 'leader' => leader_seat, 'size' => state['team'].size, 'need' => need, 'sabotage' => sabotage, 'success' => success,
                   'cards' => cards, 'rejects' => state['rejects'].to_i }
        state['results'] = Array(state['results']) << result
        history!(result.merge('kind' => 'mission'))
        post(render(config[success ? 'msg_mission_success' : 'msg_mission_fail'], mission: mission_no, sabotage: sabotage))
        set_phase!('result', config['reveal_seconds'].to_i + state['team'].size)
      end

      def after_result!
        wins = state['results'].count { |result| result['success'] }
        fails = state['results'].size - wins
        if wins >= 3
          config['harry_guess'] ? begin_assassin! : finish_game!('da', 'missions')
        elsif fails >= 3
          finish_game!('spy', 'missions')
        else
          state['mission'] = mission_no + 1
          state['rejects'] = 0
          state['leader_index'] = state['leader_index'].to_i + 1
          begin_team!
        end
      end

      # ── 해리 지목 ──
      def begin_assassin!
        state['guesses'] = {}
        post(render(config['msg_assassin'], da: config['da_name'], spy: role_name('spy'), harry: role_name('harry')))
        set_phase!('assassin', config['assassin_seconds'])
      end

      def guess!(player, target)
        return unless state['phase'] == 'assassin' && role_of(player.seat) == 'spy'
        return if target.nil? || !players.map(&:seat).include?(target) || role_of(target) == 'spy'

        state['guesses'][player.seat.to_s] = target
        session.save!
        resolve_assassin! if state['guesses'].size >= spies.size
      end

      # 지목한 표가 가장 많은 사람 (동률이면 그중 무작위, 아무도 안 정했으면 첩자가 아닌 사람 중 무작위)
      def resolve_assassin!(auto: false) # rubocop:disable Lint/UnusedMethodArgument
        tally = state['guesses'].values.tally
        pool = tally.empty? ? players.map(&:seat).reject { |seat| role_of(seat) == 'spy' } : tally.select { |_, count| count == tally.values.max }.keys
        target = pool.sample
        hit = role_of(target) == 'harry'
        state['assassin'] = { 'target' => target, 'hit' => hit }
        finish_game!(hit ? 'spy' : 'da', hit ? 'guess' : 'guess_miss')
      end

      # ── 끝 ──
      def finish_game!(side, reason)
        state['winner'] = side
        state['reason'] = reason
        state['phase'] = 'finished'
        winners = players.select { |player| (role_of(player.seat) == 'spy') == (side == 'spy') }
        key = { 'rejects' => 'msg_win_spy_rejects', 'guess' => 'msg_win_spy_guess', 'guess_miss' => 'msg_da_guess' }[reason] || (side == 'spy' ? 'msg_win_spy_missions' : 'msg_win_da')
        lines = players.map { |player| "#{player.name} — #{role_name(role_of(player.seat))}" }.join("\n")
        target = players.find { |player| player.seat == state.dig('assassin', 'target') }
        finish!(winners: winners, message: render(config[key], da: config['da_name'], spy: role_name('spy'), harry: role_name('harry'), limit: reject_limit, target: target&.name.to_s, roles: lines))
      end
    end
  end
end
