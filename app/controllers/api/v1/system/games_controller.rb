# frozen_string_literal: true

# 웹 시스템 메뉴의 컨텐츠별 화면 (/system/games/:key): 하는 법, 내 전적, 진행 중·최근 판, 순위.
# DM 으로 진행한 판은 참가자에게만 보인다.
class Api::V1::System::GamesController < Api::BaseController
  include Api::GameGate
  include RoutingHelper

  LIST_LIMIT = 15
  RANK_LIMIT = 5

  before_action -> { doorkeeper_authorize! :read }, only: [:show]
  before_action -> { doorkeeper_authorize! :write }, only: [:open]
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
      # 여럿이 하는 컨텐츠는 운영진이 연다: event 면 [이벤트 열기] (운영진) / 모집 알림을 기다리기 (일반). 이벤트로 열 수 없는 여럿이 컨텐츠(퀴디치)는 운영진만 시작
      event: event_kind?,
      can_open: can_open?,
      web_open: @kind.event_capable?,
      event_min_players: @kind.config['event_min_players'],
      event_max_players: @kind.config['event_max_players'],
      event_join_minutes: @kind.config['event_join_minutes'],
      staff: current_user.can?(:manage_settings),
      # 하루 신청 횟수를 이미 넘었으면 [시작하기]를 누를 때 바로 보여 주는 안내 (같은 상대 제한은 상대를 고른 뒤 신청할 때)
      daily_limit_message: Game::DailyLimits.check(current_account, [], kind: @kind),
      enabled: @kind.enabled?,
      system_acct: Game::System.username,
      command: @kind.config['command'],
      max_opponents: @kind.max_opponents,
      min_opponents: @kind.min_opponents,
      team: @kind.team_game?,
      uneven_teams: @kind.uneven_teams?,
      summary: guide[:summary],
      rules_text: guide[:rules],
      roles: guide[:roles],
      items: guide[:items],
      steps: guide[:steps],
      rules: rules,
      currency: common['currency_name'],
      record: record,
      my_session_id: my_session&.id&.to_s,
      recruiting: recruiting,
      busy: busy(common),
      active: visible_sessions.where(status: GameSession::OPEN_STATUSES).order(updated_at: :desc).limit(LIST_LIMIT).map { |session| session_json(session) },
      recent: visible_sessions.where(status: 'finished').order(finished_at: :desc).limit(LIST_LIMIT).map { |session| session_json(session) },
      ranking: ranking,
    }
  end

  # 운영진이 [이벤트 열기] (모집형 이벤트: 비행·미로·도둑 지도). 비밀의 방은 멘션 명령어로 연다
  #   mode: recruit(참가자 모집, 기본) / pick(accts 로 고른 참가자에게만 알림) / test(accts 로 고른 참가자끼리 단체 DM 으로 하는 테스트 플레이)
  def open
    return render json: { error: '이벤트를 열 수 있는 사람이 아닙니다.' }, status: 403 unless can_open?

    mode = params[:mode].presence || 'recruit'
    return render json: { error: '운영진만 할 수 있습니다.' }, status: 403 if mode != 'recruit' && !staff?

    Game::Events::Opening.open!(@kind, current_account, mode: mode, players: picked_accounts(mode))
    render json: { ok: true }
  rescue Game::Events::Opening::Error => e
    render json: { error: e.message }, status: 422
  end

  private

  # 고른 참가자 (아이디 목록). 목록에 없는 사람이 있으면 에러
  def picked_accounts(mode)
    return [] if mode == 'recruit'

    names = Array(params[:accts]).map { |name| name.to_s.delete_prefix('@') }.uniq
    accounts = GameCharacter.eligible_accounts.where(username: names).to_a.uniq(&:id)
    raise Game::Events::Opening::Error, '고른 참가자 중에 컨텐츠에 낄 수 없는 사람이 있습니다.' if accounts.size != names.size

    accounts
  end

  def event_kind?
    @kind.event_capable?
  end

  def staff?
    current_user.can?(:manage_settings)
  end

  def can_open?
    return false unless event_kind?

    staff?
  end

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
    results = GamePlayer.joins(:session).merge(GameSession.current_kinds.real).where(account: current_account, game_sessions: { kind: @kind.key, status: 'finished' }).group(:result).count
    { win: results['win'].to_i, lose: results['lose'].to_i, draw: results['draw'].to_i }
  end

  # 내가 지금 하고 있는 (또는 신청받은) 이 컨텐츠 판 → 게임 화면에 바로 띄운다
  # 모집 중인 이벤트 (참가 버튼): 이 컨텐츠를 운영진이 열었고 내가 아직 참가하지 않았다
  def recruiting
    session = GameSession.current_kinds.where(kind: @kind.key, status: 'pending').where("state->>'mode' = 'event'").order(id: :desc).first
    return if session.nil? || session.players.any? { |player| player.account_id == current_account.id }
    return if Array(session.state['invited']).any? && Array(session.state['invited']).exclude?(current_account.id) # 참가자를 골라 연 이벤트는 고른 사람에게만

    { session_id: session.id.to_s, ends_at: session.deadline_at&.iso8601, count: session.players.size }
  end

  def my_session
    GameSession.current_kinds.joins(:players).where(kind: @kind.key, status: GameSession::OPEN_STATUSES, game_players: { account_id: current_account.id })
               .order(updated_at: :desc).first
  end

  # 동시 진행을 막았는데 다른 컨텐츠를 하고 있으면 [시작하기] 대신 바로 안내 (문구는 명령어 탭 '이미 진행 중 (웹 시작하기)')
  def busy(common)
    return unless common['one_game_per_person']

    session = GameSession.current_kinds.joins(:players).where(status: GameSession::OPEN_STATUSES, game_players: { account_id: current_account.id })
                         .order(updated_at: :desc).first
    return if session.nil?

    { message: Game::Text.render(common['msg_busy_web'], player: current_account), session_id: session.id.to_s, name: session.kind_class&.display_name }
  end

  def visible_sessions
    mine = GamePlayer.where(account: current_account).select(:game_session_id)
    # 테스트 플레이는 참가자와 운영진(자물쇠)에게만 보인다
    scope = GameSession.current_kinds.where(kind: @kind.key)
    scope = if staff?
              scope.where("game_sessions.visibility <> 'direct' OR game_sessions.id IN (?) OR COALESCE(game_sessions.state->>'test', '') = 'true'", mine)
            else
              scope.where('game_sessions.visibility <> ? OR game_sessions.id IN (?)', 'direct', mine)
            end
    scope.includes(players: :account)
  end

  def session_json(session)
    {
      id: session.id.to_s,
      test: session.test?,
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
    wins = GamePlayer.joins(:session).merge(GameSession.current_kinds.real).where(result: 'win', game_sessions: { kind: @kind.key, status: 'finished' }).group(:account_id).count
    top = wins.sort_by { |_, count| -count }.first(RANK_LIMIT)
    accounts = Account.where(id: top.map(&:first)).index_by(&:id)
    top.filter_map do |account_id, count|
      account = accounts[account_id]
      next if account.nil?

      { name: GameCharacter.for(account).display_name, acct: account.acct, wins: count, me: account_id == current_account.id }
    end
  end
end
