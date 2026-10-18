# frozen_string_literal: true

module Admin
  # 관리 > 컨텐츠 > 목록의 [이벤트 열기]: 시스템 계정이 모집 툿을 올리고 참가자를 받는다 (Game::Events::Opening)
  class GameEventsController < BaseController
    def create
      authorize :settings, :update?

      kind = Game::Kinds.registry[params[:kind].to_s]
      return redirect_to(admin_game_settings_path, alert: t('admin.games.events.unknown')) if kind.nil?

      Game::Events::Opening.open!(kind, current_account)
      redirect_to admin_game_settings_path, notice: t('admin.games.events.opened', name: kind.display_name)
    rescue Game::Events::Opening::Error => e
      redirect_to admin_game_settings_path, alert: e.message
    end
  end
end
