# frozen_string_literal: true

# 웹 게임 화면의 버튼: 서버원 대신 '@시스템 [명령어]' 툿을 올린다.
# 진행은 툿으로 하던 그대로 (Game::Engine 이 처리, 앱에서는 멘션 알림으로 보인다).
#
#   새 판 신청:  kind, opponents[] (아이디)        → '@시스템 @상대 … [시작 명령어]'
#   서버 이벤트: kind                              → '@시스템 [이벤트 명령어]'
#   판 안 명령:  session_id, command, args?, target?, dm?
#                공개 답장이면 다른 참가자도 태그(알림), 대상이 있으면 대상만, dm 이면 시스템에게 DM
class Api::V1::System::CommandsController < Api::BaseController
  include Api::GameGate
  before_action -> { doorkeeper_authorize! :write }
  before_action :require_user!
  before_action :require_contents_open!

  def create
    text, thread, visibility = params[:session_id].present? ? session_command : new_command
    return render json: { error: @limit_error || 'invalid', limit: @limit_error.present? }, status: 422 if text.nil?

    status = PostStatusService.new.call(current_account, text: text, thread: thread, visibility: visibility)
    handle_now!(status)
    render json: { status_id: status.id.to_s }
  rescue ActiveRecord::RecordInvalid, Mastodon::ValidationError => e
    render json: { error: e.message }, status: 422
  end

  private

  # 웹 버튼: 큐(Sidekiq)에서 기다리지 않고 지금 바로 처리해서 화면이 빨리 바뀌게 한다
  def handle_now!(status)
    return unless Game::System.command_toot?(status) && Game::MentionWorker.claim?(status.id)

    Game::Engine.new(status).call
  rescue => e
    Rails.logger.error { "web command failed for status #{status.id}: #{e.class} #{e.message}" }
  end

  def system_mention
    "@#{Game::System.username}"
  end

  def clean(value)
    value.to_s.delete('[]').strip
  end

  def new_command
    kind = Game::Kinds.registry[params[:kind].to_s]
    return if kind.nil? || !kind.enabled?

    return ["#{system_mention} [#{kind.config['cmd_join']}]", nil, 'private'] if ActiveModel::Type::Boolean.new.cast(params[:join]) && kind.config['cmd_join'].present?
    return ["#{system_mention} [#{kind.config['command']}]", nil, 'private'] if kind.event?

    usernames = Array(params[:opponents]).map { |acct| clean(acct).delete_prefix('@') }
    # 고른 순서를 지킨다: 팀전은 앞에서부터 우리 팀(팀원 → 상대 팀)이다
    opponents = Account.local.where(username: usernames).where.not(id: current_account.id).sort_by { |account| usernames.index(account.username) }
    return if opponents.empty?

    # 하루 신청 횟수를 넘었으면 신청하지 않고 안내를 보여 준다 (웹 신청 창)
    @limit_error = Game::DailyLimits.check(current_account, opponents, kind: kind)
    return if @limit_error

    command = kind.config['command']
    command = "#{command}/#{params[:team_size].to_i}" if kind.uneven_teams? && params[:team_size].to_i.positive?
    ["#{system_mention} #{opponents.map { |account| "@#{account.acct}" }.join(' ')} [#{command}]", nil, 'private']
  end

  # text 가 오면 [명령어]를 따로 만들지 않고 그대로 올린다: 그냥 하는 말(시스템은 답하지 않는다) 또는 [명령어]가 섞인 말
  def session_command
    session = GameSession.find(params[:session_id])
    player = session.players.find { |item| item.account_id == current_account.id }
    body = params[:text].to_s.strip.presence || session_command_body
    return if body.blank?

    if ActiveModel::Type::Boolean.new.cast(params[:dm])
      thread = player && Status.find_by(id: player.state['dm_status_id'])
      return ["#{system_mention} #{body}", thread, 'direct']
    end

    targets = [params[:target], *Array(params[:targets])].map { |acct| clean(acct).delete_prefix('@') }.compact_blank
    others = targets.any? ? [] : session.players.reject { |item| item.account_id == current_account.id }.map { |item| "@#{item.account.acct}" }
    mentions = [system_mention, *others].join(' ')
    text = "#{mentions} #{body}#{targets.map { |acct| " @#{acct}" }.join}"
    thread = Status.find_by(id: session.last_status_id || session.root_status_id)
    [text, thread, session.visibility == 'direct' ? 'direct' : 'private']
  end

  def session_command_body
    command = clean(params[:command])
    return if command.blank?

    command = "#{command}/#{clean(params[:args])}" if params[:args].present?
    "[#{command}]"
  end
end
