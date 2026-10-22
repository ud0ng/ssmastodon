# frozen_string_literal: true

module Admin
  # 관리 > 컨텐츠 > 목록의 [이벤트 열기]: 시스템 계정이 모집 툿을 올리고 참가자를 받는다 (Game::Events::Opening)
  class GameEventsController < BaseController
    # 이벤트 설정 첫 화면: 이벤트 열기 · 진행 중인 이벤트 · 여럿이 하는 컨텐츠 목록 (줄을 누르면 그 컨텐츠 설정)
    def index
      authorize :settings, :show?

      kinds = Game::Kinds.group_games
      @recent = GameSession.where(created_at: 7.days.ago..).group(:kind).count
      @open = GameSession.open.group(:kind).count
      @running = GameSession.open.current_kinds.where(kind: kinds.map(&:key)).includes(players: :account).order(updated_at: :desc).limit(50)
    end

    # 이벤트 내역: 시간 · 종류 · 참여자(끝난 판은 승리자 강조) · 상태(대기·진행·완료). 상점 설정의 기록 화면과 같은 틀
    PER_PAGE = 30
    STATUSES = { 'waiting' => %w(pending lobby), 'running' => %w(active), 'done' => %w(finished cancelled) }.freeze

    def records
      authorize :settings, :show?

      keys = Game::Kinds.group_games.map(&:key)
      scope = GameSession.current_kinds.where(kind: keys).includes(players: :account).order(id: :desc)
      scope = scope.where(kind: params[:kind]) if keys.include?(params[:kind])
      scope = scope.where(status: STATUSES[params[:status]]) if STATUSES.key?(params[:status])
      scope = scope.where(created_at: Time.zone.parse(params[:from].to_s).beginning_of_day..) if params[:from].present? && Time.zone.parse(params[:from].to_s)
      scope = scope.where(created_at: ..Time.zone.parse(params[:to].to_s).end_of_day) if params[:to].present? && Time.zone.parse(params[:to].to_s)
      @sessions = scope.page(params[:page]).per(PER_PAGE)
      @characters_by_account = GameCharacter.where(account_id: @sessions.flat_map { |session| session.players.map(&:account_id) }).index_by(&:account_id)
    end

    def create
      authorize :settings, :update?

      kind = Game::Kinds.registry[params[:kind].to_s]
      return redirect_to(admin_game_events_settings_path, alert: t('admin.games.events.unknown')) if kind.nil?

      mode = params[:mode].presence || 'recruit'
      players = mode == 'recruit' ? [] : GameCharacter.eligible_accounts.where(id: Array(params[:account_ids]).compact_blank).to_a
      Game::Events::Opening.open!(kind, current_account, mode: mode, players: players)
      redirect_to admin_game_events_settings_path, notice: t("admin.games.events.opened_#{Game::Events::Opening::MODES.include?(mode) ? mode : 'recruit'}", name: kind.display_name)
    rescue Game::Events::Opening::Error => e
      redirect_to admin_game_events_settings_path, alert: e.message
    end
  end
end
