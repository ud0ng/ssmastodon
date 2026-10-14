# frozen_string_literal: true

# 상점 아이템 이미지 (캐릭터 상세의 인벤토리 카드에도 쓴다)
class AddImageToGameShopItems < ActiveRecord::Migration[8.0]
  def change
    add_column :game_shop_items, :image_file_name, :string
    add_column :game_shop_items, :image_content_type, :string
    add_column :game_shop_items, :image_file_size, :integer
    add_column :game_shop_items, :image_updated_at, :datetime
  end
end
