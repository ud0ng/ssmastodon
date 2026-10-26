# frozen_string_literal: true

# 웹 컨텐츠 진행 화면 (/system/sessions/:id): 한 판의 시스템 툿 카드를 순서대로.
# DM 으로 진행한 판은 참가자만 본다. 팔로워 공개 판은 서버원 누구나 (서버원끼리 서로 팔로우한다).
class Api::V1::System::SessionsController < Api::BaseController
  include Api::GameGate
  include RoutingHelper

  MESSAGE_LIMIT = 200

  before_action -> { doorkeeper_authorize! :read }, only: [:show, :view]
  before_action -> { doorkeeper_authorize! :write }, only: [:move, :destroy, :ready, :cancel_start, :chat, :join, :leave, :start_now, :accept, :decline, :invite_more, :team, :role, :control]
  before_action :require_user!
  before_action :require_contents_open!
  before_action :set_session

  def show
    # 이벤트(비행 대결·도둑 지도 등) 방은 툿·카드 없이 대기방/게임방 화면만 쓴다: 무거운 툿·카드 조회를 건너뛰고 메시지는 방 전체가 함께 쓰게 잠깐 저장해 둔다
    lean = event_stage?
    events = lean ? [] : @session.events.includes(:status).order(:id)
    render json: {
      id: @session.id.to_s,
      kind: @session.kind,
      name: @session.kind_class&.display_name || @session.kind,
      status: @session.status,
      notice: @notice,
      cancel_reason: @session.status == 'cancelled' ? @session.state['cancel_reason'] : nil,
      system_acct: Game::System.username,
      root_status_id: @session.root_status_id&.to_s,
      last_status_id: @session.last_status_id&.to_s,
      player: @session.player_for(current_account).present?,
      lobby: @session.lobby? || Game::Lobby.recruiting?(@session) ? Game::Lobby.view(@session, current_account, staff: staff?) : nil,
      staff: staff?,
      messages: lean ? lean_messages : messages(events),
      events: events.map do |event|
        {
          id: event.id.to_s,
          status_id: event.status_id.to_s,
          created_at: event.created_at.iso8601,
          text: event.status&.text.to_s.gsub(/\A(@\S+\s*)+\n?/, ''),
          card: event.id == events.last&.id ? event.current_payload : event.payload.merge('live' => false),
        }
      end,
    }
  end

  # 웹 전용 컨텐츠: 내게 보이는 판 (미로 시야 등). 참가자는 자기 시야만, 관전자(미로·도둑 지도)와 끝난 판은 전체.
  def view
    player = @session.player_for(current_account)
    raise ActiveRecord::RecordNotFound if player.nil? && !@session.kind_class.spectatable? && !staff_watching?

    kind = @session.kind_class.new(@session)
    # 모집 중인 이벤트(비밀의 방 제외)는 아직 판이 없다
    recruiting = %w(pending lobby).include?(@session.status)
    view = if @session.status == 'finished'
             # 끝난 판은 더 바뀌지 않으니 사람마다 잠깐 저장해 둔다 (결과 화면을 여러 번 읽어도 계산은 한 번)
             Rails.cache.fetch(['game/finished_view', @session.id, current_account.id, @session.updated_at.to_i], expires_in: 60.seconds) { finished_view_for(kind, player) }
           else
             kind.respond_to?(:view_for) && !recruiting ? build_view(kind, player) : nil
           end
    render json: { web: @session.kind_class.web?, status: @session.status, view: view }
  end

  # 운영진만: 끝난 판의 기록과 그 툿(멘션·DM)을 모두 지운다. 진행 중인 판은 관리 화면에서 먼저 중지해야 한다.
  def destroy
    return render json: { error: 'forbidden' }, status: 403 unless current_user.can?(:manage_settings)

    count = Game::SessionPurge.call(@session)
    render json: { deleted: true, statuses: count }
  rescue Game::SessionPurge::Error => e
    render json: { error: e.message }, status: 422
  end

  # 대기방: 준비하기 / 준비 취소 (운영진은 acct 로 다른 참가자의 준비도 바꾼다)
  def ready
    account = current_account
    if params[:acct].present?
      return render json: { error: 'forbidden' }, status: 403 unless staff?

      account = Account.local.find_by(username: params[:acct].to_s.delete_prefix('@')) || (return render json: { error: 'not found' }, status: 404)
    end
    @session.with_lock { Game::Lobby.set_ready!(@session, account, ActiveModel::Type::Boolean.new.cast(params[:ready])) }
    show
  end

  JOIN_ERRORS = {
    closed: '지금은 참가하거나 취소할 수 없습니다.', full: '참가 인원이 가득 찼습니다.', ineligible: '참가할 수 없는 계정입니다.',
    busy: '이미 다른 이벤트에 참가 중입니다.', limit: '하루에 참가할 수 있는 이벤트 횟수를 넘었습니다.', absent: '참가하지 않았습니다.', invite_only: '초대받은 사람만 참가할 수 있습니다.', not_invited: '초대받지 않았습니다.'
  }.freeze

  INVITE_ERRORS = { closed: '지금은 초대할 수 없습니다.', full: '참가 인원보다 많이 초대할 수 없습니다.' }.freeze

  # 대기방·모집 중: 아직 참가하지 않은 사람이 [참여하기]
  def join
    result = @session.with_lock { Game::Lobby.join!(@session.reload, current_account) }
    return render json: { error: JOIN_ERRORS.fetch(result) }, status: 422 if JOIN_ERRORS.key?(result)

    @notice = Game::Lobby.reward_notice(current_account, @session) if result == :ok
    show
  end

  # 초대받은 사람이 대기방에서 [수락] / [거절]
  def accept
    respond_to_invite(Game::Lobby.method(:accept_invite!))
  end

  def decline
    respond_to_invite(Game::Lobby.method(:decline_invite!))
  end

  # 대기방·모집 중: [참여 취소]
  def leave
    result = @session.with_lock { Game::Lobby.leave!(@session.reload, current_account) }
    return render json: { error: JOIN_ERRORS.fetch(result) }, status: 422 if JOIN_ERRORS.key?(result)

    show
  end

  # 운영진: 모집 중인 이벤트의 [시작하기] — 모집을 끝내고 대기방 없이 바로 시작한다 (최소 인원이 되어야 한다)
  def start_now
    return render json: { error: 'forbidden' }, status: 403 unless staff?

    error = nil
    @session.with_lock do
      session = @session.reload
      kind = session.kind_class.new(session)
      if !Game::Lobby.recruiting?(session) && !(session.lobby? && Game::Lobby.invite_ids(session).any? && !Game::Lobby.counting?(session))
        error = '지금은 시작할 수 없습니다.'
      elsif session.players.size < kind.event_min_players
        error = "최소 #{kind.event_min_players}명이 있어야 시작할 수 있습니다."
      else
        if session.lobby?
          # 초대한 이벤트: 아직 답하지 않은 사람은 빼고 지금 있는 사람들로 시작
          session.state['skipped'] = Game::Lobby.waiting_ids(session) # 끝내 수락하지 않은 사람 (완료 목록에 패자처럼 보인다)
          session.state['invited'] = session.players.map(&:account_id)
          session.save!
        else
          kind.recruitment_over!
        end
        Game::Lobby.start!(session.reload)
      end
    end
    return render json: { error: error }, status: 422 if error

    show
  end

  # 초대한 이벤트(초대하기·테스트 플레이)의 대기방에 캐릭터를 더 초대한다 (실수로 거절한 사람·나중에 더해지는 사람). 운영진과 연 사람만
  def invite_more
    return render json: { error: 'forbidden' }, status: 403 unless can_invite_more?

    names = Array(params[:accts]).map { |name| name.to_s.delete_prefix('@') }.uniq
    accounts = GameCharacter.eligible_accounts.where(username: names).to_a
    return render json: { error: '초대할 수 없는 사람이 있습니다.' }, status: 422 if accounts.size != names.size || accounts.empty?

    result = @session.with_lock { Game::Lobby.invite_more!(@session.reload, accounts) }
    return render json: { error: INVITE_ERRORS.fetch(result) }, status: 422 if INVITE_ERRORS.key?(result)

    show
  end

  # 도둑 지도 대기방: 반대 팀으로 [팀 변경] (반대 팀 정원이 차면 안 된다)
  # 운영진은 account_id 로 다른 참가자의 팀을 바꿀 수 있다 (정원과 상관없이, 시작할 때 정원에 맞춰 다시 맞춘다)
  def team
    force = staff? && params[:account_id].present?
    player = force ? @session.players.find_by(account_id: params[:account_id]) : @session.player_for(current_account)
    kind = @session.kind_class
    return render json: { error: 'forbidden' }, status: 403 if player.nil? || !(kind.respond_to?(:lobby_teams?) && kind.lobby_teams?)

    result = @session.with_lock { kind.new(@session.reload).change_team!(@session.players.find(player.id), force: force) }
    return render json: { error: { full: '바꾸려는 팀의 정원이 가득 찼습니다.', closed: '지금은 팀을 바꿀 수 없습니다.' }.fetch(result) }, status: 422 unless result == :ok

    show
  end

  # 운영진: 이벤트 목록에서 오른쪽 클릭으로 다루기 (관리 화면의 진행 중 표와 같은 Game::SessionControl)
  #   advance 단계 넘기기 / draw 무승부 종료 / cancel 취소
  CONTROLS = { 'advance' => :advance!, 'draw' => :draw!, 'cancel' => :cancel! }.freeze

  def control
    return render json: { error: 'forbidden' }, status: 403 unless staff?

    action = CONTROLS[params[:op].to_s]
    return render json: { error: '없는 조작입니다.' }, status: 422 if action.nil?
    return render json: { error: '이미 끝난 판입니다.' }, status: 422 unless @session.open?

    Game::SessionControl.public_send(action, @session)
    render json: { ok: true, status: @session.reload.status }
  rescue StandardError => e
    Rails.logger.warn { "Api::V1::System::SessionsController#control: #{e.class} #{e.message}" }
    render json: { error: e.message }, status: 422
  end

  # 비밀의 방 대기방: 운영진이 참가자의 역할을 몰래 정해 둔다 (role 이 비면 무작위로 되돌림)
  def role
    player = @session.players.find_by(account_id: params[:account_id])
    kind = @session.kind_class
    return render json: { error: 'forbidden' }, status: 403 if !staff? || player.nil? || !(kind.respond_to?(:lobby_roles?) && kind.lobby_roles?)

    result = @session.with_lock { kind.new(@session.reload).preset_role!(@session.players.find(player.id), params[:role].to_s) }
    return render json: { error: { closed: '지금은 역할을 정할 수 없습니다.', invalid: '없는 역할입니다.' }.fetch(result) }, status: 422 unless result == :ok

    show
  end

  # 대기방 카운트다운 중 누구든 취소 (참가자·운영진)
  def cancel_start
    return render json: { error: 'forbidden' }, status: 403 unless @session.player_for(current_account) || staff?

    @session.with_lock { Game::Lobby.cancel_countdown!(@session, current_account) }
    show
  end

  # 채팅 (대기방): 참가자·운영진
  def chat
    player = @session.player_for(current_account)
    return render json: { error: 'forbidden' }, status: 403 unless player || staff?

    # 대기방과 웹 전용 컨텐츠 방은 끝난 뒤에도 채팅할 수 있다
    if @session.lobby? || Game::Lobby.recruiting?(@session) || (@session.web_channel? && @session.status != 'cancelled')
      # channel=team: 같은 팀끼리만 보이는 팀 채팅 (도둑 지도, 참가자만)
      kind = @session.kind_class.new(@session)
      # 비밀의 방: 진행 중에 탈락한 사람은 관전만 (채팅 안 됨)
      return show if kind.respond_to?(:can_chat?) && !kind.can_chat?(player)

      team = params[:channel] == 'team' && player ? kind.try(:team_of, player) : nil
      Game::Lobby.chat!(@session, current_account, params[:text], team: team)
    end
    show
  end

  # 웹 전용 컨텐츠: 이번 턴 행동 (미로 이동 등)
  def move
    player = my_player!
    @session.with_lock do
      raise ActiveRecord::RecordNotFound unless @session.status == 'active'

      kind = @session.kind_class.new(@session)
      kind.submit_move!(@session.player_for(current_account), params[:path], params[:stance].to_s) if kind.respond_to?(:submit_move!) && player
    end
    view
  end

  private

  def build_view(kind, player)
    # 참가자(최대 24명)의 계정·캐릭터를 한 번에 읽어 둔다 (사람마다 조회하면 쿼리가 수십 개)
    Game::Lobby.preload_characters(@session)
    # 관전하는 운영진에게만 모든 정체를 보여 주는 컨텐츠(비밀의 방)는 staff: 를 받는다
    view = kind.method(:view_for).parameters.any? { |_, name| name == :staff } ? kind.view_for(player, staff: staff?) : kind.view_for(player)
    add_avatars!(view)
    view
  end

  def finished_view_for(kind, player)
    kind.respond_to?(:view_for) ? build_view(kind, player) : nil
  end

  def respond_to_invite(action)
    result = @session.with_lock { action.call(@session.reload, current_account) }
    return render json: { error: JOIN_ERRORS.fetch(result) }, status: 422 if JOIN_ERRORS.key?(result)

    @notice = Game::Lobby.reward_notice(current_account, @session) if result == :ok
    show
  end

  # 사람 목록(players)이 있는 화면에는 아바타·계정을 붙인다 (비밀의 방 원탁)
  def add_avatars!(view)
    return unless view.is_a?(Hash) && view[:players].is_a?(Array)

    accounts = Account.where(id: view[:players].pluck(:account_id)).index_by(&:id)
    view[:players].each do |entry|
      account = accounts[entry[:account_id]]
      entry[:avatar] = account && full_asset_url(account.avatar_static_url)
      entry[:acct] = account&.acct
    end
  end

  # 컨텐츠 방(채팅) 메시지: 판 스레드의 툿 전부(신청·명령어·시스템 진행) + 내가 낀 판이면 그 사이 시스템과 주고받은 DM(비밀 선택).
  # 관전하는 사람은 스레드만 본다.
  # 이벤트 방인가 (새 무대 화면을 쓰는 컨텐츠)
  def event_stage?
    Game::Kinds.group_games.map(&:key).include?(@session.kind)
  end

  # 방 전체가 같이 쓰는 메시지 목록(카드 없이)을 2초 동안 한 번만 만든다. 사람마다 달라지는 것(내 글·비밀 안내·팀 채팅)만 따로 거른다.
  def lean_messages
    last_id = @session.messages.maximum(:id).to_i
    rows = Rails.cache.fetch(['game/lean_messages', @session.id, last_id, @session.status], expires_in: 2.seconds, race_condition_ttl: 3.seconds) { build_lean_rows }
    my_team = team_of_viewer
    spectator = @session.player_for(current_account).nil?
    rows.filter_map do |row|
      next if row[:recipient_id] && row[:recipient_id] != current_account.id
      next if row[:chat] && row[:team].present? && row[:team] != my_team && !spectator && @session.status != 'finished'

      row.except(:recipient_id, :author_id).merge(mine: row[:chat] && row[:author_id] == current_account.id)
    end
  end

  def build_lean_rows
    system = Game::System.account
    messages = @session.messages.includes(:author).order(:id).last(MESSAGE_LIMIT)
    authors = messages.filter_map(&:author).uniq
    names = GameCharacter.where(account_id: authors.map(&:id)).index_by(&:account_id)
    messages.map do |message|
      speaker = message.chat? ? message.author : system
      {
        id: "m#{message.id}", system: !message.chat?, chat: message.chat?, mine: false, secret: message.secret?,
        name: speaker ? (names[speaker.id]&.display_name || speaker.display_name.presence || speaker.username) : '',
        acct: speaker&.acct.to_s, avatar: speaker ? full_asset_url(speaker.avatar_static_url) : '', account_id: speaker&.id&.to_s,
        text: message.text, created_at: message.created_at.iso8601,
        team: message.chat? && message.payload.is_a?(Hash) ? message.payload['team'] : nil, card: nil,
        recipient_id: message.account_id, author_id: message.author_id
      }
    end
  end

  def messages(events)
    (status_messages(events) + web_messages).sort_by { |message| message[:created_at] }.last(MESSAGE_LIMIT)
  end

  # 웹 전용 컨텐츠의 진행 메시지 (툿이 아니다): 판 전체 메시지 + 내게만 온 비밀 안내
  def web_messages
    system = Game::System.account
    scope = @session.messages.where(account_id: [nil, current_account.id]).order(:id).last(MESSAGE_LIMIT)
    my_team = team_of_viewer
    spectator = @session.player_for(current_account).nil? # 구경하는 사람은 모든 팀 채팅이 보인다
    scope = scope.reject { |message| message.chat? && message.payload.is_a?(Hash) && message.payload['team'].present? && message.payload['team'] != my_team && !spectator && @session.status != 'finished' }
    scope.map do |message|
      speaker = message.chat? ? message.author : system
      {
        id: "m#{message.id}",
        system: !message.chat?,
        chat: message.chat?,
        mine: message.chat? && message.author_id == current_account.id,
        secret: message.secret?,
        name: speaker ? GameCharacter.for(speaker).display_name : '',
        acct: speaker&.acct.to_s,
        avatar: speaker ? full_asset_url(speaker.avatar_static_url) : '',
        account_id: speaker&.id&.to_s,
        text: message.text,
        created_at: message.created_at.iso8601,
        team: message.chat? && message.payload.is_a?(Hash) ? message.payload['team'] : nil,
        card: message.chat? || message.secret? || message.payload.blank? ? nil : message.current_payload,
      }
    end
  end

  def status_messages(events)
    root = Status.find_by(id: @session.root_status_id)
    return [] if root.nil?

    # 신청 툿과 그 아래로 이어진 답만 (신청 툿이 남의 대화 안에 있으면 같은 대화의 다른 답은 이 판과 상관없다)
    statuses = thread_from(root, Status.where(conversation_id: root.conversation_id, id: root.id..).includes(:account).reorder(:id).to_a)
    statuses += secret_statuses if @session.player_for(current_account) && @session.visibility != 'direct'
    statuses = statuses.uniq(&:id).sort_by(&:id).last(MESSAGE_LIMIT)

    system = Game::System.account
    cards = events.index_by(&:status_id)
    last_event = events.last
    names = {}
    statuses.map do |status|
      account = status.account
      event = cards[status.id]
      {
        id: status.id.to_s,
        system: account.id == system&.id,
        mine: account.id == current_account.id,
        secret: status.direct_visibility? && @session.visibility != 'direct',
        name: names[account.id] ||= GameCharacter.for(account).display_name,
        acct: account.acct,
        avatar: full_asset_url(account.avatar_static_url),
        text: status.text.to_s.gsub(/\A(@\S+\s*)+/, '').strip,
        created_at: status.created_at.iso8601,
        card: event && (event.id == last_event&.id ? event.current_payload : event.payload.merge('live' => false)),
      }
    end
  end

  # root 에서 답으로 이어진 툿만 (id 순이라 부모가 먼저 나온다)
  def thread_from(root, statuses)
    kept = Set[root.id]
    statuses.select { |status| status.id == root.id || (kept.include?(status.in_reply_to_id) && kept.add(status.id)) }
  end

  # 이 판에서 시스템과 주고받은 DM: 시스템이 내게 보낸 DM 스레드(Kinds::Base#dm 이 이어 보낸다)의 툿
  def secret_statuses
    thread = Status.find_by(id: @session.player_for(current_account)&.state&.dig('dm_status_id'))
    return [] if thread.nil?

    Status.where(conversation_id: thread.conversation_id, visibility: :direct).includes(:account).to_a
  end

  # 이 사람의 팀 ('student'/'prefect'), 팀이 없는 이벤트·관전자면 nil
  def team_of_viewer
    player = @session.player_for(current_account)
    player && @session.kind_class.new(@session).try(:team_of, player)
  end

  def my_player!
    @session.player_for(current_account) || raise(ActiveRecord::RecordNotFound)
  end

  def set_session
    @session = GameSession.find(params[:id])
    raise ActiveRecord::RecordNotFound if @session.kind_class.nil?
    return if require_events_open!(@session.kind_class) # 이벤트 해금이 꺼져 있으면 막는다
    # 테스트 플레이(DM)는 참가자·초대받은 사람·운영진에게만 보인다 (다른 캐릭터는 관전도 참여도 안 된다)
    return unless @session.visibility == 'direct' && @session.players.none? { |player| player.account_id == current_account.id }
    return if Array(@session.state['invited']).map(&:to_i).include?(current_account.id)
    return if staff_watching?

    raise ActiveRecord::RecordNotFound
  end

  # 운영진은 테스트 플레이를 관전할 수 있다
  def staff_watching?
    @session.test? && staff?
  end

  def staff?
    current_user.can?(:manage_settings)
  end

  # 초대한 이벤트를 연 사람 (운영진이 아니어도 자기가 연 초대는 관리한다)
  def opener?
    @session.state['opened_by'].to_i == current_account.id
  end

  def can_invite_more?
    staff? || opener?
  end
end
