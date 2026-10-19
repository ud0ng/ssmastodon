# frozen_string_literal: true

# 스킨(툿 배경) 효과를 없앤다: 효과 목록의 스킨 효과와 캐릭터에 붙어 있던 스킨을 지운다.
# 아이템 효과 상자나 누적 수치 규칙이 지운 효과를 가리키면 아무 일도 하지 않는다 (규칙은 외래 키로 함께 지워진다).
class RemoveSkinGameEffects < ActiveRecord::Migration[8.0]
  class Effect < ActiveRecord::Base
    self.table_name = 'game_effects'
  end

  class Character < ActiveRecord::Base
    self.table_name = 'game_characters'
  end

  def up
    Effect.where(slot: 'skin').delete_all
    Character.where("effects::text LIKE '%\"skin\"%'").find_each do |character|
      character.update_columns(effects: Array(character.effects).reject { |entry| entry['slot'] == 'skin' })
    end
  end

  def down; end
end
