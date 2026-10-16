# frozen_string_literal: true

# 웹 '상점' 메뉴: 상점마다 파는 아이템(비매품 제외)과 내 재화, [구매]
class Api::V1::System::ShopsController < Api::BaseController
  include RoutingHelper

  MAX_COUNT = 99

  before_action -> { doorkeeper_authorize! :read }, only: [:show]
  before_action -> { doorkeeper_authorize! :write }, only: [:purchase]
  before_action :require_user!

  def show
    render json: {
      currency: currency,
      money: GameCharacter.for(current_account).money,
      shops: GameShop.includes(:items).filter_map { |shop| shop_json(shop) },
    }
  end

  def purchase
    item = GameShopItem.for_sale.find_by(id: params[:item_id])
    return render json: { error: '상점에 없는 아이템입니다.' }, status: 422 if item.nil?

    count = params[:count].to_i.clamp(1, MAX_COUNT)
    character = Game::Wallet.apply!([{ account: current_account, money: -item.price * count, items: { item.name => count } }],
                                    kind: 'purchase', detail: "#{item.name} #{count}개", actor: 'web').first
    render json: { message: "#{item.name} #{count}개#{Game::Text.particle('개', '을를')} 구매했습니다.", money: character.money }
  rescue Game::Wallet::Error => e
    render json: { error: e.message }, status: 422
  end

  private

  def currency
    Game::Config.for('common')['currency_name']
  end

  def shop_json(shop)
    items = shop.items.select(&:for_sale?)
    return if items.empty?

    {
      id: shop.id.to_s,
      name: shop.name,
      description: shop.description.to_s,
      items: items.map do |item|
        {
          id: item.id.to_s,
          name: item.name,
          price: item.price,
          description: item.description.to_s,
          usable: item.usable,
          image: item.image.present? ? full_asset_url(item.image.url(:small)) : nil,
        }
      end,
    }
  end
end
