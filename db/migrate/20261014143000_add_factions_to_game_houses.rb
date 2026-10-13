# frozen_string_literal: true

# 진영을 기숙사처럼: game_houses.category (house 기숙사 / faction 진영), 캐릭터마다 game_faction_id.
# 캐릭터 명단 항목으로 넣어 두었던 '진영'(고르기)은 진영 목록과 캐릭터 진영으로 옮기고 항목은 지운다.
class AddFactionsToGameHouses < ActiveRecord::Migration[8.0]
  class House < ApplicationRecord
    self.table_name = 'game_houses'
  end

  class Character < ApplicationRecord
    self.table_name = 'game_characters'
  end

  class Field < ApplicationRecord
    self.table_name = 'game_character_fields'
  end

  def up
    add_column :game_houses, :category, :string, null: false, default: 'house', if_not_exists: true
    # 캐릭터 수십 명짜리 작은 표라 잠금 걱정 없음
    safety_assured { add_reference :game_characters, :game_faction, foreign_key: { to_table: :game_houses, on_delete: :nullify }, if_not_exists: true }

    House.reset_column_information
    Character.reset_column_information
    return unless table_exists?(:game_character_fields)

    field = Field.find_by(name: '진영', kind: 'select')
    return if field.nil?

    ids = Array(field.choices).each_with_index.to_h do |choice, index|
      house = House.create!(name: choice['name'], emoji: '', color: choice['color'].to_s, position: index, category: 'faction')
      [choice['name'], house.id]
    end
    Character.find_each do |character|
      profile = character.profile || {}
      value = profile.delete(field.id.to_s)
      character.update_columns(profile: profile, game_faction_id: ids[value]) if value
    end
    field.destroy!
  end

  def down
    remove_reference :game_characters, :game_faction, foreign_key: { to_table: :game_houses }, if_exists: true
    remove_column :game_houses, :category, if_exists: true
  end
end
