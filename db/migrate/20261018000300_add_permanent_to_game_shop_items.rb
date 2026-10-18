# frozen_string_literal: true

# 영구 아이템: [사용] 해도 사라지지 않는다 (false 면 사용할 때 1개 없어진다 = 예전 동작)
class AddPermanentToGameShopItems < ActiveRecord::Migration[8.0]
  def change
    add_column :game_shop_items, :permanent, :boolean, null: false, default: false, if_not_exists: true
  end
end
