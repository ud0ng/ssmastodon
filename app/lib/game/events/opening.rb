# frozen_string_literal: true

module Game
  module Events
    # 운영진이 [이벤트 열기] 를 눌렀을 때: 시스템 계정이 모집 툿을 올리고(등록된 모든 캐릭터를 멘션), 모집 시간 동안 모두의 컨텐츠 메뉴에 알림 배지가 뜬다.
    # 한 번에 하나만 연다. 참가는 [참가] 멘션 또는 웹 컨텐츠 화면의 참가 버튼, 모집이 끝나면 각 컨텐츠 규칙대로 시작한다.
    module Opening
      class Error < StandardError; end

      module_function

      # 열 수 있는 컨텐츠: 모집형 이벤트(미로·도둑 지도·비행 대결·비밀의 방)
      def kinds
        Game::Kinds.all.select(&:event_capable?)
      end

      MODES = %w(recruit pick test).freeze

      # mode: recruit(참가자 모집: 모집 툿, 모두에게 알림) / pick(고른 참가자들에게만 참가 수락 DM 툿) / test(pick 과 같지만 비공개 테스트 플레이: 목록에 안 보이고 보상·기록 없음)
      # 어느 쪽이든 모집·참가 안내만 툿이라 앱에도 보이고, 시작한 뒤의 진행·결과는 웹 화면에만 나온다.
      def open!(kind, account, mode: 'recruit', players: [])
        mode = MODES.include?(mode.to_s) ? mode.to_s : 'recruit'
        raise Error, '시스템 계정이 설정되지 않았습니다.' if Game::System.account.nil?
        raise Error, '이벤트를 열 수 있는 사람이 아닙니다.' unless Game::Events::Settings.open_modes(account.user).include?(mode)
        raise Error, "#{kind.display_name}#{Game::Text.particle(kind.display_name.to_s.strip[-1], '은는')} 이벤트로 열 수 없습니다." unless kinds.include?(kind)
        raise Error, "#{kind.display_name}#{Game::Text.particle(kind.display_name.to_s.strip[-1], '은는')} 꺼져 있습니다. 먼저 켜 주세요." unless kind.enabled?
        raise Error, '이미 다른 이벤트에 참가 중입니다.' if !Game::Staff.web?(account.user) && Game::Lobby.busy_elsewhere?(nil, account)
        return open_invited!(kind, account, players, test: mode == 'test') unless mode == 'recruit'

        session = GameSession.create!(kind: kind.key, status: 'pending', visibility: 'private', state: { 'mode' => 'event', 'opened_by' => account.id, 'staff_open' => Game::Staff.web?(account.user) })
        kind.new(session).open!
        session.update!(root_status_id: session.last_status_id) if session.root_status_id.nil?
        # 운영진이 연 이벤트의 모집 툿은 웹 타임라인에서도 숨기지 않는다 (컨텐츠 카드이지만 모두에게 알리는 글)
        GameNotice.find_or_create_by!(status_id: session.root_status_id) if session.root_status_id
        session
      end

      # 고른 사람들에게 참가 수락 DM 툿을 보낸다. 모두 수락하면 바로, 아니면 모집 시간이 끝났을 때 수락한 사람들로 시작한다
      def open_invited!(kind, account, players, test:)
        raise Error, '이 컨텐츠는 참가자를 골라 열 수 없습니다. 참가자 모집으로 열어 주세요.' unless kind.event_capable?

        players = players.uniq
        game = kind.new(GameSession.new(kind: kind.key))
        min = game.event_min_players
        max = game.event_max_players
        raise Error, "참가자를 #{min}명 이상 골라 주세요." if players.size < min
        raise Error, "참가자는 #{max}명까지 고를 수 있습니다." if players.size > max

        session = GameSession.create!(kind: kind.key, status: 'pending', visibility: test ? 'direct' : 'private', state: { 'mode' => 'event', 'opened_by' => account.id, 'staff_open' => Game::Staff.web?(account.user) })
        kind.new(session).open_invited!(players, test: test)
        session
      end
    end
  end
end
