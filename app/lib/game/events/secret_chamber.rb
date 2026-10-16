# frozen_string_literal: true

module Game
  module Events
    # 비밀의방 (마피아형 서버 이벤트). 여러 날에 걸쳐 진행한다.
    #
    #   [비밀의방]        참가 모집 (모집 시간이 지나면 시작, 여는 사람은 설정으로 제한 가능)
    #   [참가]            모집 중에 참가
    #   낮  [고발] @누구  살아 있는 사람끼리 투표 → 최다 득표는 퇴학 (진영 공개), 동률이면 아무도 (설정)
    #   밤  DM 으로 역할 행동
    #        배신자 [석화] @누구   배신자들이 고른 사람 중 가장 많이 고른 사람 (보호받지 않았으면 석화)
    #        오러   [조사] @누구   그 사람의 진영을 DM 으로 알려 준다 (밤마다 한 번)
    #        치유사 [보호] @누구   그날 밤 석화를 막는다 (같은 사람을 이틀 연속 보호할 수 없음)
    #        예언자 [예언]         'A 와 B 중 적어도 한 명은 배신자' 같은 모호한 예언 (밤마다 한 번)
    #   승리: 호그와트 = 배신자 전원 퇴학, 어둠 = 배신자 수 ≥ 남은 호그와트 수
    #
    # state: mode=event, phase(recruit/day/night), day, roles{seat=>role}, alive[seat], votes{seat=>seat},
    #        night{petrify{seat=>seat}, protect, investigated[seat], prophesied[seat]}, last_protect, out[{seat, role, by, day}]
    class SecretChamber < Game::Kinds::Base
      KEY = 'secret_chamber'

      ROLES = %w(traitor auror healer seer student).freeze
      DARK = %w(traitor).freeze
      # 사람이 많으면 웹 고발 버튼은 생략 (툿으로 [고발] @누구)
      MAX_ACCUSE_BUTTONS = 12

      FIELDS = (base_fields(name: '비밀의방', command: '비밀의방', points_win: 15) + [
        F.new(key: 'points_survive', type: :integer, default: 5, group: 'points', label: '살아남은 사람 추가 점수'),
        F.new(key: 'openers', type: :lines, default: [], group: 'basic', label: '열 수 있는 사람 (아이디, 줄마다 하나)', hint: '비워 두면 누구나'),
        F.new(key: 'min_players', type: :integer, default: 5, group: 'rules', label: '최소 인원'),
        F.new(key: 'traitor_percent', type: :integer, default: 25, group: 'rules', label: '배신자 비율 (%)', hint: '최소 1명'),
        F.new(key: 'tie_expels', type: :boolean, default: false, group: 'rules', label: '동률이면 무작위로 한 명 퇴학', hint: '끄면 동률일 때 아무도 퇴학되지 않는다'),
        F.new(key: 'healer_repeat', type: :boolean, default: false, group: 'rules', label: '치유사가 같은 사람을 이틀 연속 보호'),
        F.new(key: 'join_minutes', type: :integer, default: 30, group: 'time', label: '참가 모집 (분)'),
        F.new(key: 'day_minutes', type: :integer, default: 120, group: 'time', label: '낮 (토론·고발) 길이 (분)'),
        F.new(key: 'night_minutes', type: :integer, default: 60, group: 'time', label: '밤 (역할 행동) 길이 (분)'),
        F.new(key: 'role_traitor', type: :string, default: '배신자', group: 'roles', label: '배신자 이름'),
        F.new(key: 'role_auror', type: :string, default: '오러', group: 'roles', label: '오러 이름'),
        F.new(key: 'role_healer', type: :string, default: '치유사', group: 'roles', label: '치유사 이름'),
        F.new(key: 'role_seer', type: :string, default: '예언자', group: 'roles', label: '예언자 이름'),
        F.new(key: 'role_student', type: :string, default: '학생', group: 'roles', label: '학생 이름'),
        F.new(key: 'faction_light', type: :string, default: '호그와트', group: 'roles', label: '선한 진영 이름'),
        F.new(key: 'faction_dark', type: :string, default: '어둠', group: 'roles', label: '어둠 진영 이름'),
        F.new(key: 'cmd_join', type: :string, default: '참가', group: 'commands', label: '참가'),
        F.new(key: 'cmd_accuse', type: :string, default: '고발', group: 'commands', label: '고발 (낮)', hint: '[고발] @누구'),
        F.new(key: 'cmd_petrify', type: :string, default: '석화', group: 'commands', label: '석화 (배신자, 밤)'),
        F.new(key: 'cmd_investigate', type: :string, default: '조사', group: 'commands', label: '조사 (오러, 밤)'),
        F.new(key: 'cmd_protect', type: :string, default: '보호', group: 'commands', label: '보호 (치유사, 밤)'),
        F.new(key: 'cmd_prophecy', type: :string, default: '예언', group: 'commands', label: '예언 (예언자, 밤)'),
        F.new(key: 'msg_recruit', type: :text, group: 'messages', label: '모집',
              default: "%{game}의 문이 열렸습니다.\n%{minutes}분 동안 [%{join}]으로 참가해 주세요. (최소 %{min}명)\n\n참가자 중 누군가는 어둠의 편입니다…"),
        F.new(key: 'msg_joined', type: :text, group: 'messages', label: '참가 확인', default: '%{player}{이가} 참가했습니다. (지금 %{count}명)'),
        F.new(key: 'msg_cancel', type: :text, group: 'messages', label: '인원 부족', default: '참가자가 %{min}명이 되지 않아 %{game}{이가} 닫혔습니다.'),
        F.new(key: 'msg_start', type: :text, group: 'messages', label: '시작',
              default: "%{game} 시작! 참가자 %{count}명, 그중 %{traitors}명이 %{traitor}입니다.\n각자 시스템 계정이 보낸 DM 으로 역할을 확인하세요.\n\n참가자: %{names}"),
        F.new(key: 'msg_role', type: :text, group: 'messages', label: '역할 안내 (DM)',
              default: "당신의 역할은 「%{role}」입니다. (%{faction})\n%{how}"),
        F.new(key: 'msg_how_traitor', type: :text, group: 'messages', label: '배신자 할 일',
              default: "밤마다 이 DM 에 [%{petrify}] @누구 로 석화할 사람을 고르세요. 동료 %{traitor}: %{mates}"),
        F.new(key: 'msg_how_auror', type: :text, group: 'messages', label: '오러 할 일', default: '밤마다 이 DM 에 [%{investigate}] @누구 로 그 사람의 진영을 알아낼 수 있습니다.'),
        F.new(key: 'msg_how_healer', type: :text, group: 'messages', label: '치유사 할 일', default: '밤마다 이 DM 에 [%{protect}] @누구 로 그날 밤 석화를 막을 수 있습니다. (같은 사람 이틀 연속은 안 됩니다)'),
        F.new(key: 'msg_how_seer', type: :text, group: 'messages', label: '예언자 할 일', default: '밤마다 이 DM 에 [%{prophecy}] 로 모호한 예언을 받을 수 있습니다.'),
        F.new(key: 'msg_how_student', type: :text, group: 'messages', label: '학생 할 일', default: '낮마다 토론하고 [%{accuse}] @누구 로 수상한 사람을 고발하세요.'),
        F.new(key: 'msg_day', type: :text, group: 'messages', label: '낮 시작',
              default: "%{day}일째 낮\n%{minutes}분 동안 토론하고 [%{accuse}] @누구 로 고발해 주세요. 가장 많이 고발된 사람은 퇴학됩니다.\n\n남은 사람: %{names}"),
        F.new(key: 'msg_vote_ok', type: :text, group: 'messages', label: '고발 접수', default: '%{player}{이가} %{target}{을를} 고발했습니다.'),
        F.new(key: 'msg_expelled', type: :text, group: 'messages', label: '퇴학',
              default: "%{day}일째 고발 결과\n%{tally}\n\n%{target}{이가} 퇴학되었습니다. 정체는 「%{role}」(%{faction})였습니다."),
        F.new(key: 'msg_no_expel', type: :text, group: 'messages', label: '퇴학 없음', default: "%{day}일째 고발 결과\n%{tally}\n\n뜻이 모이지 않아 아무도 퇴학되지 않았습니다."),
        F.new(key: 'msg_night', type: :text, group: 'messages', label: '밤 시작',
              default: '%{day}일째 밤. %{minutes}분 동안 역할이 있는 사람은 DM 으로 움직여 주세요. 모두 조용히…'),
        F.new(key: 'msg_petrified', type: :text, group: 'messages', label: '석화',
              default: '아침이 밝았습니다. 밤사이 %{target}{이가} 석화된 채 발견되었습니다. 정체는 「%{role}」(%{faction})였습니다.'),
        F.new(key: 'msg_saved', type: :text, group: 'messages', label: '아무도 석화되지 않음', default: '아침이 밝았습니다. 지난밤은 아무 일도 없었습니다.'),
        F.new(key: 'msg_action_ok', type: :text, group: 'messages', label: '밤 행동 접수 (DM)', default: '접수했습니다: %{target}'),
        F.new(key: 'msg_investigated', type: :text, group: 'messages', label: '조사 결과 (DM)', default: '%{target}의 진영은 「%{faction}」입니다.'),
        F.new(key: 'msg_prophesied', type: :text, group: 'messages', label: '예언 (DM)', default: '%{player_a}{과와} %{player_b} 중 적어도 한 명은 %{traitor}입니다.'),
        F.new(key: 'msg_wrong_time', type: :text, group: 'messages', label: '지금은 못 함', default: '지금은 할 수 없는 행동입니다.'),
        F.new(key: 'msg_need_target', type: :text, group: 'messages', label: '대상 없음', default: '살아 있는 참가자를 @로 태그해 주세요.'),
        F.new(key: 'msg_no_repeat', type: :text, group: 'messages', label: '연속 보호 안 됨', default: '같은 사람을 이틀 연속 보호할 수 없습니다.'),
        F.new(key: 'msg_win_light', type: :text, group: 'messages', label: '선한 진영 승리',
              default: "%{game} 종료! 모든 %{traitor}{이가} 퇴학되었습니다. %{faction}의 승리!\n\n%{roles}"),
        F.new(key: 'msg_win_dark', type: :text, group: 'messages', label: '어둠 진영 승리',
              default: "%{game} 종료! %{traitor}{이가} 학교를 장악했습니다. %{faction}의 승리!\n\n%{roles}"),
      ]).freeze

      class << self
        def event?
          true
        end

        def can_open?(account)
          openers = Array(config['openers']).map { |name| name.delete_prefix('@').strip }.compact_blank
          openers.empty? || openers.include?(account.username)
        end
      end

      # 모집 시작 (Engine#open_event)
      def open!
        state.merge!('mode' => 'event', 'phase' => 'recruit')
        session.save!
        post(render(config['msg_recruit'], minutes: config['join_minutes'], join: config['cmd_join'], min: min_players))
        Game::Engine.set_deadline!(session, config['join_minutes'])
      end

      # [참가]
      def join!(account, status)
        return if players.any? { |player| player.account_id == account.id }

        player = session.players.create!(account: account, seat: (players.map(&:seat).max || -1) + 1, state: { 'accepted' => true })
        session.players.reset
        reply(status, render(config['msg_joined'], player: player, count: session.players.size))
      end

      # 모집 시간이 끝났을 때 (Game::TimeoutWorker)
      def recruitment_over!
        if players.size < min_players
          session.update!(status: 'cancelled', finished_at: Time.now.utc, deadline_at: nil)
          post(render(config['msg_cancel'], min: min_players))
          return
        end

        session.update!(status: 'active', deadline_at: nil)
        start!
      end

      def start!
        roles = deal_roles
        state.merge!('roles' => roles, 'alive' => players.map(&:seat), 'day' => 1, 'out' => [], 'votes' => {}, 'night' => {})
        session.update!(turn: 1)
        post(render(config['msg_start'], count: players.size, traitors: roles.values.count('traitor'), traitor: role_name('traitor'),
                                         names: names(players)))

        players.each { |player| dm(player, role_text(player)) }
        begin_day!
      end

      def handle(player, command, _args, status)
        action = { config['cmd_accuse'] => :accuse, config['cmd_petrify'] => :petrify, config['cmd_investigate'] => :investigate,
                   config['cmd_protect'] => :protect, config['cmd_prophecy'] => :prophecy }[command]
        return false if action.nil?
        return true unless alive?(player)

        send(action, player, status)
        true
      end

      # 단계 마감: 낮 → 투표 결과 → 밤, 밤 → 석화 결과 → 낮
      def timeout!
        state['phase'] == 'night' ? end_night! : end_day!
      end

      # 이벤트 중 [기권] = 그 자리에서 퇴장 (역할 공개)
      def forfeit!(player)
        return unless alive?(player)

        knock_out!(player.seat, 'forfeit')
        finish_if_decided! || session.save!
      end

      def card_data
        roles = state['roles'] || {}
        {
          'phase' => state['phase'],
          'day' => state['day'].to_i,
          'alive' => state['alive'] || [],
          'out' => (state['out'] || []).map { |entry| entry.merge('role_name' => role_name(entry['role']), 'faction' => faction_name(entry['role'])) },
          'votes' => tally_counts,
          'traitors' => roles.values.count('traitor'),
          'traitor_name' => role_name('traitor'),
          'faction_light' => config['faction_light'],
          'faction_dark' => config['faction_dark'],
          'winner' => state['winner'],
          'roles' => session.status == 'finished' ? roles.to_h { |seat, role| [seat, role_name(role)] } : nil,
        }
      end

      # 낮에는 살아 있는 사람이 다른 사람을 고발하는 버튼
      def card_actions
        return [] unless state['phase'] == 'day'
        return [] if alive_players.size > MAX_ACCUSE_BUTTONS

        alive_players.map do |target|
          Game::Card.action(config['cmd_accuse'], label: "#{config['cmd_accuse']}: #{target.name}", seats: (state['alive'] - [target.seat]),
                                                  style: 'secondary').merge('mention' => target.account.acct)
        end
      end

      protected

      # 공지는 살아 있는 사람만 멘션
      def post(text)
        alive = state['alive']
        mentions = alive ? players.select { |player| alive.include?(player.seat) }.map(&:account) : players.map(&:account)
        Game::Poster.to_session(session, text, mentions: mentions.presence || [], kind: self)
      end

      private

      def min_players
        [config['min_players'].to_i, 3].max
      end

      def deal_roles
        seats = players.map(&:seat).shuffle
        traitor_count = [(seats.size * config['traitor_percent'].to_i / 100.0).floor, 1].max
        traitor_count = [traitor_count, ((seats.size - 1) / 2.0).floor].min.clamp(1, seats.size - 1)
        special = %w(auror healer seer).first([seats.size - traitor_count - 1, 0].max)
        list = Array.new(traitor_count, 'traitor') + special
        list += Array.new(seats.size - list.size, 'student')
        seats.zip(list).to_h { |seat, role| [seat.to_s, role] }
      end

      def role_of(seat)
        state['roles'][seat.to_s]
      end

      def role_name(role)
        config["role_#{role}"].presence || role
      end

      def faction_name(role)
        DARK.include?(role) ? config['faction_dark'] : config['faction_light']
      end

      def alive?(player)
        Array(state['alive']).include?(player.seat)
      end

      def alive_players
        players.select { |player| Array(state['alive']).include?(player.seat) }
      end

      def names(list)
        list.map(&:name).join(', ')
      end

      def role_text(player)
        role = role_of(player.seat)
        mates = players.select { |other| other.id != player.id && role_of(other.seat) == 'traitor' }
        how = render(config["msg_how_#{role}"], petrify: config['cmd_petrify'], investigate: config['cmd_investigate'], protect: config['cmd_protect'],
                                                prophecy: config['cmd_prophecy'], accuse: config['cmd_accuse'], traitor: role_name('traitor'),
                                                mates: mates.any? ? names(mates) : '-')
        render(config['msg_role'], role: role_name(role), faction: faction_name(role), how: how)
      end

      # 이 툿에서 태그한 살아 있는 참가자 (시스템 계정·자기 자신 제외)
      def target_in(status, player, allow_self: false)
        ids = status.mentions.map(&:account_id)
        alive_players.find { |other| ids.include?(other.account_id) && (allow_self || other.id != player.id) }
      end

      def reply(status, text)
        Game::Poster.post(text, mentions: [status.account], thread: status, visibility: status.direct_visibility? ? 'direct' : session.visibility)
      end

      def begin_day!
        state['phase'] = 'day'
        state['votes'] = {}
        session.save!
        post(render(config['msg_day'], day: state['day'], minutes: config['day_minutes'], accuse: config['cmd_accuse'], names: names(alive_players)))
        Game::Engine.set_deadline!(session, config['day_minutes'])
      end

      def accuse(player, status)
        return reply(status, render(config['msg_wrong_time'])) unless state['phase'] == 'day'

        target = target_in(status, player)
        return reply(status, render(config['msg_need_target'])) if target.nil?

        state['votes'][player.seat.to_s] = target.seat
        session.save!
        reply(status, render(config['msg_vote_ok'], player: player, target: target))
      end

      # {seat => 표 수}
      def tally_counts
        (state['votes'] || {}).values.tally.transform_keys(&:to_s)
      end

      def end_day!
        counts = tally_counts
        tally = counts.sort_by { |_, count| -count }.map { |seat, count| "#{players.find { |p| p.seat.to_s == seat }&.name} #{count}표" }.join("\n").presence || '-'
        best = counts.values.max
        leaders = counts.select { |_, count| count == best }.keys
        target_seat = if leaders.size == 1
                        leaders.first
                      elsif leaders.size > 1 && config['tie_expels']
                        leaders.sample
                      end

        if target_seat
          target = players.find { |player| player.seat.to_s == target_seat }
          role = role_of(target_seat)
          knock_out!(target.seat, 'vote')
          post(render(config['msg_expelled'], day: state['day'], tally: tally, target: target, role: role_name(role), faction: faction_name(role)))
        else
          post(render(config['msg_no_expel'], day: state['day'], tally: tally))
        end
        return if finish_if_decided!

        begin_night!
      end

      def begin_night!
        state['phase'] = 'night'
        state['night'] = { 'petrify' => {}, 'protect' => nil, 'investigated' => [], 'prophesied' => [] }
        session.save!
        post(render(config['msg_night'], day: state['day'], minutes: config['night_minutes']))
        Game::Engine.set_deadline!(session, config['night_minutes'])
      end

      def night_action?(player, status, role)
        return reply(status, render(config['msg_wrong_time'])) && false unless state['phase'] == 'night'
        return false unless role_of(player.seat) == role

        require_dm!(player, status)
      end

      def petrify(player, status)
        return unless night_action?(player, status, 'traitor')

        target = target_in(status, player)
        return dm(player, render(config['msg_need_target'])) if target.nil?

        state['night']['petrify'][player.seat.to_s] = target.seat
        session.save!
        dm(player, render(config['msg_action_ok'], target: target))
      end

      def investigate(player, status)
        return unless night_action?(player, status, 'auror')
        return dm(player, render(config['msg_wrong_time'])) if state['night']['investigated'].include?(player.seat)

        target = target_in(status, player)
        return dm(player, render(config['msg_need_target'])) if target.nil?

        state['night']['investigated'] << player.seat
        session.save!
        dm(player, render(config['msg_investigated'], target: target, faction: faction_name(role_of(target.seat))))
      end

      def protect(player, status)
        return unless night_action?(player, status, 'healer')

        target = target_in(status, player, allow_self: true)
        return dm(player, render(config['msg_need_target'])) if target.nil?
        return dm(player, render(config['msg_no_repeat'])) if !config['healer_repeat'] && state['last_protect'] == target.seat

        state['night']['protect'] = target.seat
        session.save!
        dm(player, render(config['msg_action_ok'], target: target))
      end

      def prophecy(player, status)
        return unless night_action?(player, status, 'seer')
        return dm(player, render(config['msg_wrong_time'])) if state['night']['prophesied'].include?(player.seat)

        others = alive_players.reject { |other| other.id == player.id }
        traitor = others.find { |other| role_of(other.seat) == 'traitor' }
        decoy = others.reject { |other| other == traitor }.sample
        return dm(player, render(config['msg_wrong_time'])) if traitor.nil? || decoy.nil?

        state['night']['prophesied'] << player.seat
        session.save!
        a, b = [traitor, decoy].shuffle
        dm(player, render(config['msg_prophesied'], player_a: a, player_b: b, traitor: role_name('traitor')))
      end

      def end_night!
        night = state['night'] || {}
        picks = (night['petrify'] || {}).values.tally
        best = picks.values.max
        target_seat = picks.select { |_, count| count == best }.keys.sample if best
        state['last_protect'] = night['protect']

        if target_seat && target_seat != night['protect'] && Array(state['alive']).include?(target_seat)
          target = players.find { |player| player.seat == target_seat }
          role = role_of(target_seat)
          knock_out!(target_seat, 'petrify')
          post(render(config['msg_petrified'], target: target, role: role_name(role), faction: faction_name(role)))
        else
          post(render(config['msg_saved']))
        end
        return if finish_if_decided!

        state['day'] = state['day'].to_i + 1
        session.update!(turn: state['day'])
        begin_day!
      end

      def knock_out!(seat, by)
        state['alive'] = Array(state['alive']) - [seat]
        state['out'] = Array(state['out']) + [{ 'seat' => seat, 'role' => role_of(seat), 'by' => by, 'day' => state['day'] }]
      end

      # 승부가 났으면 끝내고 true
      def finish_if_decided!
        alive_roles = Array(state['alive']).map { |seat| role_of(seat) }
        dark = alive_roles.count { |role| DARK.include?(role) }
        light = alive_roles.size - dark
        side = if dark.zero?
                 'light'
               elsif dark >= light
                 'dark'
               end
        return false if side.nil?

        finish_event!(side)
        true
      end

      def finish_event!(side)
        state['winner'] = side
        state['phase'] = 'finished'
        point_lines = []
        players.each do |player|
          won = (side == 'dark') == DARK.include?(role_of(player.seat))
          player.update!(result: won ? 'win' : 'lose')
          amount = (won ? config['points_win'].to_i : 0) + (alive?(player) ? config['points_survive'].to_i : 0)
          point_lines << Game::Points.give(session, player, amount, reason: "event:#{self.class.key}") if amount.positive?
        end
        session.update!(status: 'finished', finished_at: Time.now.utc, deadline_at: nil)
        point_lines.concat(give_rewards!)

        roles = players.map { |player| "#{player.name} — #{role_name(role_of(player.seat))}" }.join("\n")
        text = render(config[side == 'dark' ? 'msg_win_dark' : 'msg_win_light'], traitor: role_name('traitor'),
                                                                                faction: side == 'dark' ? config['faction_dark'] : config['faction_light'], roles: roles)
        state['alive'] = nil # 마지막 공지는 모두에게
        post([text, *point_lines.compact].join("\n\n"))
      end
    end
  end
end
