# frozen_string_literal: true

# 재화 기록·누적 수치 기록에 '상대'를 남긴다: 양도·사용 때 누가 누구에게 했는지 (웹 재화 화면 아이템 탭, 소속 점수 화면 벌점·상점 탭).
#   game_rewards.other_account_id 상대 계정, other_dir 'to'(내가 상대에게) / 'from'(상대가 나에게)
#   game_counter_logs.source_account_id 수치를 올려 준(아이템을 쓴) 계정
class AddCounterpartToRewardsAndCounterLogs < ActiveRecord::Migration[8.0]
  def change
    add_column :game_rewards, :other_account_id, :bigint, if_not_exists: true
    add_column :game_rewards, :other_dir, :string, null: false, default: '', if_not_exists: true
    add_column :game_counter_logs, :source_account_id, :bigint, if_not_exists: true
  end
end
