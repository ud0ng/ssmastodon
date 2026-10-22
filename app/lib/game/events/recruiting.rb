# frozen_string_literal: true

module Game
  module Events
    # 운영진이 여는 모집형 이벤트 (미로·도둑 지도·비행 대결·비밀의 방). 신청 대신 모두에게 모집 툿을 올리고, 정해진 시간 동안 [참가]를 받은 뒤
    # 그 사람들로 평소 규칙대로 시작한다.
    #
    #   Game::Events::Opening.open!(kind, account)   운영진 [이벤트 열기] → 모집 툿(전체 멘션) + 컨텐츠 메뉴 알림 배지
    #   [참가] (멘션·웹 버튼)                       → join!     모집 중에만, 최대 인원까지
    #   모집 시간이 끝나면                           → recruitment_over!  최소 인원이 안 되면 닫고, 되면 시작 (prepare_event_players! 로 역할 섞기)
    #
    # 쓰는 컨텐츠: include Game::Events::Recruiting, FIELDS 에 Recruiting.fields(min:, max:) 를 더하고,
    # 개인전이 아니면 prepare_event_players! 를 고쳐 역할을 나눈다.
    module Recruiting
      F = Game::Config::Field

      # 이벤트로 열 때의 인원 설정 (컨텐츠마다 다르다). 모집 시간·참가 명령어·문구는 이벤트 설정의 공통 값 (Game::Events::Settings)
      def self.fields(min:, max:)
        [
          F.new(key: 'event_min_players', type: :integer, default: min, group: 'event', label: '이벤트 최소 인원', hint: '모집이 끝났을 때 이보다 적으면 닫힙니다'),
          F.new(key: 'event_max_players', type: :integer, default: max, group: 'event', label: '이벤트 최대 인원'),
        ]
      end

      def self.included(base)
        base.extend(ClassMethods)
      end

      module ClassMethods
        # 운영진이 이벤트로 열 수 있는 컨텐츠인가
        def event_capable?
          true
        end
      end

      def event_min_players
        [config['event_min_players'].to_i, 2].max
      end

      def event_max_players
        [config['event_max_players'].to_i, event_min_players].max
      end

      # 모집 시작: 운영진이 열면 모두에게 팔로워 공개 모집 툿 (Game::Poster 가 전체를 멘션한다), 캐릭터가 열면 툿 없음.
      # 어느 쪽이든 모두의 이벤트 메뉴에 알림 배지·소리 (Game::EventNotice.alert!) + 시간 제한
      def open!
        state.merge!('mode' => 'event', 'phase' => 'recruit')
        session.save!
        post(render(event_settings['msg_recruit'], minutes: Game::Events::Settings.join_minutes, join: Game::Events::Settings.cmd_join, min: event_min_players, max: event_max_players)) if state['staff_open']
        Game::Engine.set_deadline!(session, Game::Events::Settings.join_minutes)
        Game::EventNotice.alert!(GameCharacter.eligible_accounts.where.not(id: state['opened_by']).pluck(:id).uniq)
      end

      # 초대해 열었을 때(초대하기·테스트 플레이): 모집 없이 바로 대기방이 열린다. 툿·DM 은 보내지 않고, 초대받은 사람의 이벤트 메뉴에만 알림 배지·소리가 뜬다.
      # 초대받은 캐릭터는 대기방에 '대기중...'으로 보이고, 들어오면 [수락][거절]을 누른다 (수락하면 참가자).
      # 초대받지 않은 사람은 구경만 한다. 초대받은 모두가 수락·준비하면 카운트다운 뒤 시작한다.
      def open_invited!(accounts, test: false)
        state.merge!('mode' => 'event', 'phase' => 'invite', 'invited' => accounts.map(&:id), 'test' => test)
        session.save!
        Game::Lobby.enter!(session)
        Game::EventNotice.alert!(accounts.map(&:id) - [state['opened_by']])
      end

      def event_settings
        Game::Events::Settings.config
      end

      # 고른 참가자 번호 (모집 이벤트면 비어 있다)
      def invited
        Array(state['invited'])
      end

      # [참가] 멘션: 조용히 참가만 시킨다 (정원 초과·하루 제한·고른 참가자가 아님이면 아무 답도 하지 않는다. 웹에서는 모달로 안내한다)
      def join!(account, _status)
        return if players.any? { |player| player.account_id == account.id }

        # 초대한 이벤트의 대기방: [참가] 멘션도 웹 [수락]과 같다
        return Game::Lobby.accept_invite!(session, account) if session.lobby?
        return if invited.any? && invited.exclude?(account.id)
        return if players.size >= event_max_players || Game::Lobby.over_daily_limit?(account)

        session.players.create!(account: account, seat: (players.map(&:seat).max || -1) + 1, state: { 'accepted' => true })
        session.players.reset
        recruitment_over! if invited.any? && !session.lobby? && session.players.size >= invited.size
      end

      # 모집 시간이 끝났을 때 (Game::TimeoutWorker, 운영진 [단계 넘기기])
      def recruitment_over!
        if players.size < event_min_players
          # 인원 부족: 멘션 없이 닫고, 방에 있던 사람에게는 웹에서 모달로 알린다
          state['cancel_reason'] = "참가자가 #{event_min_players}명이 되지 않아 #{self.class.display_name}#{Game::Text.particle(self.class.display_name.to_s.strip[-1], '이가')} 취소되었습니다."
          session.update!(status: 'cancelled', finished_at: Time.now.utc, deadline_at: nil, state: state)
          return
        end

        # 모집이 끝나면 바로 시작하지 않고 대기방을 연다: 모두 준비하면 카운트다운 뒤 시작 (Game::Lobby)
        Game::Lobby.enter!(session)
      end

      # 시작 전에 역할을 섞는다. 개인전(미로·비행)은 할 일이 없다.
      def prepare_event_players!; end
    end
  end
end
