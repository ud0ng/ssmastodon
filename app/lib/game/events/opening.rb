# frozen_string_literal: true

module Game
  module Events
    # 운영진이 [이벤트 열기] 를 눌렀을 때: 시스템 계정이 모집 툿을 올리고(등록된 모든 캐릭터를 멘션), 모집 시간 동안 모두의 컨텐츠 메뉴에 알림 배지가 뜬다.
    # 한 번에 하나만 연다. 참가는 [참가] 멘션 또는 웹 컨텐츠 화면의 참가 버튼, 모집이 끝나면 각 컨텐츠 규칙대로 시작한다.
    module Opening
      class Error < StandardError; end

      module_function

      # 열 수 있는 컨텐츠: 모집형 이벤트(미로·도둑 지도·비행 대결)와 비밀의 방
      def kinds
        Game::Kinds.all.select { |kind| kind.event? || kind.event_capable? }
      end

      def open!(kind, account)
        raise Error, '시스템 계정이 설정되지 않았습니다.' if Game::System.account.nil?
        raise Error, "#{kind.display_name}#{Game::Text.particle(kind.display_name.to_s.strip[-1], '은는')} 이벤트로 열 수 없습니다." unless kinds.include?(kind)
        raise Error, "#{kind.display_name}#{Game::Text.particle(kind.display_name.to_s.strip[-1], '은는')} 꺼져 있습니다. 먼저 켜 주세요." unless kind.enabled?
        raise Error, '이미 모집 중이거나 진행 중인 이벤트가 있습니다.' if GameSession.current_kinds.open.where("state->>'mode' = 'event'").exists?
        raise Error, "#{kind.display_name}#{Game::Text.particle(kind.display_name.to_s.strip[-1], '이가')} 이미 진행 중입니다." if GameSession.open.exists?(kind: kind.key)

        session = GameSession.create!(kind: kind.key, status: 'pending', visibility: 'private', state: { 'mode' => 'event', 'opened_by' => account.id })
        kind.new(session).open!
        session.update!(root_status_id: session.last_status_id) if session.root_status_id.nil?
        session
      end
    end
  end
end
