# frozen_string_literal: true

module Admin
  # 관리 > 게임 설정: 공통 규칙(시스템 계정·명령어·시간·점수 규칙·문구)과 게임별 설정
  class GameSettingsController < BaseController
    before_action :set_key, only: [:show, :update]

    # 첫 화면: 컨텐츠·수업 과목 카드 목록 (켜짐, 시작 명령어, 최근 1주 판 수)
    def index
      authorize :settings, :show?

      @recent = GameSession.where(created_at: 7.days.ago..).group(:kind).count
      @open = GameSession.open.group(:kind).count
    end

    def show
      authorize :settings, :show?

      @sections = Game::Config.sections(@key, @page)
      @values = Game::Config.for(@key)
      @accounts = Account.local.without_instance_actor.without_suspended.order(:username).to_a if @key == 'common'
    end

    def update
      authorize :settings, :update?

      Game::Config.update!(@key, params.fetch(:config, {}).permit!.to_h)
      flash[:notice] = t('generic.changes_saved_msg')
      redirect_to admin_game_setting_path(params[:id])
    end

    private

    # 공통 설정은 '설정'(common) / '명령어'(commands) 두 화면으로 나눠 보여 준다
    def set_key
      @key, @page = { 'common' => %w(common settings), 'commands' => %w(common commands) }.fetch(params[:id]) { [params[:id], nil] }
      raise ActiveRecord::RecordNotFound unless Game::Config.keys.include?(@key)
    end
  end
end
