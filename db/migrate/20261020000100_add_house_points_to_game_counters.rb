# frozen_string_literal: true

# 누적 수치가 소속 점수에 영향을 준다: 켜면 정한 시간 간격마다 소속 캐릭터의 결과값 × 점수만큼 소속 점수가 오르거나(+) 깎인다(-).
#   game_counters: affects_house(영향 여부), house_interval_minutes(시간 간격), house_amount(결과값 1점당 소속 점수), house_applied_at(마지막으로 반영한 때)
#   game_house_points.game_counter_id: 어느 누적 수치로 받은 점수인가 (소속 점수 화면의 누적 수치 탭)
class AddHousePointsToGameCounters < ActiveRecord::Migration[8.0]
  def change
    add_column :game_counters, :affects_house, :boolean, null: false, default: false, if_not_exists: true
    add_column :game_counters, :house_interval_minutes, :integer, null: false, default: 60, if_not_exists: true
    add_column :game_counters, :house_amount, :integer, null: false, default: 1, if_not_exists: true
    add_column :game_counters, :house_applied_at, :datetime, if_not_exists: true
    add_column :game_house_points, :game_counter_id, :bigint, if_not_exists: true
  end
end
