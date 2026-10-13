# frozen_string_literal: true

# 웹 게임 화면의 버튼: 서버원 대신 '@시스템 [명령어]' 툿을 올린다.
# 진행은 툿으로 하던 그대로 (Game::Engine 이 처리, 앱에서는 멘션 알림으로 보인다).
#
#   새 판 신청:  kind, opponents[] (아이디)        → '@시스템 @상대 … [시작 명령어]'
#   수업·자습:   kind, mode=study|class            → '@시스템 [자습/과목]'
#   판 안 명령:  session_id, command, args?, target?, dm?
#                공개 답장이면 다른 참가자도 태그(알림), 대상이 있으면 대상만, dm 이면 시스템에게 DM
class Api::V1::System::CommandsController < Api::BaseController
  before_action -> { doorkeeper_authorize! :write }
  before_action :require_user!

  def create
    text, thread, visibility = params[:session_id].present? ? session_command : new_command
    return render json: { error: 'invalid' }, status: 422 if text.nil?

    status = PostStatusService.new.call(current_account, text: text, thread: thread, visibility: visibility)
    render json: { status_id: status.id.to_s }
  rescue ActiveRecord::RecordInvalid, Mastodon::ValidationError => e
    render json: { error: e.message }, status: 422
  end

  private

  def system_mention
    "@#{Game::System.username}"
  end

  def clean(value)
    value.to_s.delete('[]').strip
  end

  def new_command
    kind = Game::Kinds.registry[params[:kind].to_s]
    return if kind.nil? || !kind.enabled?

    if kind.lesson?
      lessons = Game::Lessons.config
      command = params[:mode] == 'class' ? lessons['cmd_class'] : lessons['cmd_study']
      return ["#{system_mention} [#{command}/#{kind.display_name}]", nil, 'private']
    end

    return ["#{system_mention} [#{kind.config['command']}]", nil, 'private'] if kind.event?

    opponents = Account.local.where(username: Array(params[:opponents]).map { |acct| clean(acct).delete_prefix('@') }).where.not(id: current_account.id)
    return if opponents.empty?

    ["#{system_mention} #{opponents.map { |account| "@#{account.acct}" }.join(' ')} [#{kind.config['command']}]", nil, 'private']
  end

  def session_command
    session = GameSession.find(params[:session_id])
    player = session.players.find { |item| item.account_id == current_account.id }
    command = clean(params[:command])
    return if command.blank?

    command = "#{command}/#{clean(params[:args])}" if params[:args].present?
    target = clean(params[:target]).delete_prefix('@')

    if ActiveModel::Type::Boolean.new.cast(params[:dm])
      thread = player && Status.find_by(id: player.state['dm_status_id'])
      return ["#{system_mention} [#{command}]", thread, 'direct']
    end

    others = target.present? ? [] : session.players.reject { |item| item.account_id == current_account.id }.map { |item| "@#{item.account.acct}" }
    mentions = [system_mention, *others].join(' ')
    text = "#{mentions} [#{command}]#{" @#{target}" if target.present?}"
    thread = Status.find_by(id: session.last_status_id || session.root_status_id)
    [text, thread, session.visibility == 'direct' ? 'direct' : 'private']
  end
end
