# frozen_string_literal: true

# 상점 아이템 옵션: 같은 소속에 사용 불가능 (켜면 같은 소속 캐릭터·소속에 사용·양도·선물할 수 없다)
class AddBlockSameHouseToGameShopItems < ActiveRecord::Migration[8.0]
  def change
    add_column :game_shop_items, :block_same_house, :boolean, null: false, default: false, if_not_exists: true
  end
end
