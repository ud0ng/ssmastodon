# frozen_string_literal: true

# 웹 컨텐츠 진행 화면 (/system/sessions/:id): 한 판의 시스템 툿 카드를 순서대로.
# DM 으로 진행한 판은 참가자만 본다. 팔로워 공개 판은 서버원 누구나 (서버원끼리 서로 팔로우한다).
class Api::V1::System::SessionsController < Api::BaseController
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

  def my_player!
    @session.player_for(current_account) || raise(ActiveRecord::RecordNotFound)
  end

  def set_session
    @session = GameSession.find(params[:id])
    return unless @session.visibility == 'direct' && @session.players.none? { |player| player.account_id == current_account.id }

    raise ActiveRecord::RecordNotFound
  end
end
