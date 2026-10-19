# frozen_string_literal: true

module Admin
  # 누적 수치의 누적 횟수별 효과 (누적 N회 → 효과 목록의 효과를 지속시간 동안) 추가·수정·삭제
  class GameCounterRulesController < BaseController
    before_action :set_counter

    def create
      authorize :settings, :update?

      @counter.rules.create!(rule_params)
      redirect_to admin_game_counters_path, notice: t('generic.changes_saved_msg')
    rescue ActiveRecord::RecordInvalid => e
      redirect_to admin_game_counters_path(modal: "rule-add-#{@counter.id}"), alert: e.record.errors.full_messages.to_sentence
    end

    def update
      authorize :settings, :update?

      @counter.rules.find(params[:id]).update!(rule_params)
      redirect_to admin_game_counters_path, notice: t('generic.changes_saved_msg')
    rescue ActiveRecord::RecordInvalid => e
      redirect_to admin_game_counters_path(modal: "rule-#{params[:id]}"), alert: e.record.errors.full_messages.to_sentence
    end

    def destroy
      authorize :settings, :update?

      @counter.rules.find(params[:id]).destroy!
      redirect_to admin_game_counters_path, notice: t('generic.changes_saved_msg')
    end

    private

    def set_counter
      @counter = GameCounter.find(params[:game_counter_id])
    end

    # 누적 횟수는 숫자 또는 '최대치'(mode=max), 지속시간은 숫자 + 단위(minute/hour/day) 또는 영구(unit=forever)
    def rule_params
      permitted = params.expect(game_counter_rule: [:threshold, :mode, :game_effect_id, :minutes, :unit])
      permitted[:at_max] = permitted.delete(:mode) == 'max'
      unit = permitted.delete(:unit)
      permitted[:permanent] = unit == 'forever' || permitted[:at_max]
      permitted[:minutes] = permitted[:permanent] ? 1440 : Game::ItemEffects.minutes(permitted[:minutes], unit)
      permitted[:threshold] = 1 if permitted[:threshold].blank?
      permitted
    end
  end
end
