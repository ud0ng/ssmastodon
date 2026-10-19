# frozen_string_literal: true

# 자동봇 [상점]·[구매]·[설명]·[사용]이 읽는 상점 (예전 상점 시트)
class Api::V1::Bot::ShopsController < Api::V1::Bot::BaseController
  def index
    render json: GameShop.includes(:items).map { |shop|
      {
        name: shop.name,
        description: shop.description,
        items: shop.items.map do |item|
          # [사용]은 모두 서버가 처리한다 (/api/v1/bot/items/use). 예전 자동봇도 서버로 보내도록 use_target 은 special 로 둔다
          { name: item.name, price: item.price, description: item.description, usable: item.usable, permanent: item.permanent, giftable: item.giftable,
            use_target: 'special', effects: item.summary, needs: Game::ItemUse::Runner.needs(item) }
        end,
      }
    }
  end
end
