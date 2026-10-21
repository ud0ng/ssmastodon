# frozen_string_literal: true

module Game
  # 여럿이 하는 이벤트(비행 대결·미로·도둑 지도·비밀의 방)의 대기방. 모집이 끝나면 대기방(status 'lobby')이 열리고,
  # 참가자가 [준비하기]를 누른다 (운영진은 모두의 준비를 대신 바꿀 수 있다). 모두 준비하면 카운트다운 뒤 시작하고, 누구든 [취소]하면 모두 다시 준비한다.
  # 대기방 메시지·채팅은 툿이 아니라 웹 메시지(GameMessage)라서 앱에는 나가지 않는다.
  #
  #   state['lobby'] = { 'ready' => [계정 번호], 'start_at' => 카운트다운이 끝나는 때(ISO) 또는 nil }
  module Lobby
    COUNTDOWN_SECONDS = 5
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

    # 초대한 이벤트: 초대받은 계정 번호와 아직 수락하지 않은(대기중) 계정 번호
    def invite_ids(session)
      Array(session.state['invited']).map(&:to_i)
    end

    def waiting_ids(session)
      invite_ids(session) - session.players.map(&:account_id)
    end

    # 모두 준비했나: 참가자가 모두 준비했고, 초대받고 아직 답하지 않은 사람이 없어야 한다
    def all_ready?(session)
      session.players.any? && waiting_ids(session).empty? && session.players.all? { |player| ready_ids(session).include?(player.account_id) }
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

    # 웹에서 참가·참가 취소를 할 수 있는 때: 모집 중이거나, 대기방이면서 카운트다운 전
    def joinable?(session)
      recruiting?(session) || (session.lobby? && !counting?(session))
    end

    # 초대받은 사람이 대기방에서 [수락] / [거절] (카운트다운 전에만)
    def accept_invite!(session, account)
      return :closed unless session.lobby? && !counting?(session)
      return :not_invited unless invite_ids(session).include?(account.id)
      return :joined if session.player_for(account)
      return :full if session.players.size >= session.kind_class.new(session).event_max_players
      return :busy if busy_elsewhere?(session, account) # 멤버는 한 번에 이벤트 하나만 (끝나야 다른 이벤트)

      session.players.create!(account: account, seat: (session.players.maximum(:seat) || -1) + 1, state: { 'accepted' => true })
      session.players.reset
      note!(session, "#{GameCharacter.for(account).display_name}님이 수락했습니다.")
      :ok
    end

    def decline_invite!(session, account)
      return :closed unless session.lobby? && !counting?(session)
      return :not_invited unless invite_ids(session).include?(account.id)

      session.players.find_by(account_id: account.id)&.destroy!
      session.players.reset
      session.state['invited'] = invite_ids(session) - [account.id]
      session.state['lobby'] = session.state['lobby'].merge('ready' => ready_ids(session) - [account.id])
      session.save!
      note!(session, "#{GameCharacter.for(account).display_name}님이 거절했습니다.")
      begin_countdown!(session) if session.players.size >= session.kind_class.new(session).event_min_players && all_ready?(session)
      :ok
    end

    # 웹 [참여하기]: :ok / :joined(이미 참가) / :closed / :full / :ineligible / :busy / :invite_only
    def join!(session, account)
      return :closed unless joinable?(session)
      return :invite_only if invite_ids(session).any?
      return :joined if session.player_for(account)
      return :full if session.players.size >= session.kind_class.new(session).event_max_players
      return :ineligible unless GameCharacter.eligible_accounts.exists?(id: account.id)
      return :busy if busy_elsewhere?(session, account) # 멤버는 한 번에 이벤트 하나만 (끝나야 다른 이벤트)

      session.players.create!(account: account, seat: (session.players.maximum(:seat) || -1) + 1, state: { 'accepted' => true })
      session.players.reset
      note!(session, "#{GameCharacter.for(account).display_name}님이 참가했습니다.")
      :ok
    end

    # 웹 [참여 취소]: 시작 전에만. 남은 사람이 모두 준비한 상태가 되면 바로 카운트다운
    def leave!(session, account)
      return :closed unless joinable?(session)
      return decline_invite!(session, account) if session.lobby? && invite_ids(session).include?(account.id) # 초대한 이벤트: 취소는 거절과 같다

      player = session.player_for(account)
      return :absent if player.nil?

      player.destroy!
      session.players.reset
      if session.lobby?
        session.state['lobby'] = session.state['lobby'].merge('ready' => ready_ids(session) - [account.id])
        session.save!
      end
      note!(session, "#{GameCharacter.for(account).display_name}님이 참가를 취소했습니다.")
      begin_countdown!(session) if session.lobby? && session.players.size >= session.kind_class.new(session).event_min_players && all_ready?(session)
      :ok
    end

    # 다른 이벤트에 이미 끼어 있는가 (이벤트는 한 번에 하나)
    def busy_elsewhere?(session, account)
      keys = Game::Kinds.group_games.map(&:key)
      GamePlayer.joins(:session).where(account: account, game_sessions: { kind: keys, status: %w(pending lobby active) }).where.not(game_session_id: session.id).exists?
    end

    # 초대받고 아직 수락하지 않은 캐릭터: 대기방에 '대기중...'으로 보인다
    def waiting_view(session)
      Account.where(id: waiting_ids(session)).map do |account|
        house = GameCharacter.for(account).group
        { account_id: account.id.to_s, acct: account.acct, name: GameCharacter.for(account).display_name, avatar: account.avatar_static_url, house: house && { name: house.name, color: house.color }, ready: false, waiting: true }
      end
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
        invite: invite_ids(session).any?,
        can_respond: session.lobby? && !counting?(session) && invite_ids(session).include?(viewer.id) && session.player_for(viewer).nil?,
        can_join: joinable?(session) && invite_ids(session).empty? && session.player_for(viewer).nil? && session.players.size < kind.event_max_players && GameCharacter.eligible_accounts.exists?(id: viewer.id),
        can_leave: joinable?(session) && session.player_for(viewer).present?,
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
        end + waiting_view(session),
      }
    end
  end
end
