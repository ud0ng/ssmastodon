# frozen_string_literal: true

# 웹 성적 화면(글쓰기 패널 아래 [전적])의 컨텐츠 기록: 내가 끝낸 판을 최신순으로 (재화 기록처럼 max_id 로 다음 쪽)
#   한 줄: 컨텐츠·결과·함께한 사람·끝난 시각, 그 판으로 받은 소속 점수·재화·아이템
#   filter: win / lose / draw (없으면 전체)
class Api::V1::System::HistoriesController < Api::BaseController
  LIMIT = 30

  before_action -> { doorkeeper_authorize! :read }
  before_action :require_user!

  def show
    scope = GamePlayer.joins(:session).merge(GameSession.current_kinds).where(account: current_account, game_sessions: { status: 'finished' })
    scope = scope.where(result: params[:filter]) if %w(win lose draw).include?(params[:filter])
    scope = scope.where(id: ...params[:max_id].to_i) if params[:max_id].present?
    players = scope.includes(session: { players: :account }).order(id: :desc).limit(LIMIT + 1).to_a
    page = players.first(LIMIT)
    session_ids = page.map(&:game_session_id)
    points = GameHousePoint.where(account: current_account, game_session_id: session_ids).group(:game_session_id).sum(:amount)
    rewards = GameReward.where(account: current_account, game_session_id: session_ids).group_by(&:game_session_id)

    render json: {
      games: page.map { |player| game_json(player, points, rewards) },
      next_max_id: players.size > LIMIT ? page.last.id.to_s : nil,
    }
  end

  private

  def game_json(player, points, rewards)
    session = player.session
    kind = session.kind_class
    mine = rewards.fetch(session.id, [])
    {
      id: player.id.to_s,
      session_id: session.id.to_s,
      kind: session.kind,
      name: kind&.display_name || session.kind,
      result: player.result,
      opponents: session.players.reject { |other| other.id == player.id }.map(&:name),
      finished_at: (session.finished_at || session.updated_at).iso8601,
      points: points.fetch(session.id, 0),
      money: mine.sum(&:money),
      items: mine.flat_map { |reward| Array(reward.items) }.map { |item| { name: item['name'], count: item['count'].to_i } },
    }
  end
end
