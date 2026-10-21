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

      MESSAGES = {
        recruit: "%{game}{이가} 열렸습니다.\n%{minutes}분 동안 [%{join}] 명령어로 참가해 주세요. (%{min}~%{max}명)",
        joined: '%{player}{이가} 참가했습니다. (지금 %{count}명)',
        full: '%{game}은 %{max}명까지 참가할 수 있어 더 참가할 수 없습니다.',
        cancel: '참가자가 %{min}명이 되지 않아 %{game}{이가} 닫혔습니다.',
        invite: "%{game}의 참가자로 뽑혔습니다!\n%{minutes}분 안에 [%{join}] 로 답해 참가해 주세요. 시작한 뒤의 진행과 결과는 웹 컨텐츠 화면에서만 볼 수 있습니다.",
        invite_test: "[테스트 플레이] %{game}의 참가자로 뽑혔습니다. 비공개로 진행되며 보상이 존재하지 않습니다.\n%{minutes}분 안에 [%{join}] 로 답해 참가해 주세요. 진행은 웹 컨텐츠 화면에서만 볼 수 있습니다.",
        not_invited: '이번 %{game}은 고른 참가자만 참가할 수 있습니다.',
      }.freeze

      # 이벤트로 열 때의 설정: 모집 시간·인원·참가 명령어·문구 (group 'event')
      def self.fields(min:, max:)
        [
          F.new(key: 'event_join_minutes', type: :integer, default: 30, group: 'event', label: '이벤트 참가 모집 (분)', hint: '운영진이 이벤트를 열면 이 시간 동안 모두의 컨텐츠 메뉴에 알림 배지가 뜹니다'),
          F.new(key: 'event_min_players', type: :integer, default: min, group: 'event', label: '이벤트 최소 인원', hint: '모집이 끝났을 때 이보다 적으면 닫힙니다'),
          F.new(key: 'event_max_players', type: :integer, default: max, group: 'event', label: '이벤트 최대 인원'),
          F.new(key: 'cmd_join', type: :string, default: '참가', group: 'event', label: '이벤트 참가 명령어', hint: '[참가] 로 답하거나 컨텐츠 메뉴에서 참가 버튼'),
          F.new(key: 'msg_recruit', type: :text, group: 'messages', label: '이벤트 모집', default: MESSAGES[:recruit]),
          F.new(key: 'msg_joined', type: :text, group: 'messages', label: '이벤트 참가 확인', default: MESSAGES[:joined]),
          F.new(key: 'msg_full', type: :text, group: 'messages', label: '이벤트 정원 초과', default: MESSAGES[:full]),
          F.new(key: 'msg_cancel', type: :text, group: 'messages', label: '이벤트 인원 부족', default: MESSAGES[:cancel]),
          F.new(key: 'msg_invite', type: :text, group: 'messages', label: '이벤트 참가자 고르기: 참가 수락 DM', default: MESSAGES[:invite]),
          F.new(key: 'msg_invite_test', type: :text, group: 'messages', label: '이벤트 테스트 플레이: 참가 수락 DM', default: MESSAGES[:invite_test]),
          F.new(key: 'msg_not_invited', type: :text, group: 'messages', label: '이벤트 고른 참가자가 아님', default: MESSAGES[:not_invited]),
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

      # 모집 시작: 모두에게 모집 툿 (Game::Poster 가 전체를 멘션한다) + 시간 제한
      def open!
        state.merge!('mode' => 'event', 'phase' => 'recruit')
        session.save!
        post(render(config['msg_recruit'], minutes: config['event_join_minutes'], join: config['cmd_join'], min: event_min_players, max: event_max_players))
        Game::Engine.set_deadline!(session, config['event_join_minutes'])
      end

      # 운영진이 참가자를 골라 열었을 때(고르기·테스트 플레이): 고른 사람마다 DM 툿으로 참가 수락을 묻는다 (앱에도 보인다).
      # 모두 수락하면 바로, 아니면 모집 시간이 끝났을 때 수락한 사람들로 시작한다.
      def open_invited!(accounts, test: false)
        state.merge!('mode' => 'event', 'phase' => 'recruit', 'invited' => accounts.map(&:id), 'test' => test)
        session.save!
        text = render(config[test ? 'msg_invite_test' : 'msg_invite'], minutes: config['event_join_minutes'], join: config['cmd_join'])
        accounts.each { |account| Game::Poster.post(text, mentions: [account], thread: nil, visibility: 'direct') }
        Game::Engine.set_deadline!(session, config['event_join_minutes'])
      end

      # 고른 참가자 번호 (모집 이벤트면 비어 있다)
      def invited
        Array(state['invited'])
      end

      # [참가]
      def join!(account, status)
        return if players.any? { |player| player.account_id == account.id }
        return reply_to(status, render(config['msg_not_invited'])) if invited.any? && invited.exclude?(account.id)
        return reply_to(status, render(config['msg_full'], max: event_max_players)) if players.size >= event_max_players

        player = session.players.create!(account: account, seat: (players.map(&:seat).max || -1) + 1, state: { 'accepted' => true })
        session.players.reset
        reply_to(status, render(config['msg_joined'], player: player, count: session.players.size))
        recruitment_over! if invited.any? && session.players.size >= invited.size
      end

      # 모집 시간이 끝났을 때 (Game::TimeoutWorker, 운영진 [단계 넘기기])
      def recruitment_over!
        if players.size < event_min_players
          session.update!(status: 'cancelled', finished_at: Time.now.utc, deadline_at: nil)
          post_toot(render(config['msg_cancel'], min: event_min_players))
          return
        end

        # 모집이 끝나면 바로 시작하지 않고 대기방을 연다: 모두 준비하면 카운트다운 뒤 시작 (Game::Lobby)
        Game::Lobby.enter!(session)
      end

      # 시작 전에 역할을 섞는다. 개인전(미로·비행)은 할 일이 없다.
      def prepare_event_players!; end

      protected

      def reply_to(status, text)
        Game::Poster.post(text, mentions: [status.account], thread: status, visibility: status.direct_visibility? ? 'direct' : session.visibility)
      end
    end
  end
end
