# frozen_string_literal: true

# 허니듀크 하나에 있던 기본 아이템을 RP / 컨텐츠 / 특수 상점으로 나누고, 효과 아이템을 '데코' 상점에 더한다 (Game::ShopLayout).
class SplitDefaultShops < ActiveRecord::Migration[8.0]
  def up
    return if Rails.env.test? # 시험 DB 에는 넣지 않는다 (시험이 직접 만든다)

    [GameShop, GameShopItem, GameEffect, GameCounterRule].each(&:reset_column_information)
    Game::ShopLayout.apply!
  end

  def down; end
end
