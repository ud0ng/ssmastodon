# frozen_string_literal: true

# 상점 아이템마다 [선물] 가능 여부 (사용 가능 여부 usable 은 예전부터 있다)
class AddGiftableToGameShopItems < ActiveRecord::Migration[8.0]
  def change
    add_column :game_shop_items, :giftable, :boolean, null: false, default: true, if_not_exists: true
  end
end
