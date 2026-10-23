# frozen_string_literal: true

# 마니또 (관리 > RP > 마니또 설정): 캐릭터(A)가 상대(B)에게 몰래 말해야 하는 단어, 그리고 사용·추측 기록
class CreateGameManito < ActiveRecord::Migration[8.0]
  def change
    create_table :game_manito_words do |t|
      t.references :account, null: false, foreign_key: { on_delete: :cascade }                       # 말하는 사람 (A)
      t.references :target_account, null: false, foreign_key: { to_table: :accounts, on_delete: :cascade } # 들어야 하는 사람 (B)
      t.jsonb :words, null: false, default: []
      t.integer :uses, null: false, default: 0
      t.datetime :caught_at
      t.timestamps
    end
    add_index :game_manito_words, [:account_id, :target_account_id], unique: true

    create_table :game_manito_logs do |t|
      t.string :kind, null: false                                                                     # use / correct / wrong
      t.references :account, null: false, foreign_key: { on_delete: :cascade }                       # use: 말한 A, correct·wrong: 추측한 B
      t.references :other_account, null: false, foreign_key: { to_table: :accounts, on_delete: :cascade }
      t.string :word, null: false, default: ''
      t.bigint :status_id
      t.boolean :rewarded, null: false, default: false
      t.integer :money, null: false, default: 0
      t.jsonb :items, null: false, default: []
      t.integer :points, null: false, default: 0
      t.datetime :stolen_at
      t.timestamps
    end
    add_index :game_manito_logs, [:account_id, :kind, :created_at]
    add_index :game_manito_logs, [:status_id, :other_account_id, :kind], unique: true, where: 'status_id IS NOT NULL'
  end
end
