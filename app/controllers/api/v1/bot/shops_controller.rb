# frozen_string_literal: true

# 자동봇 [상점]·[구매]·[설명]·[사용]이 읽는 상점 (예전 상점 시트)
class Api::V1::Bot::ShopsController < Api::V1::Bot::BaseController
  def index
    render json: GameShop.includes(:items).map { |shop|
      {
        name: shop.name,
        description: shop.description,
        items: shop.items.map do |item|
          { name: item.name, price: item.price, description: item.description, usable: item.usable, stat: item.stat_name, value: item.stat_value }
        end,
      }
    }
  end
end
