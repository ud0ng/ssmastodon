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

  it 'saves the currency rules' do
    patch currency_admin_game_shops_path, params: { config: { transfer_enabled: '0', attendance_reward: '3', help_lines: "[가방] 가방\n" } }

    expect(Game::Config.for('currency')).to include('transfer_enabled' => false, 'attendance_reward' => 3, 'help_lines' => ['[가방] 가방'])
  end

  describe 'giving' do
    let(:harry) { Fabricate(:user).account }
    let(:ron) { Fabricate(:user).account }

    before do
      GameCharacter.for(harry).update!(money: 5)
      GameCharacter.for(ron)
      shop.items.create!(name: '초콜릿 개구리', price: 2)
    end

    it 'gives currency and an item to the chosen characters and records it' do
      post give_admin_game_shops_path, params: { account_ids: [harry.id, ron.id], money: '10', item: '초콜릿 개구리', count: '2', reason: '생일' }

      expect(GameCharacter.for(harry).reload).to have_attributes(money: 15)
      expect(GameCharacter.for(ron).reload.inventory.pluck('name', 'count')).to eq [['초콜릿 개구리', 2]]
      expect(GameReward.where(kind: 'admin', reason: '생일').count).to eq 2
    end

    it 'gives nothing without a target or anything to give' do
      post give_admin_game_shops_path, params: { account_ids: [harry.id], money: '0', item: '' }

      expect(response).to redirect_to(admin_game_shops_path(modal: 'shop-give'))
      expect(GameCharacter.for(harry).reload.money).to eq 5
    end
  end
end
