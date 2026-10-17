# frozen_string_literal: true

module Game
  module Events
    # 비밀의 방 (마피아형 서버 이벤트): 학생들 사이에 숨은 비밀의 방 주인(방주)을 찾아내는 사회적 추리 게임. 최대 진행 시간·페이즈 수가 정해져 있다.
    #
    #   [비밀의방]        참가 모집 (모집 시간이 지나면 시작, 여는 사람은 설정으로 제한 가능)
    #   [참가]            모집 중에 참가 (최소~최대 인원)
    #   낮  [고발] @누구  살아 있는 사람끼리 공개로 토론하고 투표 → 최다 득표는 퇴학 (진영 공개), 동률이면 아무도 (설정)
    #   밤  DM 으로 역할 행동
    #        방주   [석화] @누구   방주들이 고른 사람 중 가장 많이 고른 사람 (보호받지 않았으면 석화)
    #               [예언/내용]    예언자에게 전할 예언을 정한다 (방주끼리 상의해서)
    #               [밀담/내용]    방주끼리만 하는 비밀 단톡 (밤낮 어느 때나, 봇이 DM 으로 전달)
    #        오러   [조사] @누구   그 사람의 진영을 DM 으로 알려 준다 (밤마다 한 번)
    #        치유사 [보호] @누구   그날 밤 석화를 막는다 (같은 사람을 이틀 연속 보호할 수 없음)
    #        예언자 (능력 없음)    밤이 끝나면 방주들이 전한 예언을 DM 으로 받는다
    #   탈락자는 진영이 공개되고 관전만 한다 (웹에서 모든 역할을 볼 수 있다)
    #   승리: 호그와트 = 방주 전원 퇴학, 어둠 = 방주 수 ≥ 남은 호그와트 수. 시간·페이즈가 다 되면 어둠 승리(설정으로 무승부).
    #
    # state: mode=event, phase(recruit/day/night/finished), day, phase_no, ends_at, roles{seat=>role}, alive[seat], votes{seat=>seat},
    #        night{petrify{seat=>seat}, protect, investigated[seat], prophecy{text, by}}, last_protect, out[{seat, role, by, day}],
    #        notes{seat=>[{day, text}]}, dark_chat[{name, text}]
    class SecretChamber < Game::Kinds::Base
      KEY = 'secret_chamber'

      ROLES = %w(traitor auror healer seer student).freeze
      DARK = %w(traitor).freeze
      CHAT_KEEP = 40
      CHAT_LENGTH = 200
      # 사람이 많으면 웹 고발 버튼은 생략 (웹 지도 화면에서는 아바타를 눌러 고발)
      MAX_ACCUSE_BUTTONS = 12

      FIELDS = (base_fields(name: '비밀의 방', command: '비밀의방', points_win: 15) + [
        F.new(key: 'points_survive', type: :integer, default: 5, group: 'points', label: '살아남은 사람 추가 점수'),
        F.new(key: 'openers', type: :lines, default: [], group: 'basic', label: '열 수 있는 사람 (아이디, 줄마다 하나)', hint: '비워 두면 누구나'),
        F.new(key: 'min_players', type: :integer, default: 7, group: 'rules', label: '최소 인원'),
        F.new(key: 'max_players', type: :integer, default: 20, group: 'rules', label: '최대 인원'),
        F.new(key: 'traitor_percent', type: :integer, default: 25, group: 'rules', label: '방주 비율 (%)', hint: '최소 1명'),
        F.new(key: 'max_phases', type: :integer, default: 8, group: 'rules', label: '최대 페이즈 수', hint: '낮 하나, 밤 하나가 각각 1페이즈. 넘으면 끝납니다'),
        F.new(key: 'total_minutes', type: :integer, default: 60, group: 'rules', label: '최대 진행 시간 (분)', hint: '시작부터 이 시간이 지나면 끝납니다'),
        F.new(key: 'limit_dark_wins', type: :boolean, default: true, group: 'rules', label: '시간·페이즈가 다 되면 어둠 진영 승리', hint: '끄면 무승부'),
        F.new(key: 'tie_expels', type: :boolean, default: false, group: 'rules', label: '동률이면 무작위로 한 명 퇴학', hint: '끄면 동률일 때 아무도 퇴학되지 않는다'),
        F.new(key: 'healer_repeat', type: :boolean, default: false, group: 'rules', label: '치유사가 같은 사람을 이틀 연속 보호'),
        F.new(key: 'join_minutes', type: :integer, default: 30, group: 'time', label: '참가 모집 (분)'),
        F.new(key: 'day_minutes', type: :integer, default: 10, group: 'time', label: '낮 (토론·고발) 길이 (분)'),
        F.new(key: 'night_minutes', type: :integer, default: 5, group: 'time', label: '밤 (역할 행동) 길이 (분)'),
        F.new(key: 'role_traitor', type: :string, default: '방주', group: 'roles', label: '방주 이름'),
        F.new(key: 'role_auror', type: :string, default: '오러', group: 'roles', label: '오러 이름'),
        F.new(key: 'role_healer', type: :string, default: '치유사', group: 'roles', label: '치유사 이름'),
        F.new(key: 'role_seer', type: :string, default: '예언자', group: 'roles', label: '예언자 이름'),
        F.new(key: 'role_student', type: :string, default: '학생', group: 'roles', label: '학생 이름'),
        F.new(key: 'faction_light', type: :string, default: '호그와트', group: 'roles', label: '선한 진영 이름'),
        F.new(key: 'faction_dark', type: :string, default: '어둠', group: 'roles', label: '어둠 진영 이름'),
        F.new(key: 'cmd_join', type: :string, default: '참가', group: 'commands', label: '참가'),
        F.new(key: 'cmd_accuse', type: :string, default: '고발', group: 'commands', label: '고발 (낮)', hint: '[고발] @누구'),
        F.new(key: 'cmd_petrify', type: :string, default: '석화', group: 'commands', label: '석화 (방주, 밤)'),
        F.new(key: 'cmd_investigate', type: :string, default: '조사', group: 'commands', label: '조사 (오러, 밤)'),
        F.new(key: 'cmd_protect', type: :string, default: '보호', group: 'commands', label: '보호 (치유사, 밤)'),
        F.new(key: 'cmd_prophecy', type: :string, default: '예언', group: 'commands', label: '예언 전하기 (방주, 밤)', hint: '[예언/내용] 으로 예언자에게 전할 예언을 정한다'),
        F.new(key: 'cmd_chat', type: :string, default: '밀담', group: 'commands', label: '방주 비밀 단톡 (방주)', hint: '[밀담/내용] 으로 방주끼리만 이야기한다'),
        F.new(key: 'msg_recruit', type: :text, group: 'messages', label: '모집',
              default: "%{game}의 문이 열렸습니다.\n%{minutes}분 동안 [%{join}]으로 참가해 주세요. (%{min}~%{max}명)\n\n참가자 중 누군가는 어둠의 편입니다."),
        F.new(key: 'msg_joined', type: :text, group: 'messages', label: '참가 확인', default: '%{player}{이가} 참가했습니다. (지금 %{count}명)'),
        F.new(key: 'msg_full', type: :text, group: 'messages', label: '정원 초과', default: '%{game}은 %{max}명까지 참가할 수 있어 더 참가할 수 없습니다.'),
        F.new(key: 'msg_cancel', type: :text, group: 'messages', label: '인원 부족', default: '참가자가 %{min}명이 되지 않아 %{game}{이가} 닫혔습니다.'),
        F.new(key: 'msg_start', type: :text, group: 'messages', label: '시작',
              default: "%{game} 시작! 참가자 %{count}명, 그중 %{traitors}명이 %{traitor}입니다.\n각자 시스템 계정이 보낸 DM 으로 역할을 확인하세요. 진행 화면은 컨텐츠 방에서 볼 수 있습니다.\n최대 %{phases}페이즈, %{total}분 안에 끝납니다.\n\n참가자: %{names}"),
        F.new(key: 'msg_role', type: :text, group: 'messages', label: '역할 안내 (DM)',
              default: "당신의 역할은 「%{role}」입니다. (%{faction})\n%{how}"),
        F.new(key: 'msg_how_traitor', type: :text, group: 'messages', label: '방주 할 일',
              default: "밤마다 [%{petrify}] @누구 로 석화할 사람을 고르고, [%{prophecy}/내용] 으로 예언자에게 전할 예언을 정하세요.\n[%{chat}/내용] 으로 동료끼리만 상의할 수 있습니다. 동료 %{traitor}: %{mates}"),
        F.new(key: 'msg_how_auror', type: :text, group: 'messages', label: '오러 할 일', default: '밤마다 이 DM 에 [%{investigate}] @누구 로 그 사람의 진영을 알아낼 수 있습니다.'),
        F.new(key: 'msg_how_healer', type: :text, group: 'messages', label: '치유사 할 일', default: '밤마다 이 DM 에 [%{protect}] @누구 로 그날 밤 석화를 막을 수 있습니다. (같은 사람 이틀 연속은 안 됩니다)'),
        F.new(key: 'msg_how_seer', type: :text, group: 'messages', label: '예언자 할 일', default: '밤이 끝날 때마다 %{traitor}들이 전하는 예언을 이 DM 으로 받습니다. 예언은 진실일 수도, 거짓일 수도 있습니다.'),
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
        F.new(key: 'msg_prophecy_ok', type: :text, group: 'messages', label: '예언 접수 (DM, 방주)', default: '예언을 정했습니다: %{text}'),
        F.new(key: 'msg_prophesied', type: :text, group: 'messages', label: '예언 (DM, 예언자)', default: '%{day}일째 밤의 예언: %{text}'),
        F.new(key: 'msg_prophecy_none', type: :text, group: 'messages', label: '예언 없음 (DM, 예언자)', default: '%{day}일째 밤, 전해진 예언이 없습니다.'),
        F.new(key: 'msg_chat', type: :text, group: 'messages', label: '방주 단톡 전달 (DM)', default: '[밀담] %{player}: %{text}'),
        F.new(key: 'msg_wrong_time', type: :text, group: 'messages', label: '지금은 못 함', default: '지금은 할 수 없는 행동입니다.'),
        F.new(key: 'msg_need_target', type: :text, group: 'messages', label: '대상 없음', default: '살아 있는 참가자를 @로 태그해 주세요.'),
        F.new(key: 'msg_need_text', type: :text, group: 'messages', label: '내용 없음', default: '내용을 함께 보내 주세요.'),
        F.new(key: 'msg_no_repeat', type: :text, group: 'messages', label: '연속 보호 안 됨', default: '같은 사람을 이틀 연속 보호할 수 없습니다.'),
        F.new(key: 'msg_limit', type: :text, group: 'messages', label: '시간·페이즈 종료', default: '%{game}의 시간이 다 되었습니다.'),
        F.new(key: 'msg_win_light', type: :text, group: 'messages', label: '선한 진영 승리',
              default: "%{game} 종료! 모든 %{traitor}{이가} 퇴학되었습니다. %{faction}의 승리!\n\n%{roles}"),
        F.new(key: 'msg_win_dark', type: :text, group: 'messages', label: '어둠 진영 승리',
              default: "%{game} 종료! %{traitor}{이가} 학교를 장악했습니다. %{faction}의 승리!\n\n%{roles}"),
        F.new(key: 'msg_draw', type: :text, group: 'messages', label: '무승부', default: "%{game} 종료! 승부가 나지 않았습니다. 무승부!\n\n%{roles}"),
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
        post(render(config['msg_recruit'], minutes: config['join_minutes'], join: config['cmd_join'], min: min_players, max: max_players))
        Game::Engine.set_deadline!(session, config['join_minutes'])
      end

      # [참가]
      def join!(account, status)
        return if players.any? { |player| player.account_id == account.id }
        return reply(status, render(config['msg_full'], max: max_players)) if players.size >= max_players

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
        state.merge!('roles' => roles, 'alive' => players.map(&:seat), 'day' => 1, 'phase_no' => 0, 'out' => [], 'votes' => {}, 'night' => {},
                     'notes' => {}, 'dark_chat' => [], 'ends_at' => config['total_minutes'].to_i.clamp(1, 24 * 60).minutes.from_now.iso8601)
        session.update!(turn: 1)
        post(render(config['msg_start'], count: players.size, traitors: roles.values.count('traitor'), traitor: role_name('traitor'),
                                         phases: config['max_phases'].to_i, total: config['total_minutes'].to_i, names: names(players)))

        players.each { |player| dm(player, role_text(player)) }
        begin_day!
      end

      def handle(player, command, args, status)
        action = { config['cmd_accuse'] => :accuse, config['cmd_petrify'] => :petrify, config['cmd_investigate'] => :investigate,
                   config['cmd_protect'] => :protect, config['cmd_prophecy'] => :prophecy, config['cmd_chat'] => :chat }[command]
        return false if action.nil?
        return true unless alive?(player)

        send(action, player, status, args)
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

      # 웹 방은 아바타 원탁 화면에서 하니 입력창 위 버튼은 두지 않는다
      def card_actions
        []
      end

      # 이 사람에게 보이는 비밀의 방 (웹 진행 화면). 탈락했거나 끝났으면 모든 역할이 보인다.
      def view_for(player)
        seat = player.seat
        roles = state['roles'] || {}
        started = state['phase'].present? && state['phase'] != 'recruit'
        out = Array(state['out']).index_by { |entry| entry['seat'] }
        alive = players.map(&:seat) - out.keys
        role = roles[seat.to_s]
        mine_out = started && !alive.include?(seat)
        reveal = session.status == 'finished' || mine_out
        mates = role.present? && DARK.include?(role) ? players.select { |other| other.id != player.id && DARK.include?(role_of(other.seat)) }.map(&:seat) : []
        counts = tally_counts
        votes = state['votes'] || {}

        {
          phase: state['phase'], day: state['day'].to_i, phase_no: state['phase_no'].to_i, max_phases: config['max_phases'].to_i,
          deadline_at: session.deadline_at&.iso8601, ends_at: state['ends_at'], status: session.status,
          winner: state['winner'], me: seat, alive_me: !started || alive.include?(seat),
          players: players.map do |other|
            known = reveal || other.id == player.id || mates.include?(other.seat)
            entry = out[other.seat]
            {
              seat: other.seat, name: other.name, account_id: other.account_id, alive: !started || alive.include?(other.seat),
              out: entry && { by: entry['by'], day: entry['day'], role_name: role_name(entry['role']), faction: faction_name(entry['role']), dark: DARK.include?(entry['role']) },
              role_name: known && roles[other.seat.to_s] ? role_name(roles[other.seat.to_s]) : nil,
              dark: known && roles[other.seat.to_s] ? DARK.include?(roles[other.seat.to_s]) : nil,
              votes: counts[other.seat.to_s].to_i,
              voted_by: votes.select { |_, target| target == other.seat }.keys.filter_map { |from| players.find { |p| p.seat.to_s == from }&.name },
            }
          end,
          my_role: role && { key: role, name: role_name(role), faction: faction_name(role), dark: DARK.include?(role), how: role_how(player), mates: mates },
          my_vote: votes[seat.to_s],
          votes: votes.transform_keys(&:to_s),
          night: night_view(player, role),
          notes: Array(state.dig('notes', seat.to_s)),
          dark_chat: role == 'traitor' ? Array(state['dark_chat']) : [],
          prophecy: role == 'traitor' ? state.dig('night', 'prophecy', 'text') : nil,
          commands: %w(accuse petrify investigate protect prophecy chat join).to_h { |key| [key, config["cmd_#{key}"]] },
          min_players: min_players, max_players: max_players,
        }
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

      def max_players
        [config['max_players'].to_i, min_players].max
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

      def role_how(player)
        role = role_of(player.seat)
        mates = players.select { |other| other.id != player.id && role_of(other.seat) == 'traitor' }
        render(config["msg_how_#{role}"], petrify: config['cmd_petrify'], investigate: config['cmd_investigate'], protect: config['cmd_protect'],
                                          prophecy: config['cmd_prophecy'], chat: config['cmd_chat'], accuse: config['cmd_accuse'], traitor: role_name('traitor'),
                                          mates: mates.any? ? names(mates) : '-')
      end

      def role_text(player)
        role = role_of(player.seat)
        render(config['msg_role'], role: role_name(role), faction: faction_name(role), how: role_how(player))
      end

      # 이 툿에서 태그한 살아 있는 참가자 (시스템 계정·자기 자신 제외)
      def target_in(status, player, allow_self: false)
        ids = status.mentions.map(&:account_id)
        alive_players.find { |other| ids.include?(other.account_id) && (allow_self || other.id != player.id) }
      end

      def reply(status, text)
        Game::Poster.post(text, mentions: [status.account], thread: status, visibility: status.direct_visibility? ? 'direct' : session.visibility)
      end

      # ── 시간·페이즈 ──
      def remaining
        return nil if state['ends_at'].blank?

        Time.zone.parse(state['ends_at']) - Time.current
      end

      def limit_reached?
        state['phase_no'].to_i >= config['max_phases'].to_i || (remaining && remaining <= 0)
      end

      # 단계 시간 제한 (남은 전체 시간을 넘지 않게)
      def set_phase_deadline!(minutes)
        duration = [minutes.to_i.clamp(1, 24 * 60).minutes, [remaining.to_f, 1].max.seconds].min
        Game::Engine.set_deadline_in!(session, duration)
      end

      def begin_day!
        return finish_limit! if limit_reached?

        state['phase'] = 'day'
        state['phase_no'] = state['phase_no'].to_i + 1
        state['votes'] = {}
        session.save!
        post(render(config['msg_day'], day: state['day'], minutes: config['day_minutes'], accuse: config['cmd_accuse'], names: names(alive_players)))
        set_phase_deadline!(config['day_minutes'])
      end

      def accuse(player, status, _args)
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
        return finish_limit! if limit_reached?

        state['phase'] = 'night'
        state['phase_no'] = state['phase_no'].to_i + 1
        state['night'] = { 'petrify' => {}, 'protect' => nil, 'investigated' => [], 'prophecy' => nil }
        session.save!
        post(render(config['msg_night'], day: state['day'], minutes: config['night_minutes']))
        set_phase_deadline!(config['night_minutes'])
      end

      def night_action?(player, status, role)
        return reply(status, render(config['msg_wrong_time'])) && false unless state['phase'] == 'night'
        return false unless role_of(player.seat) == role

        require_dm!(player, status)
      end

      def add_note!(player, text)
        notes = (state['notes'] ||= {})
        (notes[player.seat.to_s] ||= []) << { 'day' => state['day'], 'text' => text }
      end

      def petrify(player, status, _args)
        return unless night_action?(player, status, 'traitor')

        target = target_in(status, player)
        return dm(player, render(config['msg_need_target'])) if target.nil?

        state['night']['petrify'][player.seat.to_s] = target.seat
        session.save!
        dm(player, render(config['msg_action_ok'], target: target))
      end

      def investigate(player, status, _args)
        return unless night_action?(player, status, 'auror')
        return dm(player, render(config['msg_wrong_time'])) if state['night']['investigated'].include?(player.seat)

        target = target_in(status, player)
        return dm(player, render(config['msg_need_target'])) if target.nil?

        state['night']['investigated'] << player.seat
        text = render(config['msg_investigated'], target: target, faction: faction_name(role_of(target.seat)))
        add_note!(player, text)
        session.save!
        dm(player, text)
      end

      def protect(player, status, _args)
        return unless night_action?(player, status, 'healer')

        target = target_in(status, player, allow_self: true)
        return dm(player, render(config['msg_need_target'])) if target.nil?
        return dm(player, render(config['msg_no_repeat'])) if !config['healer_repeat'] && state['last_protect'] == target.seat

        state['night']['protect'] = target.seat
        session.save!
        dm(player, render(config['msg_action_ok'], target: target))
      end

      # 방주가 예언자에게 전할 예언을 정한다 (마지막으로 정한 것이 전해진다). 다른 방주에게도 알린다.
      def prophecy(player, status, args)
        return unless night_action?(player, status, 'traitor')

        text = Array(args).join('/').strip[0, CHAT_LENGTH]
        return dm(player, render(config['msg_need_text'])) if text.blank?

        state['night']['prophecy'] = { 'text' => text, 'by' => player.seat }
        session.save!
        dm(player, render(config['msg_prophecy_ok'], text: text))
        relay_chat(player, "(#{config['cmd_prophecy']}) #{text}")
      end

      # 방주끼리만 하는 비밀 단톡: 다른 방주에게 DM 으로 전달하고 웹 화면에도 남긴다
      def chat(player, status, args)
        return unless role_of(player.seat) == 'traitor' && require_dm!(player, status)

        text = Array(args).join('/').strip[0, CHAT_LENGTH]
        return dm(player, render(config['msg_need_text'])) if text.blank?

        relay_chat(player, text)
      end

      def relay_chat(player, text)
        state['dark_chat'] = (Array(state['dark_chat']) + [{ 'name' => player.name, 'text' => text }]).last(CHAT_KEEP)
        session.save!
        alive_players.select { |other| other.id != player.id && role_of(other.seat) == 'traitor' }.each do |other|
          dm(other, render(config['msg_chat'], player: player, text: text))
        end
      end

      # 밤이 끝나면 예언자가 방주들이 전한 예언을 받는다
      def deliver_prophecy!
        seer = alive_players.find { |player| role_of(player.seat) == 'seer' }
        return if seer.nil?

        text = state.dig('night', 'prophecy', 'text')
        message = text.present? ? render(config['msg_prophesied'], day: state['day'], text: text) : render(config['msg_prophecy_none'], day: state['day'])
        add_note!(seer, message)
        session.save!
        dm(seer, message)
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
        deliver_prophecy!
        return if finish_if_decided!

        state['day'] = state['day'].to_i + 1
        session.update!(turn: state['day'])
        begin_day!
      end

      # 웹 화면: 지금 밤에 내가 고를 수 있는 행동과 이미 고른 사람
      def night_view(player, role)
        return nil unless state['phase'] == 'night' && Array(state['alive']).include?(player.seat)

        night = state['night'] || {}
        case role
        when 'traitor' then { kind: 'petrify', picked: night.dig('petrify', player.seat.to_s) }
        when 'auror' then { kind: 'investigate', picked: nil, used: night['investigated'].to_a.include?(player.seat) }
        when 'healer' then { kind: 'protect', picked: night['protect'], blocked: config['healer_repeat'] ? nil : state['last_protect'] }
        end
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

      # 시간이나 페이즈가 다 되었을 때
      def finish_limit!
        post(render(config['msg_limit']))
        finish_event!(config['limit_dark_wins'] ? 'dark' : 'draw')
      end

      def finish_event!(side)
        state['winner'] = side
        state['phase'] = 'finished'
        point_lines = []
        players.each do |player|
          won = side != 'draw' && (side == 'dark') == DARK.include?(role_of(player.seat))
          player.update!(result: side == 'draw' ? 'draw' : (won ? 'win' : 'lose'))
          amount = (won ? config['points_win'].to_i : 0) + (alive?(player) ? config['points_survive'].to_i : 0)
          amount = 0 if side == 'draw'
          point_lines << Game::Points.give(session, player, amount, reason: "event:#{self.class.key}") if amount.positive?
        end
        session.update!(status: 'finished', finished_at: Time.now.utc, deadline_at: nil)
        point_lines.concat(give_rewards!)

        roles = players.map { |player| "#{player.name} — #{role_name(role_of(player.seat))}" }.join("\n")
        text = if side == 'draw'
                 render(config['msg_draw'], roles: roles)
               else
                 render(config[side == 'dark' ? 'msg_win_dark' : 'msg_win_light'], traitor: role_name('traitor'),
                                                                                  faction: side == 'dark' ? config['faction_dark'] : config['faction_light'], roles: roles)
               end
        state['alive'] = nil # 마지막 공지는 모두에게
        post([text, *point_lines.compact].join("\n\n"))
      end
    end
  end
end
