# frozen_string_literal: true

# 캐릭터 관리 개편: 스탯(유형 스탯/상태 수치, 최소·최대, 수식)과 항목 설명
class AddStatDetailsToGameCharacterFields < ActiveRecord::Migration[8.0]
  def change
    add_column :game_character_fields, :stat_type, :string, null: false, default: 'stat', if_not_exists: true
    add_column :game_character_fields, :min_value, :integer, if_not_exists: true
    add_column :game_character_fields, :max_value, :integer, if_not_exists: true
    add_column :game_character_fields, :formula, :string, null: false, default: '', if_not_exists: true
    add_column :game_character_fields, :description, :text, null: false, default: '', if_not_exists: true
  end
end
