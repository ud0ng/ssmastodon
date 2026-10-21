# frozen_string_literal: true

module Game
  # 시스템 계정을 멘션한 툿의 [명령어]를 처리한다 (Game::MentionWorker 가 부른다).
  #
  #   [젤리빈] @상대    게임 신청 (게임별 시작 명령어)
  #   [수락] [거절]     신청에 답하기
  #   [기권]            진행 중인 게임 포기
  #   [점수] [내전적]   기숙사 점수, 내 전적
  #   그 밖의 명령어는 진행 중인 게임이 처리한다 (예: [먹기/2]). 모르는 명령어는 조용히 넘긴다.
  class Engine
    COMMAND = /\[([^\[\]\n]{1,60})\]/

    # "[먹기/2]" → ["먹기", ["2"]]
    def self.parse(text)
      match = text.to_s.match(COMMAND)
      return if match.nil?

      name, *args = match[1].split('/').map(&:strip)
      [name, args]
    end

    # 시간 제한을 걸고 그 시각에 Game::TimeoutWorker 를 예약한다
    def self.set_deadline!(session, minutes)
      set_deadline_in!(session, minutes.to_i.clamp(1, 24 * 60).minutes)
    end

    # 초 단위 (레비오사 신호 등)
    def self.set_deadline_in!(session, duration)
      session.update!(deadline_at: duration.from_now)
      Game::TimeoutWorker.perform_at(session.deadline_at, session.id, session.deadline_token)
    end

    attr_reader :status, :actor

    def initialize(status)
      @status = status
      @actor = status.account
    end

    def call
      command, args = self.class.parse(status.text)
      return if command.nil?

      case command
      when common['cmd_accept'] then accept
      when common['cmd_decline'] then decline
      when common['cmd_cancel'] then cancel_invite
      when common['cmd_forfeit'] then forfeit
      when common['cmd_points'] then reply(Game::Points.board)
      when common['cmd_record'] then reply(Game::Points.record(actor))
      # 시스템봇 [도움말]: 컨텐츠 명령어 (컨텐츠 설정 > 도움말 > 시스템봇)
      when Game::Help.system_command.presence then reply(Game::Help.system_text)
      # 모바일에서 시스템 계정에 DM 으로 쓰는 특수 아이템: [사용/호울러/소문 내용] (그 밖의 [사용]은 상점 봇이 처리한다)
      when use_command then item_command(args)
      else
        pending = pending_event(command, args.first)
        return join(pending) if pending

        kind = Game::Kinds.by_command(command)
        if kind
          invite(kind, args)
        elsif (disabled = Game::Kinds.disabled_by_command(command))
          reply(Game::Text.render(common['msg_disabled'], game: disabled.display_name))
        else
          play(command, args)
        end
      end
    end

    private

    def use_command
      Game::Config.for('currency')['cmd_use'].to_s.strip.presence || '사용'
    end

    def item_command(args)
      return unless status.direct_visibility?

      # 소문내기 아이템만: 보낸 사람이 드러나지 않게 시스템 계정 DM [사용/아이템] 으로 받는다 (문구는 아이템에 정해 둔 것)
      item = GameShopItem.all.find { |each| Game::Wallet.key(each.name) == Game::Wallet.key(args.first) }
      return unless item && Game::ItemEffects.rumor_text(item.effects_list)

      reply(Game::ItemUse::Runner.from_args(actor, item.name, args.drop(1), via: :system).call)
    rescue Game::ItemUse::Error, Game::Wallet::Error => e
      reply(e.message)
    end

    def common
      @common ||= Game::Config.for('common')
    end

    def visibility
      status.direct_visibility? ? 'direct' : 'private'
    end

    def name_of(account)
      GameCharacter.for(account).display_name
    end

    def reply(text, mentions: [actor])
      Game::Poster.post(text, mentions: mentions, thread: status, visibility: visibility)
    end

    # 진행 중인 방에 있는 사람. events: true 면 이벤트(여럿이 하는 컨텐츠)방만, false 면 컨텐츠(1:1)방만, nil 이면 모두
    def open_player(account, statuses = GameSession::OPEN_STATUSES, events: nil)
      scope = GamePlayer.joins(:session).where(account: account, game_sessions: { status: statuses })
      keys = Game::Kinds.group_games.map(&:key)
      scope = events ? scope.where(game_sessions: { kind: keys }) : scope.where.not(game_sessions: { kind: keys }) unless events.nil?
      scope.order(id: :desc).first
    end

    # 게임 신청: 상대 한 명을 태그해야 한다
    def invite(kind, args = [])
      system = Game::System.account
      opponents = status.mentions.map(&:account).uniq.reject { |account| account.id == actor.id || account.id == system&.id || !account.local? }

      return reply(Game::Text.render(common['msg_no_opponent'], game: kind.display_name)) if opponents.empty?
      if opponents.size > kind.max_opponents
        key = kind.max_opponents > 1 ? 'msg_many_opponents' : 'msg_one_opponent'
        return reply(Game::Text.render(common[key], game: kind.display_name, max: kind.max_opponents))
      end
      error = kind.invite_error(opponents.size + 1, args)
      return reply(error) if error

      # 하루 신청 횟수 (컨텐츠 설정 > 룰 설정): 넘으면 신청되지 않고 이 안내가 답멘으로 간다
      limited = Game::DailyLimits.check(actor, opponents, kind: kind)
      return reply(limited) if limited

      opponent = opponents.first
      # 컨텐츠(1:1)는 컨텐츠끼리, 이벤트는 이벤트끼리 1개까지 (이벤트는 설정과 상관없이 늘 1개)
      event = kind.max_opponents > 1
      if event || common['one_game_per_person']
        busy = [actor, *opponents].find { |account| open_player(account, events: event) }
        return reply(Game::Text.render(common['msg_busy'], player: busy)) if busy
      end

      session = GameSession.transaction do
        GameSession.create!(kind: kind.key, visibility: visibility, root_status_id: status.id, state: kind.invite_state(args)).tap do |created|
          created.players.create!(account: actor, seat: 0, state: { 'accepted' => true })
          opponents.each_with_index { |account, index| created.players.create!(account: account, seat: index + 1) }
        end
      end

      # 여러 명이면 이름을 이어서 (상대 아이디·아바타 명령어는 첫 사람)
      opponent_value = opponents.size > 1 ? opponents.map { |account| GameCharacter.for(account).display_name }.join(', ') : opponent
      Game::Poster.to_session(session, Game::Text.render(
        common['msg_invite'],
        game: kind.display_name, player: actor, opponent: opponent_value,
        accept: common['cmd_accept'], decline: common['cmd_decline'], minutes: common['invite_minutes']
      ))
      self.class.set_deadline!(session, common['invite_minutes'])
    end

    # 나에게 온 신청 중 가장 최근 것
    def pending_invite
      GamePlayer.joins(:session)
                .where(account: actor, game_sessions: { status: 'pending' })
                .where("game_players.state->>'accepted' IS NULL")
                .order(id: :desc).first
    end

    def accept
      player = pending_invite
      return if player.nil?

      session = player.session
      session.with_lock do
        next unless session.status == 'pending'

        # 이벤트는 한 번에 1개만 (진행 중인 다른 이벤트가 있으면 수락할 수 없다)
        other = open_player(actor, events: true)
        if Game::Kinds.group_games.map(&:key).include?(session.kind) && other && other.game_session_id != session.id
          reply(Game::Text.render(common['msg_busy'], player: actor))
          next
        end

        follow_up!(session)
        player.update!(state: player.state.merge('accepted' => true))
        next unless session.players.reload.all? { |each| each.state['accepted'] }

        session.update!(status: 'active', deadline_at: nil)
        session.kind_class.new(session).start!
      end
    end

    def decline
      player = pending_invite
      return if player.nil?

      session = player.session
      session.with_lock do
        next unless session.status == 'pending'

        follow_up!(session)
        session.update!(status: 'cancelled', finished_at: Time.now.utc, deadline_at: nil)
        Game::Poster.to_session(session, Game::Text.render(common['msg_declined'], player: player, game: session.kind_class.display_name))
      end
    end

    # 내가 한 신청을 상대가 수락하기 전에 취소 (운영진이 연 이벤트 모집은 제외)
    def cancel_invite
      player = GamePlayer.joins(:session)
                         .where(account: actor, game_sessions: { status: 'pending' })
                         .where("game_players.state->>'accepted' = 'true'")
                         .where("COALESCE(game_sessions.state->>'mode', '') <> 'event'")
                         .order(id: :desc).first
      return if player.nil?

      session = player.session
      session.with_lock do
        next unless session.status == 'pending'

        follow_up!(session)
        session.update!(status: 'cancelled', finished_at: Time.now.utc, deadline_at: nil)
        Game::Poster.to_session(session, Game::Text.render(common['msg_cancelled'], player: player, game: session.kind_class.display_name))
      end
    end

    def forfeit
      player = open_player(actor, %w(active))
      return if player.nil?

      session = player.session
      session.with_lock do
        next unless session.status == 'active'

        follow_up!(session)
        session.kind_class.new(session).forfeit!(player)
      end
    end

    def bot_account?(account)
      common['bot_usernames'].to_s.split(/[,s]+/).map { |name| name.delete_prefix('@').downcase }.include?(account.username.downcase)
    end

    # 모집 중인 이벤트 (미로·도둑 지도·비행 대결·비밀의 방)
    # 모집 중인 이벤트 중 이 참가 명령어에 맞는 것. 여럿이 열려 있으면 [참가/컨텐츠 키]로 고르거나 모집 툿에 답한 쪽, 아니면 가장 최근 것
    def pending_event(command = nil, kind_key = nil)
      events = GameSession.where(status: %w(pending lobby)).where("state->>'mode' = 'event'").order(id: :desc).to_a.select { |event| event.status == 'pending' || Array(event.state['invited']).any? }
      events = events.select { |event| event.kind_class&.config&.dig('cmd_join') == command } if command
      events = events.select { |event| event.kind == kind_key } if kind_key.present? && events.any? { |event| event.kind == kind_key }
      replied = events.find { |event| [event.root_status_id, event.last_status_id].compact.include?(status.in_reply_to_id) }
      replied || events.first
    end

    # [참가] 모집 중인 이벤트
    def join(event)
      return if event.nil? || event.players.exists?(account_id: actor.id)
      return if bot_account?(actor) # 상점 봇이 모집 툿의 [참가]를 따라 읽어도 참가자로 넣지 않는다
      return reply(Game::Text.render(common['msg_busy'], player: actor)) if open_player(actor, events: true)

      event.with_lock { event.kind_class.new(event).join!(actor, status) if %w(pending lobby).include?(event.status) }
    end

    # 시스템의 다음 툿은 방금 명령어를 보낸 툿에 답장한다 (신청 → 수락 → 시작 → 먹기 → 결과가 한 줄로 이어지게)
    # (DM 으로 보낸 비밀 선택은 공개 스레드에 끼우지 않는다)
    def follow_up!(session)
      return if status.direct_visibility? && session.visibility != 'direct'

      session.update!(last_status_id: status.id)
    end

    # 진행 중인 게임의 명령어
    def play(command, args)
      player = open_player(actor, %w(active))
      return if player.nil?

      session = player.session
      session.with_lock do
        next unless session.status == 'active'

        follow_up!(session)
        session.kind_class.new(session).handle(session.player_for(actor), command, args, status)
      end
    end
  end
end
