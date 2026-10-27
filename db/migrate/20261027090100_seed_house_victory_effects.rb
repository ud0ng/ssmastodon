# frozen_string_literal: true

# 효과 목록에 기숙사전 승리 보상(그리핀도르·후플푸프·슬리데린·래번클로)의 소속 카드·칭호·데코·스킨을 더한다. 이미 있는 모양은 그대로 둔다.
class SeedHouseVictoryEffects < ActiveRecord::Migration[8.0]
  def up
    GameEffect.reset_column_information
    GameEffect.seed_missing!
  end

  def down; end
end
