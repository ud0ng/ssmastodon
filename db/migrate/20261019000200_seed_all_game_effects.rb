# frozen_string_literal: true

# 효과 목록에 모든 모양(소속 카드·칭호·데코·스킨 24가지)을 기본으로 넣는다. 이미 있는 모양은 그대로 둔다.
class SeedAllGameEffects < ActiveRecord::Migration[8.0]
  def up
    GameEffect.reset_column_information
    GameEffect.seed_missing!
  end

  def down; end
end
