# frozen_string_literal: true

# 캐릭터 명단 확장: 운영진이 정하는 항목(진영 등 고르기·글·숫자, 전투 스탯), 돈, 인벤토리
class AddProfileToGameCharacters < ActiveRecord::Migration[8.0]
  def change
    create_table :game_character_fields, if_not_exists: true do |t|
      t.string :name, null: false
      t.string :kind, null: false, default: 'select' # select / text / number
      t.string :section, null: false, default: 'profile' # profile(정보) / stat(전투 스탯)
      t.jsonb :choices, null: false, default: [] # select: [{ name, color }]
      t.integer :position, null: false, default: 0
      t.timestamps
    end

    add_column :game_characters, :profile, :jsonb, null: false, default: {}, if_not_exists: true
    add_column :game_characters, :money, :integer, null: false, default: 0, if_not_exists: true
    add_column :game_characters, :inventory, :jsonb, null: false, default: [], if_not_exists: true
  end
end
