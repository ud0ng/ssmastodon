# frozen_string_literal: true

module Admin
  # 관리 > 게임 설정 > 기숙사: 기숙사 목록, 점수 현황, 운영진 점수 조정
  class GameHousesController < BaseController
    def index
      authorize :settings, :show?

      GameHouse.ensure_defaults!
      @houses = GameHouse.all
      @recent_points = GameHousePoint.includes(:house, :account).order(id: :desc).limit(30)
    end

    def create
      authorize :settings, :update?

      GameHouse.create!(house_params.merge(position: GameHouse.count))
      redirect_to admin_game_houses_path, notice: t('generic.changes_saved_msg')
    rescue ActiveRecord::RecordInvalid => e
      redirect_to admin_game_houses_path, alert: e.record.errors.full_messages.to_sentence
    end

    def update
      authorize :settings, :update?

      GameHouse.find(params[:id]).update!(house_params)
      redirect_to admin_game_houses_path, notice: t('generic.changes_saved_msg')
    rescue ActiveRecord::RecordInvalid => e
      redirect_to admin_game_houses_path, alert: e.record.errors.full_messages.to_sentence
    end

    def destroy
      authorize :settings, :update?

      GameHouse.find(params[:id]).destroy!
      redirect_to admin_game_houses_path, notice: t('generic.changes_saved_msg')
    end

    # 운영진 점수 조정 (+/-)
    def adjust
      authorize :settings, :update?

      house = GameHouse.find(params[:house_id])
      amount = params[:amount].to_i
      GameHousePoint.create!(house: house, amount: amount, reason: params[:reason].to_s.strip.presence || t('admin.games.houses.manual')) unless amount.zero?
      redirect_to admin_game_houses_path, notice: t('generic.changes_saved_msg')
    end

    # 주간 결산 툿을 지금 올린다 (정기 결산과 별개)
    def weekly
      authorize :settings, :update?

      Game::Summary.post_weekly!
      redirect_to admin_game_houses_path, notice: t('admin.games.houses.posted')
    end

    # 학기 마감 발표 (점수는 그대로 둔다)
    def term_end
      authorize :settings, :update?

      Game::Summary.term_end!
      redirect_to admin_game_houses_path, notice: t('admin.games.houses.posted')
    end

    private

    def house_params
      params.expect(game_house: [:name, :emoji, :color, :position])
    end
  end
end
