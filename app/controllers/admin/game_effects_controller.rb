# frozen_string_literal: true

module Admin
  # 상점 설정 > 효과 목록: 소속 카드·캐릭터(칭호·데코·스킨) 효과. 맨 위 효과 on/off 는 Game::Config 'currency' effects_enabled
  class GameEffectsController < BaseController
    def index
      authorize :settings, :show?

      GameEffect.ensure_defaults!
      @effects = GameEffect.all.to_a
      @values = Game::Config.for('currency')
      @sections = Game::Config.schema('currency').group_by(&:group)
    end

    def create
      authorize :settings, :update?

      GameEffect.create!(effect_params.merge(position: GameEffect.count))
      redirect_to admin_game_effects_path, notice: t('generic.changes_saved_msg')
    rescue ActiveRecord::RecordInvalid => e
      redirect_to admin_game_effects_path(modal: 'effect-add'), alert: e.record.errors.full_messages.to_sentence
    end

    def update
      authorize :settings, :update?

      GameEffect.find(params[:id]).update!(effect_params)
      redirect_to admin_game_effects_path, notice: t('generic.changes_saved_msg')
    rescue ActiveRecord::RecordInvalid => e
      redirect_to admin_game_effects_path(modal: "effect-#{params[:id]}"), alert: e.record.errors.full_messages.to_sentence
    end

    def destroy
      authorize :settings, :update?

      GameEffect.find(params[:id]).destroy!
      redirect_to admin_game_effects_path, notice: t('generic.changes_saved_msg')
    end

    private

    def effect_params
      params.expect(game_effect: [:look, :name, :description])
    end
  end
end
