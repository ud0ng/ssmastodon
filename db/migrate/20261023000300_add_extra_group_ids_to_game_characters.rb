# frozen_string_literal: true

# 기숙사·진영 말고 운영진이 더 만든 소속 종류(Game::GroupKinds)에서 캐릭터가 속한 소속: { 종류 키 => 소속 번호 }
class AddExtraGroupIdsToGameCharacters < ActiveRecord::Migration[8.0]
  def change
    add_column :game_characters, :extra_group_ids, :jsonb, null: false, default: {}
  end
end
