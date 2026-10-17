# frozen_string_literal: true

# 웹 시스템 메뉴의 컨텐츠별 화면 (/system/games/:key): 하는 법, 내 전적, 진행 중·최근 판, 순위.
# DM 으로 진행한 판은 참가자에게만 보인다.
class Api::V1::System::GamesController < Api::BaseController
  include Api::GameGate
  include RoutingHelper

  LIST_LIMIT = 15
  RANK_LIMIT = 5

  before_action -> { doorkeeper_authorize! :read }
  before_action :require_user!
  before_action :require_contents_open!
  before_action :set_kind

  def show
    common = Game::Config.for('common')
    guide = Game::Guide.for(@kind)

    render json: {
      key: @kind.key,
      name: @kind.display_name,
      group: Game::Guide.group_of(@kind),
      event: @kind.event?,
      enabled: @kind.enabled?,
      system_acct: Game::System.username,
      command: @kind.config['command'],
      max_opponents: @kind.max_opponents,
      min_opponents: @kind.min_opponents,
      team: @kind.team_game?,
      summary: guide[:summary],
      rules_text: guide[:rules],
      roles: guide[:roles],
      items: guide[:items],
      steps: guide[:steps],
      rules: rules,
      currency: common['currency_name'],
      record: record,
      my_session_id: my_session&.id&.to_s,
      busy: busy(common),
      active: visible_sessions.where(status: %w(pending active)).order(updated_at: :desc).limit(LIST_LIMIT).map { |session| session_json(session) },
      recent: visible_sessions.where(status: 'finished').order(finished_at: :desc).limit(LIST_LIMIT).map { |session| session_json(session) },
      ranking: ranking,
    }
  end

  private

  def set_kind
    @kind = Game::Kinds.registry[params[:id]]
    not_found if @kind.nil?
  end

  # 점수·보상 한눈에
  def rules
    config = @kind.config
    [
      { label: 'win', points: config['points_win'].to_i, money: config['reward_money_win'].to_i, items: Array(config['reward_items_win']).map { |line| line.to_s.split('|').first } },
      { label: 'draw', points: config['points_draw'].to_i, money: config['reward_money_draw'].to_i },
      { label: 'lose', points: 0, money: config['reward_money_lose'].to_i },
    ]
  end

  def record
    results = GamePlayer.joins(:session).merge(GameSession.current_kinds).where(account: current_account, game_sessions: { kind: @kind.key, status: 'finished' }).group(:result).count
    { win: results['win'].to_i, lose: results['lose'].to_i, draw: results['draw'].to_i }
  end

  # 내가 지금 하고 있는 (또는 신청받은) 이 컨텐츠 판 → 게임 화면에 바로 띄운다
  def my_session
    GameSession.current_kinds.joins(:players).where(kind: @kind.key, status: %w(pending active), game_players: { account_id: current_account.id })
               .order(updated_at: :desc).first
  end

  # 동시 진행을 막았는데 다른 컨텐츠를 하고 있으면 [시작하기] 대신 바로 안내 (문구는 명령어 탭 '이미 진행 중 (웹 시작하기)')
  def busy(common)
    return unless common['one_game_per_person']

    session = GameSession.current_kinds.joins(:players).where(status: %w(pending active), game_players: { account_id: current_account.id })
                         .order(updated_at: :desc).first
    return if session.nil?

    { message: Game::Text.render(common['msg_busy_web'], player: current_account), session_id: session.id.to_s, name: session.kind_class&.display_name }
  end

  def visible_sessions
    mine = GamePlayer.where(account: current_account).select(:game_session_id)
    GameSession.current_kinds.where(kind: @kind.key).where('game_sessions.visibility <> ? OR game_sessions.id IN (?)', 'direct', mine).includes(players: :account)
  end

  def session_json(session)
    {
      id: session.id.to_s,
      status: session.status,
      turn: session.turn,
      deadline_at: session.deadline_at&.iso8601,
      finished_at: session.finished_at&.iso8601,
      players: session.players.map do |player|
        { name: player.name, acct: player.account.acct, avatar: full_asset_url(player.account.avatar_static_url),
          result: player.result, me: player.account_id == current_account.id }
      end,
    }
  end

  # 이 컨텐츠 승리 수 순위
  def ranking
    wins = GamePlayer.joins(:session).merge(GameSession.current_kinds).where(result: 'win', game_sessions: { kind: @kind.key, status: 'finished' }).group(:account_id).count
    top = wins.sort_by { |_, count| -count }.first(RANK_LIMIT)
    accounts = Account.where(id: top.map(&:first)).index_by(&:id)
    top.filter_map do |account_id, count|
      account = accounts[account_id]
      next if account.nil?

      { name: GameCharacter.for(account).display_name, acct: account.acct, wins: count, me: account_id == current_account.id }
    end
  end
end
