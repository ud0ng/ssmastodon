# frozen_string_literal: true

# 웹 컨텐츠 진행 화면 (/system/sessions/:id): 한 판의 시스템 툿 카드를 순서대로.
# DM 으로 진행한 판은 참가자만 본다. 팔로워 공개 판은 서버원 누구나 (서버원끼리 서로 팔로우한다).
class Api::V1::System::SessionsController < Api::BaseController
  include RoutingHelper

  MESSAGE_LIMIT = 200

  before_action -> { doorkeeper_authorize! :read }, only: [:show, :view]
  before_action -> { doorkeeper_authorize! :write }, only: [:move]
  before_action :require_user!
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

  # 웹 전용 컨텐츠: 내게 보이는 판 (미로 시야 등). 참가자만.
  def view
    player = my_player!
    kind = @session.kind_class.new(@session)
    render json: { web: @session.kind_class.web?, status: @session.status, view: kind.respond_to?(:view_for) ? kind.view_for(player) : nil }
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

  # 컨텐츠 방(채팅) 메시지: 판 스레드의 툿 전부(신청·명령어·시스템 진행) + 내가 낀 판이면 그 사이 시스템과 주고받은 DM(비밀 선택).
  # 관전하는 사람은 스레드만 본다.
  def messages(events)
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

    raise ActiveRecord::RecordNotFound
  end
end
