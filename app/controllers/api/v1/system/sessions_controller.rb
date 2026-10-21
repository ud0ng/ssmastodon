# frozen_string_literal: true

# 웹 컨텐츠 진행 화면 (/system/sessions/:id): 한 판의 시스템 툿 카드를 순서대로.
# DM 으로 진행한 판은 참가자만 본다. 팔로워 공개 판은 서버원 누구나 (서버원끼리 서로 팔로우한다).
class Api::V1::System::SessionsController < Api::BaseController
  include Api::GameGate
  include RoutingHelper

  MESSAGE_LIMIT = 200

  before_action -> { doorkeeper_authorize! :read }, only: [:show, :view]
  before_action -> { doorkeeper_authorize! :write }, only: [:move, :destroy, :ready, :cancel_start, :chat]
  before_action :require_user!
  before_action :require_contents_open!
  before_action :set_session

  def show
    events = @session.events.includes(:status).order(:id)
    render json: {
      id: @session.id.to_s,
      kind: @session.kind,
      name: @session.kind_class&.display_name || @session.kind,
      status: @session.status,
      system_acct: Game::System.username,
      root_status_id: @session.root_status_id&.to_s,
      last_status_id: @session.last_status_id&.to_s,
      player: @session.player_for(current_account).present?,
      lobby: @session.lobby? || Game::Lobby.recruiting?(@session) ? Game::Lobby.view(@session, current_account, staff: staff?) : nil,
      staff: staff?,
      messages: messages(events),
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
    view = kind.respond_to?(:view_for) && !recruiting ? kind.view_for(player) : nil
    add_avatars!(view)
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

  # 대기방 카운트다운 중 누구든 취소 (참가자·운영진)
  def cancel_start
    return render json: { error: 'forbidden' }, status: 403 unless @session.player_for(current_account) || staff?

    @session.with_lock { Game::Lobby.cancel_countdown!(@session, current_account) }
    show
  end

  # 채팅 (대기방): 참가자·운영진
  def chat
    return render json: { error: 'forbidden' }, status: 403 unless @session.player_for(current_account) || staff?

    # 대기방과 웹 전용 컨텐츠 방은 끝난 뒤에도 채팅할 수 있다
    Game::Lobby.chat!(@session, current_account, params[:text]) if @session.lobby? || Game::Lobby.recruiting?(@session) || (@session.web_channel? && @session.status != 'cancelled')
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
  def messages(events)
    (status_messages(events) + web_messages).sort_by { |message| message[:created_at] }.last(MESSAGE_LIMIT)
  end

  # 웹 전용 컨텐츠의 진행 메시지 (툿이 아니다): 판 전체 메시지 + 내게만 온 비밀 안내
  def web_messages
    system = Game::System.account
    scope = @session.messages.where(account_id: [nil, current_account.id]).order(:id).last(MESSAGE_LIMIT)
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
        card: message.secret? || message.payload.blank? ? nil : message.current_payload,
      }
    end
  end

  def status_messages(events)
    root = Status.find_by(id: @session.root_status_id)
    return [] if root.nil?

    statuses = Status.where(conversation_id: root.conversation_id, id: root.id..).includes(:account).to_a
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

  # 이 판에서 시스템과 주고받은 DM: 시스템이 내게 보낸 DM 스레드(Kinds::Base#dm 이 이어 보낸다)의 툿
  def secret_statuses
    thread = Status.find_by(id: @session.player_for(current_account)&.state&.dig('dm_status_id'))
    return [] if thread.nil?

    Status.where(conversation_id: thread.conversation_id, visibility: :direct).includes(:account).to_a
  end

  def my_player!
    @session.player_for(current_account) || raise(ActiveRecord::RecordNotFound)
  end

  def set_session
    @session = GameSession.find(params[:id])
    raise ActiveRecord::RecordNotFound if @session.kind_class.nil?
    return unless @session.visibility == 'direct' && @session.players.none? { |player| player.account_id == current_account.id }
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
end
