# frozen_string_literal: true

# 시스템 계정이 올린 컨텐츠 툿마다 그 순간의 컨텐츠 상태 (PC 웹에서 툿을 카드 화면으로 보여 줄 때 쓴다)
class CreateGameEvents < ActiveRecord::Migration[8.0]
  def change
    create_table :game_events, if_not_exists: true do |t|
      t.references :game_session, null: false, foreign_key: { on_delete: :cascade }
      t.references :status, null: false, foreign_key: { on_delete: :cascade }, index: { unique: true }
      t.jsonb :payload, null: false, default: {}
      t.timestamps
    end
  end
end
