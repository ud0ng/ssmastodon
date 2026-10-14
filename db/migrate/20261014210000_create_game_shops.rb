# frozen_string_literal: true

# 재화를 마스토돈으로: 상점(목록)·상점 아이템, 재화 기록(구매·사용·양도·출석·운영진 변경 등)
#   예전 자동봇 시트의 상점·관리·출석부·기록 워크시트를 대신한다. 자동봇은 /api/v1/bot 으로 읽고 쓴다.
class CreateGameShops < ActiveRecord::Migration[8.0]
  def change
    create_table :game_shops, if_not_exists: true do |t|
      t.string :name, null: false
      t.text :description, null: false, default: ''
      t.integer :position, null: false, default: 0
      t.timestamps
    end

    create_table :game_shop_items, if_not_exists: true do |t|
      t.references :game_shop, null: false, foreign_key: { on_delete: :cascade }
      t.string :name, null: false, index: { unique: true }
      t.integer :price # 비우면 비매품
      t.text :description, null: false, default: ''
      t.boolean :usable, null: false, default: true
      t.string :stat_name, null: false, default: ''  # [사용] 할 때 바뀌는 스탯
      t.string :stat_value, null: false, default: '' # 5, -20, 1d10, -(1d6+3)
      t.integer :position, null: false, default: 0
      t.timestamps
    end

    # game_rewards 를 재화 기록 전체로 쓴다 (컨텐츠 보상은 kind 'content')
    add_column :game_rewards, :kind, :string, null: false, default: 'content', if_not_exists: true
    add_column :game_rewards, :stats, :jsonb, null: false, default: {}, if_not_exists: true
    add_column :game_rewards, :actor, :string, null: false, default: '', if_not_exists: true
    safety_assured { add_index :game_rewards, [:account_id, :kind, :created_at], if_not_exists: true } # 작은 표
  end
end
