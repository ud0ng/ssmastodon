# frozen_string_literal: true

module Admin
  # 상점 설정 > 누적 수치 목록: 수치 종류(신고 등) 추가·이름 바꾸기·삭제. 누적 횟수별 효과는 Admin::GameCounterRulesController
  class GameCountersController < BaseController
    def index
      authorize :settings, :show?

      GameCounter.ensure_defaults!
      GameEffect.ensure_defaults!
      @counters = GameCounter.includes(rules: :effect).to_a
      @effects = GameEffect.all.to_a
    end

    def create
      authorize :settings, :update?

      GameCounter.create!(counter_params.merge(position: GameCounter.count))
      redirect_to admin_game_counters_path, notice: t('generic.changes_saved_msg')
    rescue ActiveRecord::RecordInvalid => e
      redirect_to admin_game_counters_path(modal: 'counter-add'), alert: e.record.errors.full_messages.to_sentence
    end

    def update
      authorize :settings, :update?

      GameCounter.find(params[:id]).update!(counter_params)
      redirect_to admin_game_counters_path, notice: t('generic.changes_saved_msg')
    rescue ActiveRecord::RecordInvalid => e
      redirect_to admin_game_counters_path(modal: "counter-#{params[:id]}"), alert: e.record.errors.full_messages.to_sentence
    end

    def destroy
      authorize :settings, :update?

      GameCounter.find(params[:id]).destroy!
      redirect_to admin_game_counters_path, notice: t('generic.changes_saved_msg')
    end

    private

    def counter_params
      permitted = params.expect(game_counter: [:name, :max_count, :opposite_id, :affects_house, :house_interval, :house_unit, :house_amount])
      interval = permitted.delete(:house_interval)
      unit = permitted.delete(:house_unit)
      permitted[:affects_house] = permitted[:affects_house] == '1'
      permitted[:house_interval_minutes] = [interval.to_i, 1].max * { 'hour' => 60, 'day' => 1440 }.fetch(unit.to_s, 1) if interval.present?
      permitted
    end
  end
end
