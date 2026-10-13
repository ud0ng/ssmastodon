# frozen_string_literal: true

module Admin
  # 관리 > 게임 설정: 공통 규칙(시스템 계정·명령어·시간·점수 규칙·문구)과 게임별 설정
  class GameSettingsController < BaseController
    before_action :set_key, only: [:show, :update]

    def index
      authorize :settings, :show?

      redirect_to admin_game_setting_path('common')
    end

    def show
      authorize :settings, :show?

      @fields = Game::Config.schema(@key)
      @values = Game::Config.for(@key)
    end

    def update
      authorize :settings, :update?

      Game::Config.update!(@key, params.fetch(:config, {}).permit!.to_h)
      flash[:notice] = t('generic.changes_saved_msg')
      redirect_to admin_game_setting_path(@key)
    end

    private

    def set_key
      @key = params[:id]
      raise ActiveRecord::RecordNotFound unless Game::Config.keys.include?(@key)
    end
  end
end
