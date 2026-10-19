# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Game::ShopLayout do
  let!(:honey) { GameShop.create!(name: '허니듀크') }

  before { GameEffect.seed_missing! }

  it 'moves existing items into their shops, renames ink sets, adds only the missing ones and can run twice' do
    honey.items.create!(name: '호울러', price: 20)
    honey.items.create!(name: '그리핀도르 색잉크', price: 20)
    honey.items.create!(name: '초콜릿 개구리', price: 5)

    2.times { described_class.apply! }

    expect(GameShopItem.find_by(name: '호울러').shop.name).to eq '특수'
    expect(GameShopItem.find_by(name: '그리핀도르 깃펜세트').shop.name).to eq 'RP'
    expect(GameShopItem.exists?(name: '그리핀도르 색잉크')).to be false
    expect(GameShopItem.find_by(name: '장소 협의권').shop.name).to eq '컨텐츠'
    expect(GameShopItem.find_by(name: '초콜릿 개구리').shop).to eq honey
    expect(GameShopItem.where(name: '호울러').count).to eq 1
  end

  it 'adds house effects and title+deco sets, leaving out counter effects and the debut' do
    counter = GameCounter.create!(name: '벌점')
    dung = GameEffect.find_by(slot: 'title', preset: 'dung1')
    counter.rules.create!(threshold: 1, game_effect_id: dung.id, minutes: 60)

    described_class.apply!

    shop = GameShop.find_by(name: '데코')
    gold_house = shop.items.find_by(name: '블링블링 소속 데코')
    expect(gold_house.price).to eq 20
    expect(gold_house.item_effects).to eq [{ 'type' => 'fx', 'target' => 'house', 'effect_id' => GameEffect.find_by(slot: 'card', preset: 'gold').id, 'minutes' => 60 }]
    expect(shop.items.find_by(name: '금빛 반짝 세트').item_effects.pluck('effect_id')).to eq [GameEffect.find_by(slot: 'title', preset: 'gold').id, GameEffect.find_by(slot: 'deco', preset: 'gold').id]
    expect(GameShopItem.where('name LIKE ?', '%데뷔탕트%')).to be_empty
    expect(GameShopItem.exists?(name: '똥 한 덩이 세트')).to be false
  end
end
