# frozen_string_literal: true

# 누적 수치: 최대 누적치(max_count)와 상성 수치(opposite_id, 서로 상쇄), 누적 효과의 '최대치일 때'(at_max)·'영구'(permanent),
# 누적 수치 기록(game_counter_logs). 기본 수치는 신고(최대 5) ↔ 칭찬(최대 5).
class AddLimitsToGameCounters < ActiveRecord::Migration[8.0]
  class Counter < ActiveRecord::Base
    self.table_name = 'game_counters'
  end

  def up
    add_column :game_counters, :max_count, :integer, if_not_exists: true
    add_column :game_counters, :opposite_id, :bigint, if_not_exists: true
    add_column :game_counter_rules, :at_max, :boolean, null: false, default: false, if_not_exists: true
    add_column :game_counter_rules, :permanent, :boolean, null: false, default: false, if_not_exists: true

    create_table :game_counter_logs, if_not_exists: true do |t|
      t.references :account, null: false, foreign_key: { on_delete: :cascade }
      t.references :game_counter, null: false, foreign_key: { on_delete: :cascade }
      t.integer :delta, null: false, default: 0
      t.integer :raw, null: false, default: 0
      t.integer :net, null: false, default: 0
      t.string :reason, null: false, default: ''
      t.string :actor, null: false, default: ''
      t.timestamps
    end
    add_index :game_counter_logs, :created_at, if_not_exists: true

    Counter.reset_column_information
    report = Counter.find_by(name: '신고') || Counter.create!(name: '신고', position: 0)
    praise = Counter.find_by(name: '칭찬') || Counter.create!(name: '칭찬', position: Counter.maximum(:position).to_i + 1)
    report.update_columns(max_count: 5, opposite_id: praise.id)
    praise.update_columns(max_count: 5, opposite_id: report.id)
  end

  def down
    drop_table :game_counter_logs, if_exists: true
    remove_column :game_counter_rules, :permanent, if_exists: true
    remove_column :game_counter_rules, :at_max, if_exists: true
    remove_column :game_counters, :opposite_id, if_exists: true
    remove_column :game_counters, :max_count, if_exists: true
  end
end
