# frozen_string_literal: true

module Admin
  # 관리 > 시스템 > 캐릭터 관리 > 소속: 기숙사·진영 목록, 점수 기준 소속(둘 중 무엇으로 점수·토너먼트를 할지), 점수 현황·조정, 정기 툿
  class GameHousesController < BaseController
    def index
      authorize :settings, :show?

      GameHouse.ensure_defaults!
      common = Game::Config.for('common')
      @mode = GameHouse.mode
      @labels = { 'house' => common['house_label'], 'faction' => common['faction_label'] }
      @lists = GameHouse::CATEGORIES.index_with { |category| GameHouse.where(category: category).to_a }
      @counts = {
        'house' => GameCharacter.visible.group(:game_house_id).count,
        'faction' => GameCharacter.visible.group(:game_faction_id).count,
      }
      @scoring_mode = common['scoring_mode']
      @seasons = GameSeason.order(id: :desc).to_a
      @season_fields = Game::Config.sections('common', 'season').flat_map(&:last)
      @season_values = common
    end

    def create
      authorize :settings, :update?

      category = GameHouse::CATEGORIES.include?(params.dig(:game_house, :category)) ? params[:game_house][:category] : 'house'
      GameHouse.create!(house_params.merge(category: category, position: GameHouse.where(category: category).count))
      redirect_to admin_game_houses_path, notice: t('generic.changes_saved_msg')
    rescue ActiveRecord::RecordInvalid => e
      redirect_to admin_game_houses_path(modal: "house-add-#{category}"), alert: e.record.errors.full_messages.to_sentence
    end

    def update
      authorize :settings, :update?

      GameHouse.find(params[:id]).update!(house_params)
      redirect_to admin_game_houses_path, notice: t('generic.changes_saved_msg')
    rescue ActiveRecord::RecordInvalid => e
      redirect_to admin_game_houses_path(modal: "house-#{params[:id]}"), alert: e.record.errors.full_messages.to_sentence
    end

    def destroy
      authorize :settings, :update?

      GameHouse.find(params[:id]).destroy!
      redirect_to admin_game_houses_path, notice: t('generic.changes_saved_msg')
    end

    # 점수 기준 소속 바꾸기 (공통 설정 group_mode)
    def mode
      authorize :settings, :update?

      Game::Config.merge!('common', 'group_mode' => params[:mode] == 'faction' ? 'faction' : 'house')
      redirect_to admin_game_houses_path, notice: t('generic.changes_saved_msg')
    end

    # 기숙사·진영을 부르는 이름 (공통 설정 house_label / faction_label)
    def labels
      authorize :settings, :update?

      values = GameHouse::CATEGORIES.to_h { |category| ["#{category}_label", params.dig(:labels, category).to_s.strip.first(20)] }.compact_blank
      Game::Config.merge!('common', values) if values.any?
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

    # 점수 방식 (점수제 / 판수제)
    def scoring
      authorize :settings, :update?

      Game::Config.merge!('common', 'scoring_mode' => params[:scoring_mode].to_s)
      redirect_to admin_game_houses_path, notice: t('generic.changes_saved_msg')
    end

    private

    def house_params
      params.expect(game_house: [:name, :color, :position])
    end
  end
end
