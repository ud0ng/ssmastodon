# frozen_string_literal: true

module Admin
  # 관리 > 컨텐츠 > 목록의 '진행 중' 표: 멈추거나 잘못된 판을 운영진이 직접 다룬다 (Game::SessionControl)
  class GameSessionsController < BaseController
    before_action :set_session

    def advance
      run { Game::SessionControl.advance!(@session) }
    end

    def cancel
      run { Game::SessionControl.cancel!(@session) }
    end

    def draw
      run { Game::SessionControl.draw!(@session) }
    end

    def decide
      player = @session.players.find_by(id: params[:player_id])
      return redirect_to(admin_game_settings_path, alert: t('admin.games.running.no_player')) if player.nil?

      run { Game::SessionControl.decide!(@session, player) }
    end

    private

    def run
      yield
      redirect_to admin_game_settings_path, notice: t('admin.games.running.done')
    rescue StandardError => e
      Rails.logger.warn { "Admin::GameSessionsController: #{e.class} #{e.message}" }
      redirect_to admin_game_settings_path, alert: t('admin.games.running.failed', message: e.message)
    end

    def set_session
      authorize :settings, :update?
      @session = GameSession.find(params[:id])
    end
  end
end
