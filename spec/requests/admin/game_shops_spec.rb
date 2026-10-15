# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Admin shop' do
  before do
    sign_in Fabricate(:admin_user)
    GameCharacterField.ensure_defaults!
  end

  let(:shop) { GameShop.create!(name: '허니듀크') }

  it 'adds a shop and an item that is not for sale' do
    post admin_game_shops_path, params: { game_shop: { name: '올리밴더스', description: '지팡이' } }
    shop = GameShop.find_by(name: '올리밴더스')

    post admin_game_shop_items_path, params: { game_shop_item: { game_shop_id: shop.id, name: '딱총나무 지팡이', price: '', usable: '0', stat_name: '', stat_value: '9' } }

    expect(shop.items.first).to have_attributes(name: '딱총나무 지팡이', price: nil, usable: false, stat_value: '')
  end

  it 'refuses an item that changes a stat that does not exist or with a bad amount' do
    post admin_game_shop_items_path, params: { game_shop_item: { game_shop_id: shop.id, name: '사과', price: '1', stat_name: '지능', stat_value: '1' } }
    post admin_game_shop_items_path, params: { game_shop_item: { game_shop_id: shop.id, name: '배', price: '1', stat_name: '힘', stat_value: '세 개' } }

    expect(GameShopItem.count).to eq 0
    expect(response).to redirect_to(admin_game_shops_path(modal: 'item-add'))
  end

  it 'saves shop commands without touching the staff commands, and staff accounts can be cleared' do
    patch currency_admin_game_shops_path, params: { config: { admin_usernames: ['', 'manager', 'luna'], cmd_money_add: '돈 주기' } }
    patch currency_admin_game_shops_path, params: { config: { cmd_buy: '사기', transfer_enabled: '0' } }

    expect(Game::Config.for('currency')).to include('cmd_buy' => '사기', 'transfer_enabled' => false, 'cmd_money_add' => '돈 주기', 'admin_usernames' => %w(manager luna))

    patch currency_admin_game_shops_path, params: { config: { admin_usernames: [''] } }
    expect(Game::Config.for('currency')['admin_usernames']).to eq []
  end
end
