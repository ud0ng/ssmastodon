# frozen_string_literal: true

# 웹 글쓰기 패널 아래 재화 | 인벤토리 | 전적 버튼과 재화·인벤토리 화면: 내 재화·재화 기록·인벤토리·전적
class Api::V1::System::WalletsController < Api::BaseController
  include RoutingHelper

  RECORDS = 50

  before_action -> { doorkeeper_authorize! :read }
  before_action :require_user!

  def show
    character = GameCharacter.for(current_account)
    shop_items = GameShopItem.all.index_by { |item| Game::Wallet.key(item.name) }
    results = GamePlayer.joins(:session).where(account: current_account, game_sessions: { status: 'finished' }).group(:result).count

    render json: {
      currency: Game::Config.for('common')['currency_name'],
      money: character.money,
      item_count: character.item_count,
      record: { win: results['win'].to_i, lose: results['lose'].to_i, draw: results['draw'].to_i },
      inventory: Array(character.inventory).map { |item| inventory_json(item, shop_items[Game::Wallet.key(item['name'])]) },
      records: GameReward.where(account: current_account).order(id: :desc).limit(RECORDS).map { |record| record_json(record) },
    }
  end

  private

  def inventory_json(item, shop_item)
    {
      name: item['name'],
      count: item['count'].to_i,
      note: item['note'].to_s,
      description: shop_item&.description.to_s,
      image: shop_item&.image.present? ? full_asset_url(shop_item.image.url(:small)) : nil,
    }
  end

  def record_json(record)
    {
      id: record.id.to_s,
      kind: record.kind,
      kind_name: I18n.t("admin.games.shop.kinds.#{record.kind}", default: record.kind),
      money: record.money,
      items: Array(record.items).map { |item| { name: item['name'], count: item['count'].to_i } },
      reason: reason_label(record.reason),
      created_at: record.created_at.iso8601,
    }
  end

  # 컨텐츠 보상의 'game:jellybean' 같은 사유는 컨텐츠 이름으로
  def reason_label(reason)
    key = reason.to_s.split(':').last
    Game::Kinds.keys.include?(key) ? Game::Kinds.fetch(key).display_name : reason.to_s
  end
end
