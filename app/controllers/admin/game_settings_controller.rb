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
      @shop_item_names = GameShopItem.pluck(:name)
      @accounts = Account.local.without_instance_actor.without_suspended.order(:username).to_a if @key == 'common'

      kind = Game::Kinds.registry[@key]
      if @page == 'settings'
        # 설정 탭: 컨텐츠마다 승리·무승부·패배 점수를 한 표에서 고친다
        @points_kinds = Game::Kinds.all.reject(&:lesson?)
        @scoring_mode = @values['scoring_mode']
      elsif kind && !kind.lesson?
        # 컨텐츠 화면에서는 점수 칸을 빼고 설정 탭의 표에서만 고친다
        @sections = @sections.reject { |section, _| section == 'points' }
      end
    end

    def update
      authorize :settings, :update?

      Game::Config.update!(@key, params.fetch(:config, {}).permit!.to_h)
      update_points! if @page == 'settings'
      flash[:notice] = t('generic.changes_saved_msg')
      redirect_to admin_game_setting_path(params[:id])
    end

    private

    # 설정 탭의 컨텐츠별 점수 표: points[컨텐츠][win|draw|lose]
    def update_points!
      params.fetch(:points, {}).permit!.to_h.each do |key, values|
        kind = Game::Kinds.registry[key]
        next if kind.nil? || kind.lesson?

        Game::Config.merge!(key, %w(win draw lose).to_h { |outcome| ["points_#{outcome}", [values[outcome].to_i, 0].max] })
      end
    end

    # 공통 설정은 '설정'(common) / '명령어'(commands), 도움말은 상점봇(help) / 시스템봇(help_system) 화면으로 나눠 보여 준다
    def set_key
      @key, @page = { 'common' => %w(common settings), 'commands' => %w(common commands), 'help' => %w(help shop_bot), 'help_system' => %w(help system_bot) }.fetch(params[:id]) { [params[:id], nil] }
      raise ActiveRecord::RecordNotFound unless Game::Config.keys.include?(@key)
    end
  end
end
