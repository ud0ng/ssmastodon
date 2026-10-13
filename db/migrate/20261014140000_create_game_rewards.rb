# frozen_string_literal: true

# 컨텐츠 보상 기록 (돈·아이템). 캐릭터의 money/inventory 에 더하고 여기 남긴다.
class CreateGameRewards < ActiveRecord::Migration[8.0]
  def change
    create_table :game_rewards, if_not_exists: true do |t|
      t.references :account, null: false, foreign_key: { on_delete: :cascade }
      t.references :game_session, null: true, foreign_key: { on_delete: :nullify }
      t.integer :money, null: false, default: 0
      t.jsonb :items, null: false, default: []
      t.string :reason, null: false, default: ''
      t.timestamps
    end
  end
end
