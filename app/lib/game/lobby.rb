# frozen_string_literal: true

module Game
  # 여럿이 하는 이벤트(비행 대결·미로·도둑 지도·비밀의 방)의 대기방. 모집이 끝나면 대기방(status 'lobby')이 열리고,
  # 참가자가 [준비하기]를 누른다 (운영진은 모두의 준비를 대신 바꿀 수 있다). 모두 준비하면 카운트다운 뒤 시작하고, 누구든 [취소]하면 모두 다시 준비한다.
  # 대기방 메시지·채팅은 툿이 아니라 웹 메시지(GameMessage)라서 앱에는 나가지 않는다.
  #
  #   state['lobby'] = { 'ready' => [계정 번호], 'start_at' => 카운트다운이 끝나는 때(ISO) 또는 nil }
  module Lobby
    COUNTDOWN_SECONDS = 10
    CHAT_LIMIT = 200
    CHAT_KEEP = 100

    module_function

    # 모집이 끝났을 때: 대기방을 연다
    def enter!(session)
      session.update!(status: 'lobby', deadline_at: nil)
      session.state['lobby'] = { 'ready' => [], 'start_at' => nil }
      session.save!
      note!(session, '대기방이 열렸습니다. 모두 [준비하기]를 누르면 곧 시작합니다.')
    end

    def ready_ids(session)
      Array(session.state.dig('lobby', 'ready')).map(&:to_i)
    end

    def start_at(session)
      Time.zone.parse(session.state.dig('lobby', 'start_at').to_s)
    end

    def counting?(session)
      session.lobby? && start_at(session)&.future?
    end

    def all_ready?(session)
      session.players.any? && session.players.all? { |player| ready_ids(session).include?(player.account_id) }
    end

    # 준비하기 / 준비 취소. 모두 준비했으면 카운트다운을 시작하고, 한 명이라도 취소하면 카운트다운이 멈춘다
    def set_ready!(session, account, ready)
      return unless session.lobby? && session.player_for(account)

      ids = ready_ids(session)
      ready ? ids |= [account.id] : ids -= [account.id]
      session.state['lobby'] = session.state['lobby'].merge('ready' => ids, 'start_at' => nil)
      session.save!
      begin_countdown!(session) if ready && all_ready?(session)
    end

    # 누구든 카운트다운 중에 [취소]: 준비를 모두 풀고 다시 준비하기 화면으로
    def cancel_countdown!(session, by)
      return unless counting?(session)

      session.state['lobby'] = { 'ready' => [], 'start_at' => nil }
      session.save!
      note!(session, "#{GameCharacter.for(by).display_name}님이 시작을 취소했습니다. 다시 준비해 주세요.")
    end

    def begin_countdown!(session, seconds = COUNTDOWN_SECONDS)
      at = seconds.seconds.from_now
      session.state['lobby'] = session.state['lobby'].merge('start_at' => at.iso8601(3))
      session.save!
      note!(session, "모두 준비했습니다! #{seconds}초 뒤에 시작합니다.")
      Game::LobbyStartWorker.perform_at(at, session.id, at.iso8601(3))
    end

    # 카운트다운이 끝났을 때 (Game::LobbyStartWorker) 또는 운영진이 [단계 넘기기]: 지금 시작한다
    def start!(session)
      return unless session.lobby?

      session.update!(status: 'active', deadline_at: nil)
      session.state.delete('lobby')
      session.save!
      kind = session.kind_class.new(session)
      kind.prepare_event_players!
      kind.start!
    end

    def chat!(session, account, text)
      text = text.to_s.strip[0, CHAT_LIMIT]
      return if text.blank?

      message = GameMessage.create!(session: session, kind: 'chat', author: account, text: text)
      old = session.messages.where(kind: 'chat').order(id: :desc).offset(CHAT_KEEP).pluck(:id)
      GameMessage.where(id: old).delete_all if old.any?
      message
    end

    # 대기방 시스템 안내
    def note!(session, text)
      GameMessage.create!(session: session, text: text)
    end

    # 모집 중인가 (이벤트를 열고 참가를 받는 동안): 같은 대기방 화면에 남은 모집 시간을 보여 준다
    def recruiting?(session)
      session.status == 'pending' && session.state['mode'] == 'event' && session.state['phase'] == 'recruit'
    end

    # 웹 대기방 화면: 참가자(아바타·소속·준비)와 카운트다운
    def view(session, viewer, staff:)
      kind = session.kind_class.new(session)
      at = start_at(session)
      ready = ready_ids(session)
      {
        min: kind.event_min_players,
        max: kind.event_max_players,
        countdown_seconds: COUNTDOWN_SECONDS,
        start_at: at&.future? ? at.iso8601(3) : nil,
        now: Time.current.iso8601(3),
        can_manage: staff,
        recruiting: recruiting?(session),
        recruit_ends_at: recruiting?(session) ? session.deadline_at&.iso8601(3) : nil,
        me: session.player_for(viewer)&.account_id&.to_s,
        players: session.players.map do |player|
          account = player.account
          house = player.character.group
          {
            account_id: account.id.to_s,
            acct: account.acct,
            name: player.name,
            avatar: account.avatar_static_url,
            house: house && { name: house.name, color: house.color },
            ready: ready.include?(account.id),
          }
        end,
      }
    end
  end
end
