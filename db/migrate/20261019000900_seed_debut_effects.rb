# frozen_string_literal: true

# 효과 목록에 데뷔탕트(칭호·데코·스킨)를 더한다. 이미 있는 모양은 그대로 둔다.
class SeedDebutEffects < ActiveRecord::Migration[8.0]
  def up
    GameEffect.reset_column_information
    GameEffect.seed_missing!
  end

  def down; end
end
