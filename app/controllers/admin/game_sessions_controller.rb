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
      return redirect_to(back_path, alert: t('admin.games.running.no_player')) if player.nil?

      run { Game::SessionControl.decide!(@session, player) }
    end

    private

    # 판을 다룬 뒤에는 그 판이 있던 목록으로: 이벤트(여럿이 하는 컨텐츠)는 이벤트 설정 > 목록, 그 밖에는 컨텐츠 설정 > 목록
    def back_path
      Game::Kinds.group_games.map(&:key).include?(@session.kind) ? admin_game_events_settings_path : admin_game_settings_path
    end

    def run
      yield
      redirect_to back_path, notice: t('admin.games.running.done')
    rescue StandardError => e
      Rails.logger.warn { "Admin::GameSessionsController: #{e.class} #{e.message}" }
      redirect_to back_path, alert: t('admin.games.running.failed', message: e.message)
    end

    def set_session
      authorize :settings, :update?
      @session = GameSession.find(params[:id])
    end
  end
end
