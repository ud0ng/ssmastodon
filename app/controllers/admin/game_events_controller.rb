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
