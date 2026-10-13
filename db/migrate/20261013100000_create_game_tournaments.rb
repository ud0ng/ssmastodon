# frozen_string_literal: true

# 토너먼트제: 대진표(사람) 경기마다 컨텐츠·시간·선수를 운영진이 정하고, 이긴 경기 수가 많은 소속이 우승
class CreateGameTournaments < ActiveRecord::Migration[8.0]
  def change
    create_table :game_tournaments, if_not_exists: true do |t|
      t.string :name, null: false
      t.string :status, null: false, default: 'draft'
      t.integer :size, null: false
      t.integer :reward, null: false, default: 0
      t.references :winner_house, foreign_key: { to_table: :game_houses, on_delete: :nullify }
      t.datetime :finished_at
      t.timestamps
    end

    create_table :game_tournament_matches, if_not_exists: true do |t|
      t.references :game_tournament, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.integer :round, null: false
      t.integer :position, null: false
      t.string :kind
      t.datetime :scheduled_at
      t.references :player_a, foreign_key: { to_table: :accounts, on_delete: :nullify }
      t.references :player_b, foreign_key: { to_table: :accounts, on_delete: :nullify }
      t.references :winner, foreign_key: { to_table: :accounts, on_delete: :nullify }
      t.references :game_session, foreign_key: { on_delete: :nullify }
      t.string :status, null: false, default: 'waiting'
      t.timestamps
    end
    add_index :game_tournament_matches, [:game_tournament_id, :round, :position], unique: true, name: 'index_game_tournament_matches_on_slot', if_not_exists: true
  end
end
