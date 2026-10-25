# frozen_string_literal: true

module Game
  module Web
    # 비밀의 방 (웹 전용, 마피아형): 학생들 사이에 숨은 비밀의 방 주인(방주)을 찾아내는 사회적 추리 게임. 최대 진행 시간·페이즈 수가 정해져 있다.
    #
    #   운영진이 이벤트로 열어 참가를 모집한다 (미로·도둑 지도와 같다). 모집·참가 안내만 툿이고 시작한 뒤의 진행·결과는 웹 화면에만 올라간다.
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

      include Game::Events::Recruiting

      ROLES = %w(traitor auror healer seer student).freeze
      DARK = %w(traitor).freeze
      CHAT_KEEP = 400
      CHAT_LENGTH = 200
      # 사람이 많으면 웹 고발 버튼은 생략 (웹 지도 화면에서는 아바타를 눌러 고발)
      MAX_ACCUSE_BUTTONS = 12

      FIELDS = (base_fields(name: '비밀의 방', command: '비밀의방', points_win: 15) + [
        F.new(key: 'points_survive', type: :integer, default: 0, group: 'points', label: '살아남은 사람 추가 점수'),
        F.new(key: 'traitor_percent', type: :integer, default: 25, group: 'rules', label: '방주 비율 (%)', hint: '최소 1명'),
        F.new(key: 'max_phases', type: :integer, default: 8, group: 'rules', label: '최대 페이즈 수', hint: '낮 하나, 밤 하나가 각각 1페이즈. 넘으면 끝납니다'),
        F.new(key: 'total_minutes', type: :integer, default: 60, group: 'rules', label: '최대 진행 시간 (분)', hint: '시작부터 이 시간이 지나면 끝납니다'),
        F.new(key: 'limit_dark_wins', type: :boolean, default: true, group: 'rules', label: '시간·페이즈가 다 되면 어둠 진영 승리', hint: '끄면 무승부'),
        F.new(key: 'tie_expels', type: :boolean, default: false, group: 'rules', label: '동률이면 무작위로 한 명 퇴학', hint: '끄면 동률일 때 아무도 퇴학되지 않는다'),
        F.new(key: 'healer_repeat', type: :boolean, default: false, group: 'rules', label: '치유사가 같은 사람을 이틀 연속 보호'),
        F.new(key: 'day_minutes', type: :integer, default: 10, group: 'time', label: '낮 (토론·고발) 길이 (분)'),
        F.new(key: 'night_minutes', type: :integer, default: 5, group: 'time', label: '밤 (역할 행동) 길이 (분)'),
        F.new(key: 'role_traitor', type: :string, default: '방주', group: 'roles', label: '방주 이름'),
        F.new(key: 'role_auror', type: :string, default: '오러', group: 'roles', label: '오러 이름'),
        F.new(key: 'role_healer', type: :string, default: '치유사', group: 'roles', label: '치유사 이름'),
        F.new(key: 'role_seer', type: :string, default: '예언자', group: 'roles', label: '예언자 이름'),
        F.new(key: 'role_student', type: :string, default: '학생', group: 'roles', label: '학생 이름'),
        F.new(key: 'faction_light', type: :string, default: '호그와트', group: 'roles', label: '선한 진영 이름'),
        F.new(key: 'faction_dark', type: :string, default: '어둠', group: 'roles', label: '어둠 진영 이름'),
        F.new(key: 'cmd_accuse', type: :string, default: '고발', group: 'commands', label: '고발 (낮)', hint: '[고발] @누구'),
        F.new(key: 'cmd_abstain', type: :string, default: '무효', group: 'commands', label: '무효표 (낮)', hint: '[무효] 아무도 고발하지 않는다'),
        F.new(key: 'cmd_petrify', type: :string, default: '석화', group: 'commands', label: '석화 (방주, 밤)'),
        F.new(key: 'cmd_investigate', type: :string, default: '조사', group: 'commands', label: '조사 (오러, 밤)'),
        F.new(key: 'cmd_protect', type: :string, default: '보호', group: 'commands', label: '보호 (치유사, 밤)'),
        F.new(key: 'cmd_prophecy', type: :string, default: '예언', group: 'commands', label: '예언 전하기 (방주, 밤)', hint: '[예언/호그와트] @누구 처럼 사실인 예언만 전할 수 있다'),
        F.new(key: 'cmd_chat', type: :string, default: '밀담', group: 'commands', label: '방주 비밀 단톡 (방주)', hint: '[밀담/내용] 으로 방주끼리만 이야기한다'),
        F.new(key: 'msg_start', type: :text, group: 'messages', label: '시작',
              default: "%{game} 시작! 참가자 %{count}명, 그중 %{traitors}명이 %{traitor}입니다.\n각자 받은 역할 카드를 확인하세요.\n최대 %{phases}페이즈, %{total}분 안에 끝납니다.\n\n참가자: %{names}"),
        F.new(key: 'msg_role', type: :text, group: 'messages', label: '역할 안내 (DM)',
              default: "당신의 역할은 「%{role}」입니다. (%{faction})\n%{how}"),
        F.new(key: 'msg_how_traitor', type: :text, group: 'messages', label: '방주 할 일',
              default: "밤마다 [%{petrify}] @누구 로 석화할 사람을 고르고, 예언자에게 전할 예언을 정하세요. 예언은 사실인 내용만 전할 수 있습니다.\n[%{prophecy}/호그와트] @누구 · [%{prophecy}/어둠] @누구 · [%{prophecy}/역할] @누구 · [%{prophecy}/둘중] @A @B\n[%{chat}/내용] 으로 동료끼리만 상의할 수 있습니다. 동료 %{traitor}: %{mates}"),
        F.new(key: 'msg_how_auror', type: :text, group: 'messages', label: '오러 할 일', default: '밤마다 이 DM 에 [%{investigate}] @누구 로 그 사람이 %{traitor}인지 알아낼 수 있습니다.'),
        F.new(key: 'msg_how_healer', type: :text, group: 'messages', label: '치유사 할 일', default: '밤마다 이 DM 에 [%{protect}] @누구 로 그날 밤 석화를 막을 수 있습니다. (같은 사람 이틀 연속은 안 됩니다)'),
        F.new(key: 'msg_how_seer', type: :text, group: 'messages', label: '예언자 할 일', default: '밤이 끝날 때마다 %{traitor}들이 전하는 예언을 이 DM 으로 받습니다. 예언은 언제나 진실입니다.'),
        F.new(key: 'msg_how_student', type: :text, group: 'messages', label: '학생 할 일', default: '낮마다 토론하고 [%{accuse}] @누구 로 수상한 사람을 고발하세요.'),
        F.new(key: 'msg_day', type: :text, group: 'messages', label: '낮 시작',
              default: "%{day}일째 낮\n%{minutes}분 동안 토론하고 [%{accuse}] @누구 로 고발해 주세요. 가장 많이 고발된 사람은 퇴학됩니다.\n\n남은 사람: %{names}"),
        F.new(key: 'msg_vote_ok', type: :text, group: 'messages', label: '고발 접수', default: '%{player}{이가} %{target}{을를} 고발했습니다.'),
        F.new(key: 'msg_abstain_ok', type: :text, group: 'messages', label: '무효표 접수', default: '%{player}{이가} 무효표를 냈습니다.'),
        F.new(key: 'msg_expelled', type: :text, group: 'messages', label: '퇴학',
              default: "%{day}일째 고발 결과\n%{tally}\n\n%{target}{이가} 퇴학되었습니다. 정체는 「%{role}」였습니다."),
        F.new(key: 'msg_no_expel', type: :text, group: 'messages', label: '퇴학 없음', default: "%{day}일째 고발 결과\n%{tally}\n\n뜻이 모이지 않아 아무도 퇴학되지 않았습니다."),
        F.new(key: 'msg_night', type: :text, group: 'messages', label: '밤 시작',
              default: '%{day}일째 밤. %{minutes}분 동안 역할이 있는 사람만 몰래 움직입니다. 모두 조용히…'),
        F.new(key: 'msg_petrified', type: :text, group: 'messages', label: '석화',
              default: '아침이 밝았습니다. 밤사이 %{target}{이가} 석화된 채 발견되었습니다. 정체는 「%{role}」였습니다.'),
        F.new(key: 'msg_saved', type: :text, group: 'messages', label: '아무도 석화되지 않음', default: '아침이 밝았습니다. 지난밤은 아무 일도 없었습니다.'),
        F.new(key: 'msg_action_ok', type: :text, group: 'messages', label: '밤 행동 접수 (DM)', default: '접수했습니다: %{target}'),
        F.new(key: 'msg_investigated', type: :text, group: 'messages', label: '조사 결과 (DM)', default: '%{target}{은는} %{verdict}'),
        F.new(key: 'msg_prophecy_ok', type: :text, group: 'messages', label: '예언 접수 (DM, 방주)', default: '예언을 정했습니다: %{text}'),
        F.new(key: 'msg_prophesied', type: :text, group: 'messages', label: '예언 (DM, 예언자)', default: '%{day}일째 밤의 예언: %{text}'),
        F.new(key: 'msg_prophecy_none', type: :text, group: 'messages', label: '예언 없음 (DM, 예언자)', default: '%{day}일째 밤, 전해진 예언이 없습니다.'),
        F.new(key: 'msg_chat', type: :text, group: 'messages', label: '방주 단톡 전달 (DM)', default: '[밀담] %{player}: %{text}'),
        F.new(key: 'msg_wrong_time', type: :text, group: 'messages', label: '지금은 못 함', default: '지금은 할 수 없는 행동입니다.'),
        F.new(key: 'msg_need_target', type: :text, group: 'messages', label: '대상 없음', default: '살아 있는 참가자를 @로 태그해 주세요.'),
        F.new(key: 'msg_prophecy_light', type: :text, group: 'messages', label: '예언: 방주가 아님', default: '%{target}{은는} %{traitor}{이가} 아닙니다.'),
        F.new(key: 'msg_prophecy_dark', type: :text, group: 'messages', label: '예언: 방주', default: '%{target}{은는} %{traitor}입니다.'),
        F.new(key: 'msg_prophecy_role', type: :text, group: 'messages', label: '예언: 역할', default: '%{target}의 역할은 「%{role}」입니다.'),
        F.new(key: 'msg_prophecy_pair', type: :text, group: 'messages', label: '예언: 둘 중 한 명', default: '%{player_a}{과와} %{player_b} 중 적어도 한 명은 %{traitor}입니다.'),
        F.new(key: 'msg_prophecy_trio', type: :text, group: 'messages', label: '예언: 셋 중 한 명', default: '%{player_a}, %{player_b}, %{player_c} 중 적어도 한 명은 %{traitor}입니다.'),
        F.new(key: 'msg_prophecy_same', type: :text, group: 'messages', label: '예언: 같은 편', default: '%{player_a}{과와} %{player_b}{은는} 같은 편입니다.'),
        F.new(key: 'msg_prophecy_diff', type: :text, group: 'messages', label: '예언: 다른 편', default: '%{player_a}{과와} %{player_b}{은는} 서로 다른 편입니다.'),
        F.new(key: 'msg_prophecy_count', type: :text, group: 'messages', label: '예언: 남은 방주 수', default: '지금 학교에 남은 %{traitor}{은는} %{count}명입니다.'),
        F.new(key: 'msg_prophecy_sent', type: :text, group: 'messages', label: '예언은 한 번만 (DM, 방주)', default: '오늘 밤의 예언은 이미 보냈습니다.'),
        F.new(key: 'msg_prophecy_auto', type: :text, group: 'messages', label: '예언 자동 전달 (방주 밀담)', default: '시간이 다 되어 예언이 저절로 전해졌습니다: %{text}'),
        F.new(key: 'msg_petrify_over', type: :text, group: 'messages', label: '표적 고르기 끝 (DM, 방주)', default: '표적을 고르는 시간이 끝났습니다. 이제 예언을 골라 주세요.'),
        F.new(key: 'msg_prophecy_usage', type: :text, group: 'messages', label: '예언 형식 안내 (DM, 방주)',
              default: "예언 형식: [%{prophecy}/%{light}] @누구 · [%{prophecy}/%{dark}] @누구 · [%{prophecy}/역할] @누구 · [%{prophecy}/둘중] @A @B · [%{prophecy}/셋중] @A @B @C · [%{prophecy}/같은편] @A @B · [%{prophecy}/다른편] @A @B · [%{prophecy}/남은수]"),
        F.new(key: 'msg_prophecy_false', type: :text, group: 'messages', label: '거짓 예언 (DM, 방주)', default: '사실이 아닌 예언은 전할 수 없습니다. 사실에 맞는 예언만 골라 주세요.'),
        F.new(key: 'msg_need_text', type: :text, group: 'messages', label: '내용 없음', default: '내용을 함께 보내 주세요.'),
        F.new(key: 'msg_no_repeat', type: :text, group: 'messages', label: '연속 보호 안 됨', default: '같은 사람을 이틀 연속 보호할 수 없습니다.'),
        F.new(key: 'msg_limit', type: :text, group: 'messages', label: '시간·페이즈 종료', default: '%{game}의 시간이 다 되었습니다.'),
        F.new(key: 'msg_win_light', type: :text, group: 'messages', label: '선한 진영 승리',
              default: "%{game} 종료! 모든 %{traitor}{이가} 퇴학되었습니다. %{faction}의 승리!\n\n%{roles}"),
        F.new(key: 'msg_win_dark', type: :text, group: 'messages', label: '어둠 진영 승리',
              default: "%{game} 종료! %{traitor}{이가} 학교를 장악했습니다. %{faction}의 승리!\n\n%{roles}"),
        F.new(key: 'msg_draw', type: :text, group: 'messages', label: '무승부', default: "%{game} 종료! 승부가 나지 않았습니다. 무승부!\n\n%{roles}"),
      ] + Game::Events::Recruiting.fields(min: 7, max: 20)).freeze

      class << self
        def web?
          true
        end

        def event_only?
          true
        end

        # 7~20명이 하는 컨텐츠라 여럿이 하는 컨텐츠로 센다 (신청이 아니라 이벤트로 연다)
        def max_opponents
          [config['event_max_players'].to_i - 1, 2].max
        end

        # 참가하지 않은 사람도 관전한다 (운영진이 아니면 정체는 공개된 것만)
        def spectatable?
          true
        end

        # 다시 보기에서 판 전체의 대화를 보여 주니 채팅을 넉넉히 남긴다 (Game::Lobby.chat!)
        def chat_keep
          1_000
        end

        def invite_error(_total, _args = [])
          '비밀의 방은 운영진이 이벤트로 엽니다. 모집 안내를 기다려 주세요.'
        end

        # 대기실에서 운영진이 몰래 역할을 정해 둘 수 있다 (Game::Lobby, 정하지 않은 사람은 무작위)
        def lobby_roles?
          true
        end
      end

      # 대기실 운영진 화면: 고를 수 있는 역할과 정해 둔 역할 {계정 번호 => 역할} (참가자에게는 보내지 않는다)
      def lobby_roles_view
        presets = preset_roles.slice(*players.map { |player| player.account_id.to_s })
        { options: ROLES.map { |role| { key: role, name: role_name(role) } }, picks: presets }
      end

      # 운영진이 정한 역할 (빈 값이면 무작위로 되돌린다). :ok / :closed / :invalid
      def preset_role!(player, role)
        return :closed unless session.lobby? && !Game::Lobby.counting?(session)
        return :invalid if role.present? && ROLES.exclude?(role)

        presets = preset_roles.dup
        role.present? ? presets[player.account_id.to_s] = role : presets.delete(player.account_id.to_s)
        state['preset_roles'] = presets
        session.save!
        :ok
      end

      def preset_roles
        state['preset_roles'].is_a?(Hash) ? state['preset_roles'] : {}
      end

      def start!
        roles = deal_roles
        state.merge!('roles' => roles, 'alive' => players.map(&:seat), 'day' => 1, 'phase_no' => 0, 'out' => [], 'votes' => {}, 'night' => {}, 'started_at' => Time.current.iso8601,
                     'notes' => {}, 'dark_chat' => [], 'ends_at' => config['total_minutes'].to_i.clamp(1, 24 * 60).minutes.from_now.iso8601)
        session.update!(turn: 1)
        post(render(config['msg_start'], count: players.size, traitors: roles.values.count('traitor'), traitor: role_name('traitor'),
                                         phases: config['max_phases'].to_i, total: config['total_minutes'].to_i, names: names(players)))

        players.each { |player| dm(player, role_text(player)) }
        begin_day!
      end

      def handle(player, command, args, status)
        action = { config['cmd_accuse'] => :accuse, config['cmd_abstain'] => :abstain, config['cmd_petrify'] => :petrify, config['cmd_investigate'] => :investigate,
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
      # player 가 nil 이면 관전: 운영진(staff)은 모든 역할이 보이고, 참가하지 않은 다른 사람은 공개된 것(탈락자의 정체)만 본다.
      def view_for(player, staff: false)
        seat = player&.seat
        roles = state['roles'] || {}
        started = state['phase'].present? && state['phase'] != 'recruit'
        out = Array(state['out']).index_by { |entry| entry['seat'] }
        alive = players.map(&:seat) - out.keys
        role = roles[seat.to_s]
        mine_out = player && started && !alive.include?(seat)
        watching_staff = player.nil? && staff
        reveal = session.status == 'finished' || mine_out || watching_staff
        mates = player && role.present? && DARK.include?(role) ? players.select { |other| other.id != player.id && DARK.include?(role_of(other.seat)) }.map(&:seat) : []
        counts = tally_counts
        votes = state['votes'] || {}

        {
          phase: state['phase'], day: state['day'].to_i, phase_no: state['phase_no'].to_i, max_phases: config['max_phases'].to_i,
          deadline_at: session.deadline_at&.iso8601, ends_at: state['ends_at'], status: session.status,
          winner: state['winner'], me: seat, alive_me: player.present? && (!started || alive.include?(seat)), spectator: player.nil?, spectator_staff: watching_staff,
          started_at: state['started_at'], total_minutes: config['total_minutes'].to_i, day_minutes: config['day_minutes'].to_i, night_minutes: config['night_minutes'].to_i,
          faction_light: config['faction_light'], faction_dark: config['faction_dark'], traitor_name: role_name('traitor'), traitor_count: roles.values.count('traitor'),
          role_names: ROLES.to_h { |key| [key, role_name(key)] },
          players: players.map do |other|
            known = reveal || other.id == player&.id || mates.include?(other.seat)
            entry = out[other.seat]
            {
              seat: other.seat, name: other.name, account_id: other.account_id, alive: !started || alive.include?(other.seat),
              out: entry && { by: entry['by'], day: entry['day'], role_name: role_name(entry['role']), faction: faction_name(entry['role']), dark: DARK.include?(entry['role']) },
              role_name: known && roles[other.seat.to_s] ? role_name(roles[other.seat.to_s]) : nil,
              dark: known && roles[other.seat.to_s] ? DARK.include?(roles[other.seat.to_s]) : nil,
              votes: counts[other.seat.to_s].to_i,
              voted_by: votes.select { |_, target| target == other.seat }.keys.filter_map { |from| players.find { |p| p.seat.to_s == from }&.name },
              # 이 사람이 무효표를 냈는가 (고발은 공개라 무효표도 공개)
              abstained: votes[other.seat.to_s] == ABSTAIN,
            }
          end,
          my_role: role && { key: role, name: role_name(role), faction: faction_name(role), dark: DARK.include?(role), how: role_how(player), mates: mates },
          my_vote: seat && votes[seat.to_s],
          votes: votes.transform_keys(&:to_s),
          # 살아 있는 사람이 모두 고발했다 (5초 뒤 결과, 바꾸면 다시 5초)
          all_voted: all_voted?,
          # 밤: 역할이 있는 사람이 모두 행동함 (5초 뒤 아침)
          all_acted: night_done?,
          night: player && night_view(player, role),
          # 방주끼리: 이번 밤에 동료들이 석화하려고 고른 사람 {자리 => 대상 자리}
          petrify_picks: role == 'traitor' && state['phase'] == 'night' ? (state.dig('night', 'petrify') || {}) : {},
          notes: seat ? Array(state.dig('notes', seat.to_s)) : [],
          dark_chat: role == 'traitor' || (watching_staff && Array(state['dark_chat']).any?) ? Array(state['dark_chat']) : [],
          # 지금까지 일어난 일 (퇴학·석화·무사): 화면 효과와 다시 보기
          out_log: Array(state['out']).map { |entry| entry.merge('role_name' => role_name(entry['role']), 'dark' => DARK.include?(entry['role'])) },
          prophecy: role == 'traitor' ? state.dig('night', 'prophecy', 'text') : nil,
          prophecy_kinds: role == 'traitor' ? [
            { key: config['faction_light'], label: "#{role_name('traitor')}가 아니다", count: 1 },
            { key: config['faction_dark'], label: "#{role_name('traitor')}다", count: 1 },
            { key: '역할', label: '역할은 ○○다', count: 1 },
            { key: '둘중', label: "둘 중 한 명 이상이 #{role_name('traitor')}다", count: 2 },
            { key: '셋중', label: "셋 중 한 명 이상이 #{role_name('traitor')}다", count: 3 },
            { key: '같은편', label: '두 사람은 같은 편이다', count: 2 },
            { key: '다른편', label: '두 사람은 서로 다른 편이다', count: 2 },
            { key: '남은수', label: "남은 #{role_name('traitor')}는 몇 명이다", count: 0 },
          ] : [],
          # 방주의 밤: 이 시각까지 표적, 그 뒤는 예언 · 오늘 밤 예언을 보냈나 (예언자는 구슬이 빛난다)
          night_half_at: state['phase'] == 'night' && (role == 'traitor' || player.nil?) ? state.dig('night', 'half_at') : nil,
          prophecy_sent: state['phase'] == 'night' && %w(traitor seer).include?(role) && state.dig('night', 'prophecy').present?,
          seer_alive: seer_alive?,
          commands: %w(accuse abstain petrify investigate protect prophecy chat join).to_h { |key| [key, config["cmd_#{key}"]] },
          min_players: min_players, max_players: max_players,
          # 끝난 뒤에만: 다시 보기(낮·밤마다 일어난 일)와 MVP
          history: session.status == 'finished' ? Array(state['history']) : [],
          awards: awards,
          chat_log: session.status == 'finished' ? chat_log : [],
        }
      end

      # 웹 채팅: 진행 중에는 살아 있는 사람만 (탈락자는 관전만). 시작 전·끝난 뒤는 누구나
      # 전체 채팅: 진행 중에는 살아 있는 사람이 낮에만 (밤에는 모두 잠들어 방주끼리 [밀담]만 한다)
      def can_chat?(player)
        return true unless session.status == 'active' && %w(day night).include?(state['phase'])

        player.present? && alive?(player) && state['phase'] == 'day'
      end

      protected

      private

      def min_players
        [event_min_players, 3].max
      end

      def max_players
        event_max_players
      end

      # 역할 나누기: 운영진이 대기실에서 정해 둔 사람은 그 역할 그대로, 나머지는 남은 자리(방주 수·특수 역할)를 무작위로.
      # 정해 둔 역할이 원래 수보다 많으면 그대로 따르고, 방주가 한 명도 없게 되면 정하지 않은 사람(없으면 아무나) 한 명을 방주로
      def deal_roles
        seats = players.map(&:seat)
        traitor_count = [(seats.size * config['traitor_percent'].to_i / 100.0).floor, 1].max
        traitor_count = [traitor_count, ((seats.size - 1) / 2.0).floor].min.clamp(1, seats.size - 1)
        special = %w(auror healer seer).first([seats.size - traitor_count - 1, 0].max)

        presets = players.filter_map { |player| (role = preset_roles[player.account_id.to_s]) && ROLES.include?(role) ? [player.seat, role] : nil }.to_h
        free = (seats - presets.keys).shuffle
        list = Array.new([traitor_count - presets.values.count('traitor'), 0].max, 'traitor') + (special - presets.values)
        list = list.first(free.size)
        list += Array.new(free.size - list.size, 'student')
        roles = presets.merge(free.zip(list).to_h).to_h { |seat, role| [seat.to_s, role] }
        unless roles.value?('traitor')
          seat = free.first || seats.sample
          roles[seat.to_s] = 'traitor'
        end
        roles
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

      # 이 툿의 인자(계정 아이디) 또는 태그로 고른 살아 있는 참가자 (시스템 계정·자기 자신 제외)
      def target_in(status, player, allow_self: false, args: [])
        named_targets(status, args).find { |other| allow_self || other.id != player.id }
      end

      # 인자 뒤쪽(이름)과 태그에서 고른 살아 있는 참가자들 (중복 없이, 고른 순서). 첫 인자는 종류라 건너뛴다 (석화 같은 한 명 명령은 이름이 첫 인자).
      def named_targets(status, args)
        words = Array(args).map { |word| word.to_s.strip.delete_prefix('@') }.compact_blank
        found = words.filter_map { |word| alive_players.find { |other| [other.account.username, other.account.acct].include?(word) } }
        mentioned = status.mentions.map(&:account_id).filter_map { |id| alive_players.find { |other| other.account_id == id } }
        (found + mentioned).uniq
      end

      # 웹 전용이라 답은 보낸 사람에게만 가는 웹 안내 (툿이 아니다)
      def reply(status, text)
        player = players.find { |each| each.account_id == status.account.id }
        player ? dm(player, text) : nil
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
        state['phase_started_at'] = Time.current.iso8601(3)
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
        hurry_if_all_voted!
      end

      # [무효]: 아무도 고발하지 않는다 (누구의 표로도 세지 않는다)
      ABSTAIN = -1

      def abstain(player, status, _args)
        return reply(status, render(config['msg_wrong_time'])) unless state['phase'] == 'day'

        state['votes'][player.seat.to_s] = ABSTAIN
        session.save!
        reply(status, render(config['msg_abstain_ok'], player: player))
        hurry_if_all_voted!
      end

      # 살아 있는 사람이 모두 고발(무효표 포함)하면 5초 뒤 결과 (낮 시간이 남아도). 그사이 누가 바꾸면 다시 5초
      ALL_VOTED_SECONDS = 5

      def hurry_if_all_voted!
        votes = state['votes'] || {}
        return unless alive_players.all? { |each| votes.key?(each.seat.to_s) }

        Game::Engine.set_deadline_in!(session, ALL_VOTED_SECONDS.seconds)
      end

      def all_voted?
        votes = state['votes'] || {}
        state['phase'] == 'day' && alive_players.all? { |each| votes.key?(each.seat.to_s) }
      end

      # {seat => 표 수} (무효표는 빼고)
      def tally_counts
        (state['votes'] || {}).values.reject { |target| target == ABSTAIN }.tally.transform_keys(&:to_s)
      end

      def end_day!
        counts = tally_counts
        abstained = (state['votes'] || {}).values.count(ABSTAIN)
        lines = counts.sort_by { |_, count| -count }.map { |seat, count| "#{players.find { |p| p.seat.to_s == seat }&.name} #{count}표" }
        lines << "무효 #{abstained}표" if abstained.positive?
        tally = lines.join("\n").presence || '-'
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
        record_history!('phase' => 'day', 'day' => state['day'].to_i, 'votes' => (state['votes'] || {}).dup, 'out' => target_seat&.to_i)
        return if finish_if_decided!

        begin_night!
      end

      def begin_night!
        return finish_limit! if limit_reached?

        state['phase'] = 'night'
        state['phase_started_at'] = Time.current.iso8601(3)
        state['phase_no'] = state['phase_no'].to_i + 1
        state['night'] = { 'petrify' => {}, 'protect' => nil, 'investigated' => [], 'prophecy' => nil }
        session.save!
        post(render(config['msg_night'], day: state['day'], minutes: config['night_minutes']))
        set_phase_deadline!(config['night_minutes'])
        # 방주의 밤은 둘로 나뉜다: 앞 절반은 비밀의 방에서 표적, 뒤 절반은 기숙사에서 예언
        state['night']['half_at'] = (Time.current + ((session.deadline_at - Time.current) / 2)).iso8601
        session.save!
      end

      def petrify_open?
        half = state.dig('night', 'half_at')
        half.blank? || Time.zone.parse(half) > Time.current
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

      def petrify(player, status, args)
        return unless night_action?(player, status, 'traitor')
        return dm(player, render(config['msg_petrify_over'])) unless petrify_open?

        target = target_in(status, player, args: args)
        return dm(player, render(config['msg_need_target'])) if target.nil?

        state['night']['petrify'][player.seat.to_s] = target.seat
        session.save!
        dm(player, render(config['msg_action_ok'], target: target))
        hurry_if_night_done!
      end

      def investigate(player, status, args)
        return unless night_action?(player, status, 'auror')
        return dm(player, render(config['msg_wrong_time'])) if state['night']['investigated'].include?(player.seat)

        target = target_in(status, player, args: args)
        return dm(player, render(config['msg_need_target'])) if target.nil?

        state['night']['investigated'] << player.seat
        state['night']['looks'] = (state['night']['looks'] || {}).merge(player.seat.to_s => target.seat) # 다시 보기
        # 진영 대신 '방주입니다 / 방주가 아닙니다'로 알려 준다
        traitor = role_name('traitor')
        verdict = DARK.include?(role_of(target.seat)) ? "#{traitor}입니다." : "#{traitor}#{Game::Text.particle(traitor[-1], '이가')} 아닙니다."
        text = render(config['msg_investigated'], target: target, verdict: verdict, faction: faction_name(role_of(target.seat)))
        add_note!(player, text)
        session.save!
        dm(player, text)
        hurry_if_night_done!
      end

      def protect(player, status, args)
        return unless night_action?(player, status, 'healer')

        target = target_in(status, player, allow_self: true, args: args)
        return dm(player, render(config['msg_need_target'])) if target.nil?
        return dm(player, render(config['msg_no_repeat'])) if !config['healer_repeat'] && state['last_protect'] == target.seat

        state['night']['protect'] = target.seat
        session.save!
        dm(player, render(config['msg_action_ok'], target: target))
        hurry_if_night_done!
      end

      # 밤: 역할이 있는 사람(살아 있는 방주·오러·치유사)이 모두 행동하면 5초 뒤 아침 (밤 시간이 남아도). 그사이 바꾸면 다시 5초
      def night_done?
        return false unless state['phase'] == 'night'

        night = state['night'] || {}
        alive_players.all? do |each|
          case role_of(each.seat)
          when 'traitor' then (night['petrify'] || {}).key?(each.seat.to_s) && (night['prophecy'].present? || !seer_alive?)
          when 'auror' then Array(night['investigated']).include?(each.seat)
          when 'healer' then !night['protect'].nil?
          else true
          end
        end
      end

      def hurry_if_night_done!
        Game::Engine.set_deadline_in!(session, ALL_VOTED_SECONDS.seconds) if night_done?
      end

      # 예언자가 받는 예언은 언제나 진실이다. 방주는 사실에 맞는 예언만 골라 전할 수 있다 (거짓이면 시스템이 막는다).
      #   [예언/호그와트 @누구]  그 사람은 호그와트 진영 (방주가 아닐 때만)
      #   [예언/어둠 @누구]      그 사람은 방주 (방주일 때만)
      #   [예언/역할 @누구]      그 사람의 역할
      #   [예언/둘중 @A @B]      둘 중 적어도 한 명은 방주 (사실일 때만)
      # 마지막으로 정한 예언이 밤이 끝날 때 예언자에게 전해진다. 다른 방주에게도 알린다.
      def prophecy(player, status, args)
        return unless night_action?(player, status, 'traitor')

        kind = prophecy_kind(Array(args).first.to_s.strip)
        targets = named_targets(status, args)
        text, error = build_prophecy(kind, targets)
        return dm(player, render(config[error], **prophecy_words)) if error

        return dm(player, render(config['msg_prophecy_sent'])) if state.dig('night', 'prophecy').present?

        state['night']['prophecy'] = { 'text' => text, 'by' => player.seat }
        session.save!
        dm(player, render(config['msg_prophecy_ok'], text: text))
        relay_chat(player, "(#{config['cmd_prophecy']}) #{text}")
        # 보내는 순간 예언자의 구슬이 빛나고 목소리가 들린다
        deliver_prophecy!
        hurry_if_night_done!
      end

      # 밤이 끝날 때까지 예언을 보내지 않았으면 사실인 예언 하나가 저절로 전해진다 (예언은 건너뛸 수 없다)
      def auto_prophecy!
        return if state.dig('night', 'prophecy').present? || !seer_alive?

        target = alive_players.sample
        text = render(config['msg_prophecy_role'], target: target, role: role_name(role_of(target.seat)))
        state['night']['prophecy'] = { 'text' => text, 'by' => nil, 'auto' => true }
        traitor = alive_players.find { |each| role_of(each.seat) == 'traitor' }
        relay_chat(traitor, render(config['msg_prophecy_auto'], text: text)) if traitor
        deliver_prophecy!
      end

      def seer_alive?
        alive_players.any? { |each| role_of(each.seat) == 'seer' }
      end

      def prophecy_words
        { prophecy: config['cmd_prophecy'], light: config['faction_light'], dark: config['faction_dark'], traitor: role_name('traitor') }
      end

      # 예언 종류 말 → light / dark / role / pair
      def prophecy_kind(token)
        { config['faction_light'] => 'light', config['faction_dark'] => 'dark', '역할' => 'role', '둘중' => 'pair', '셋중' => 'trio', '같은편' => 'same', '다른편' => 'diff', '남은수' => 'count' }[token]
      end

      # [문구, nil] 또는 [nil, 오류 문구 키]
      def build_prophecy(kind, targets)
        first, second = targets
        case kind
        when 'light'
          return [nil, 'msg_prophecy_usage'] if first.nil?
          return [nil, 'msg_prophecy_false'] if role_of(first.seat) == 'traitor'

          [render(config['msg_prophecy_light'], target: first, traitor: role_name('traitor'), faction: config['faction_light']), nil]
        when 'dark'
          return [nil, 'msg_prophecy_usage'] if first.nil?
          return [nil, 'msg_prophecy_false'] unless role_of(first.seat) == 'traitor'

          [render(config['msg_prophecy_dark'], target: first, traitor: role_name('traitor')), nil]
        when 'role'
          return [nil, 'msg_prophecy_usage'] if first.nil?

          [render(config['msg_prophecy_role'], target: first, role: role_name(role_of(first.seat))), nil]
        when 'pair'
          return [nil, 'msg_prophecy_usage'] if second.nil?
          return [nil, 'msg_prophecy_false'] unless [first, second].any? { |other| role_of(other.seat) == 'traitor' }

          [render(config['msg_prophecy_pair'], player_a: first, player_b: second, traitor: role_name('traitor')), nil]
        when 'trio'
          third = targets[2]
          return [nil, 'msg_prophecy_usage'] if third.nil?
          return [nil, 'msg_prophecy_false'] unless [first, second, third].any? { |other| role_of(other.seat) == 'traitor' }

          [render(config['msg_prophecy_trio'], player_a: first, player_b: second, player_c: third, traitor: role_name('traitor')), nil]
        when 'same', 'diff'
          return [nil, 'msg_prophecy_usage'] if second.nil?

          same = DARK.include?(role_of(first.seat)) == DARK.include?(role_of(second.seat))
          return [nil, 'msg_prophecy_false'] unless same == (kind == 'same')

          [render(config["msg_prophecy_#{kind}"], player_a: first, player_b: second), nil]
        when 'count'
          count = alive_players.count { |other| role_of(other.seat) == 'traitor' }
          [render(config['msg_prophecy_count'], traitor: role_name('traitor'), count: count), nil]
        else
          [nil, 'msg_prophecy_usage']
        end
      end

      # 방주끼리만 하는 비밀 단톡: 다른 방주에게 DM 으로 전달하고 웹 화면에도 남긴다
      def chat(player, status, args)
        return unless role_of(player.seat) == 'traitor' && require_dm!(player, status)

        text = Array(args).join('/').strip[0, CHAT_LENGTH]
        return dm(player, render(config['msg_need_text'])) if text.blank?

        relay_chat(player, text)
      end

      def relay_chat(player, text)
        state['dark_chat'] = (Array(state['dark_chat']) + [{ 'name' => player.name, 'text' => text, 'at' => Time.current.iso8601(3) }]).last(CHAT_KEEP)
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
        out_seat = Array(state['out']).last&.then { |entry| entry['by'] == 'petrify' && entry['day'].to_i == state['day'].to_i ? entry['seat'] : nil }
        record_history!('phase' => 'night', 'day' => state['day'].to_i, 'petrify' => (night['petrify'] || {}).dup, 'protect' => night['protect'],
                        'looks' => (night['looks'] || {}).dup, 'prophecy' => night.dig('prophecy', 'text'), 'out' => out_seat)
        auto_prophecy!
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

      # 다시 보기: 낮(고발)·밤(석화·보호·조사·예언)마다 일어난 일. 끝난 뒤에만 화면에 보낸다
      def record_history!(entry)
        state['history'] = Array(state['history']) + [entry.merge('from' => state['phase_started_at'], 'to' => Time.current.iso8601(3))]
      end

      # 다시 보기: 판 전체의 대화 (전체 채팅은 GameMessage, 방주방은 state['dark_chat']). 끝난 뒤에만
      def chat_log
        names = players.index_by(&:account_id)
        public = session.messages.where(kind: 'chat').includes(:author).order(:id).map do |message|
          { name: names[message.author_id]&.name || message.author&.display_name.presence || message.author&.username.to_s, text: message.text, at: message.created_at.iso8601(3), dark: false }
        end
        dark = Array(state['dark_chat']).filter_map { |line| line['at'] && { name: line['name'], text: line['text'], at: line['at'], dark: true } }
        (public + dark).sort_by { |line| line[:at] }
      end

      # 끝난 뒤 MVP 후보 (이긴 진영 먼저). [{ key, title, text, seat, dark }]
      #   명탐정: 방주를 가장 많이 고발한 호그와트 / 날카로운 등불: 방주를 조사로 찾아낸 오러 / 수호천사: 석화를 막아 낸 치유사
      #   바실리스크의 주인: 석화를 가장 많이 성공시킨 방주 / 완벽한 위장: 고발을 가장 적게 받은 방주 / 끝까지 살아남은: 마지막까지 버틴 호그와트
      def awards
        return [] unless session.status == 'finished'

        roles = state['roles'] || {}
        dark_seats = roles.select { |_, role| DARK.include?(role) }.keys.map(&:to_i)
        history = Array(state['history'])
        days = history.select { |entry| entry['phase'] == 'day' }
        nights = history.select { |entry| entry['phase'] == 'night' }
        traitor = role_name('traitor')
        list = []

        hits = Hash.new(0)
        days.each { |entry| entry['votes'].to_h.each { |from, to| hits[from.to_i] += 1 if dark_seats.include?(to) && !dark_seats.include?(from.to_i) } }
        best = hits.max_by { |_, count| count }
        list << award('detective', '명탐정', "#{traitor}#{Game::Text.particle(traitor[-1], '을를')} #{best[1]}번 고발했습니다.", best[0]) if best

        looks = Hash.new(0)
        nights.each { |entry| entry['looks'].to_h.each { |from, to| looks[from.to_i] += 1 if dark_seats.include?(to) } }
        best = looks.max_by { |_, count| count }
        list << award('lantern', '날카로운 등불', "조사로 #{traitor}#{Game::Text.particle(traitor[-1], '을를')} #{best[1]}번 찾아냈습니다.", best[0]) if best

        saves = nights.count { |entry| entry['out'].nil? && entry['protect'] && entry['petrify'].to_h.values.include?(entry['protect']) }
        healer = roles.key('healer')
        list << award('guardian', '수호천사', "바실리스크에게서 #{saves}번 학생을 지켜 냈습니다.", healer.to_i) if healer && saves.positive?

        kills = Hash.new(0)
        nights.each { |entry| entry['petrify'].to_h.each { |from, to| kills[from.to_i] += 1 if entry['out'] && to == entry['out'] } }
        best = kills.max_by { |_, count| count }
        list << award('basilisk', '바실리스크의 주인', "#{best[1]}명을 돌로 만들었습니다.", best[0]) if best

        received = dark_seats.index_with { |seat| days.sum { |entry| entry['votes'].to_h.values.count(seat) } }
        if (sly = received.min_by { |_, count| count })
          list << award('disguise', '완벽한 위장', sly[1].zero? ? '한 번도 의심받지 않았습니다.' : "고발을 #{sly[1]}표만 받았습니다.", sly[0])
        end

        survivors = Array(state['alive']).reject { |seat| dark_seats.include?(seat) }
        list << award('survivor', '끝까지 살아남은', '마지막까지 석화되지도 퇴학되지도 않았습니다.', survivors.first) if survivors.any?

        winner_dark = state['winner'] == 'dark'
        list.compact.sort_by { |item| item[:dark] == winner_dark ? 0 : 1 }
      end

      def award(key, title, text, seat)
        return if seat.nil? || players.none? { |player| player.seat == seat }

        { key: key, title: title, text: text, seat: seat, dark: DARK.include?(role_of(seat)) }
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
          amount = 0 if side == 'draw' || session.test? # 테스트 플레이는 점수 없음
          point_lines << Game::Points.give(session, player, amount, reason: "event:#{self.class.key}") if amount.positive?
        end
        session.update!(status: 'finished', finished_at: Time.now.utc, deadline_at: nil)
        # 테스트 플레이: 점수·보상 없이 결과 안내만 (다른 컨텐츠의 finish! 와 같다)
        if session.test?
          point_lines << '(테스트 플레이라 점수와 보상은 없습니다)'
        else
          point_lines.concat(give_rewards!)
        end

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
