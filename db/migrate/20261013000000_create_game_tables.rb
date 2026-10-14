# frozen_string_literal: true

# 시스템 계정(@system)이 진행하는 게임 (해리포터 세계관): 기숙사, 캐릭터 명단, 게임 판, 기숙사 점수, 설정
class CreateGameTables < ActiveRecord::Migration[8.0]
  def change
    create_table :game_houses, if_not_exists: true do |t|
      t.string :name, null: false
      t.string :emoji, null: false, default: ''
      t.string :color, null: false, default: ''
      t.integer :position, null: false, default: 0
      t.timestamps
    end

    create_table :game_characters, if_not_exists: true do |t|
      t.references :account, null: false, foreign_key: { on_delete: :cascade }, index: { unique: true }
      t.references :game_house, foreign_key: { on_delete: :nullify }
      t.string :name, null: false, default: ''
      t.integer :grade
      t.text :note, null: false, default: ''
      t.jsonb :stats, null: false, default: {}
      t.timestamps
    end

    create_table :game_sessions, if_not_exists: true do |t|
      t.string :kind, null: false
      t.string :status, null: false, default: 'pending'
      t.string :visibility, null: false, default: 'private'
      t.jsonb :state, null: false, default: {}
      t.integer :turn, null: false, default: 0
      t.datetime :deadline_at
      t.bigint :root_status_id
      t.bigint :last_status_id
      t.datetime :finished_at
      t.timestamps
    end
    add_index :game_sessions, :status, if_not_exists: true

    create_table :game_players, if_not_exists: true do |t|
      t.references :game_session, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.references :account, null: false, foreign_key: { on_delete: :cascade }
      t.integer :seat, null: false, default: 0
      t.jsonb :state, null: false, default: {}
      t.string :result
      t.timestamps
    end
    add_index :game_players, [:game_session_id, :account_id], unique: true, if_not_exists: true

    create_table :game_house_points, if_not_exists: true do |t|
      t.references :game_house, null: false, foreign_key: { on_delete: :cascade }
      t.references :account, foreign_key: { on_delete: :nullify }
      t.references :game_session, foreign_key: { on_delete: :nullify }
      t.integer :amount, null: false
      t.string :reason, null: false, default: ''
      t.timestamps
    end

    create_table :game_configs, if_not_exists: true do |t|
      t.string :key, null: false, index: { unique: true }
      t.jsonb :data, null: false, default: {}
      t.timestamps
    end
  end
end
