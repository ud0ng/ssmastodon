# frozen_string_literal: true

# 상점 (컨텐츠 설정 > 상점). 아이템은 GameShopItem. 자동봇 [상점]·[구매]가 /api/v1/bot/shop 으로 읽는다.
class GameShop < ApplicationRecord
  has_many :items, -> { order(:position, :id) }, class_name: 'GameShopItem', dependent: :destroy, inverse_of: :shop

  validates :name, presence: true, length: { maximum: 50 }, uniqueness: true
  validates :description, length: { maximum: 500 }

  default_scope { order(:position, :id) }
end
