# frozen_string_literal: true

module Game
  module Events
    # 이벤트 공통 설정 (관리 > 시스템 > 이벤트 설정 > 설정·문구): 해금, 이벤트를 열 수 있는 사람과 유형, 동시 진행·하루 제한, 모집 시간, 참가 명령어, 공통 문구.
    # 이벤트별 설정(최소·최대 인원, 룰)은 각 컨텐츠 설정, 점수·보상은 이벤트 설정 > 설정의 표에서 고친다.
    module Settings
      F = Game::Config::Field

      FIELDS = [
        # 이벤트 해금: 끄면 화면에서 이벤트 메뉴가 사라진다 (운영진은 항상 보인다)
        F.new(key: 'event_unlock', type: :boolean, default: true, group: 'unlock', label: '이벤트 해금', hint: '끄면 사용자 화면에서 이벤트 메뉴가 사라집니다 (운영진은 항상 보입니다)'),
        # 이벤트 오픈: 이벤트를 열 수 있는 사람과 (모두일 때) 열 수 있는 유형
        F.new(key: 'event_open_by', type: :select, default: 'staff', group: 'opening', choices: [['staff', '운영진'], ['everyone', '모두']], label: '이벤트를 열 수 있는 사람',
              hint: '모두로 하면 운영진이 아닌 사람도 이벤트를 열 수 있습니다. 테스트 플레이는 운영진만 할 수 있습니다'),
        F.new(key: 'event_open_recruit', type: :boolean, default: true, group: 'opening', label: '모집 열기 허용', hint: '(모두일 때) 참가자를 모집하는 이벤트를 열 수 있습니다'),
        F.new(key: 'event_open_invite', type: :boolean, default: true, group: 'opening', label: '초대 열기 허용', hint: '(모두일 때) 참가자를 골라 초대하는 이벤트를 열 수 있습니다'),
        F.new(key: 'event_join_minutes', type: :integer, default: 30, group: 'opening', label: '참가 모집 시간 (분)', hint: '모집으로 연 이벤트에서 참가를 받는 시간'),
        # 제한
        F.new(key: 'event_concurrent_limit', type: :boolean, default: true, group: 'limits', label: '동시 진행 제한', hint: '켜면 한 사람이 한 번에 이벤트 하나에만 낄 수 있습니다 (운영진이 여는 이벤트는 여러 개 동시에 열 수 있습니다)'),
        F.new(key: 'event_daily_limit', type: :integer, default: 0, group: 'limits', label: '하루 제한 횟수', hint: '한 사람이 하루(00시 기준)에 참가할 수 있는 이벤트 횟수 (0 = 제한 없음)'),
        F.new(key: 'event_daily_reward_limit', type: :integer, default: 0, group: 'limits', label: '하루 최대 보상 획득 횟수', hint: '하루에 보상(재화·아이템)을 받는 판 수. 그 이상 하면 보상이 없습니다 (0 = 제한 없음)'),
        # 문구와 명령어: 운영진이 모집을 열 때 올리는 팔로워 공개 툿만. 참가 결과·정원 초과·하루 제한·인원 부족 취소는 멘션 없이 웹 화면(모달)으로 안내한다
        F.new(key: 'cmd_join', type: :string, default: '참가', group: 'commands', label: '이벤트 참가 명령어', hint: '[참가] 로 답하거나 이벤트 메뉴에서 참가 버튼'),
        F.new(key: 'msg_recruit', type: :text, group: 'messages', label: '이벤트 모집 (운영진이 열 때 팔로워 공개 툿)',
              default: "%{game}{이가} 열렸습니다.\n%{minutes}분 동안 [%{join}] 명령어로 참가해 주세요. (%{min}~%{max}명)"),
      ].freeze

      module_function

      def config
        Game::Config.for('events')
      end

      def unlocked?
        config['event_unlock']
      end

      def everyone_can_open?
        config['event_open_by'] == 'everyone'
      end

      # 이 사람이 열 수 있는 유형: 운영진은 모두(테스트 포함), 그 밖에는 설정한 유형만
      def open_modes(user)
        return %w(recruit pick test) if Game::Staff.web?(user)
        return [] unless unlocked? && everyone_can_open?

        { 'recruit' => config['event_open_recruit'], 'pick' => config['event_open_invite'] }.select { |_, on| on }.keys
      end

      def join_minutes
        config['event_join_minutes'].to_i.clamp(1, 24 * 60)
      end

      def cmd_join
        config['cmd_join'].presence || '참가'
      end

      def concurrent_limit?
        config['event_concurrent_limit']
      end

      def daily_limit
        config['event_daily_limit'].to_i
      end

      def daily_reward_limit
        config['event_daily_reward_limit'].to_i
      end
    end
  end
end
