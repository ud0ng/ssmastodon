# frozen_string_literal: true

require 'rails_helper'

# 웹 상점 메뉴와 인벤토리 아이템 모달 ([구매] [사용] [선물] [버리기])
RSpec.describe 'API V1 System shop and items' do
  let(:user) { Fabricate(:user) }
  let(:friend) { Fabricate(:user) }
  let(:token) { Fabricate(:accessible_access_token, resource_owner_id: user.id, scopes: 'read write') }
  let(:headers) { { 'Authorization' => "Bearer #{token.token}" } }
  let(:shop) { GameShop.create!(name: '허니듀크', description: '과자 가게') }
  let(:frog) { shop.items.create!(name: '초콜릿 개구리', price: 5, description: '폴짝', stat_name: '힘', stat_value: '3') }

  before do
    GameCharacterField.ensure_defaults!
    frog
    shop.items.create!(name: '비밀 열쇠', price: nil)
    shop.items.create!(name: '돌멩이', price: 1, usable: false)
    GameCharacter.for(friend.account)
    Game::Wallet.apply!([{ account: user.account, money: 12 }], kind: 'admin')
  end

  def character(account = user.account)
    GameCharacter.for(account).reload
  end

  def count(name, account = user.account)
    Array(character(account).inventory).find { |item| item['name'] == name }.to_h['count'].to_i
  end

  it 'lists shops without items that are not for sale' do
    get '/api/v1/system/shop', headers: headers

    expect(response).to have_http_status(200)
    expect(response.parsed_body).to include('money' => 12)
    expect(response.parsed_body['shops'].first['items'].pluck('name')).to eq %w(초콜릿\ 개구리 돌멩이)
  end

  it 'buys items and refuses when money runs out' do
    post '/api/v1/system/shop/purchase', params: { item_id: frog.id, count: 2 }, headers: headers

    expect(response).to have_http_status(200)
    expect(response.parsed_body['money']).to eq 2
    expect(count('초콜릿 개구리')).to eq 2

    post '/api/v1/system/shop/purchase', params: { item_id: frog.id }, headers: headers

    expect(response).to have_http_status(422)
    expect(response.parsed_body['error']).to include('부족')
  end

  context 'with items in the inventory' do
    before { Game::Wallet.apply!([{ account: user.account, items: { '초콜릿 개구리' => 3, '돌멩이' => 1 } }], kind: 'admin') }

    it 'uses an item and changes the stat' do
      stat = GameCharacterField.base_stats.find_by(name: '힘')
      before_value = character.stat_value(stat)

      post '/api/v1/system/items/use', params: { name: '초콜릿개구리' }, headers: headers

      expect(response).to have_http_status(200)
      expect(response.parsed_body['message']).to include('초콜릿 개구리를 사용했습니다.')
      expect(count('초콜릿 개구리')).to eq 2
      expect(character.stat_value(stat)).to eq stat.clamp(before_value + 3)
      expect(GameReward.where(account: user.account).order(:id).last.kind).to eq 'use'
    end

    it 'refuses an item whose stat is gone, like the bot' do
      frog.update_column(:stat_name, '없는 스탯')

      post '/api/v1/system/items/use', params: { name: '초콜릿 개구리' }, headers: headers

      expect(response).to have_http_status(422)
      expect(response.parsed_body['error']).to include('스탯이 없습니다')
      expect(count('초콜릿 개구리')).to eq 3
    end

    it 'refuses items that cannot be used' do
      post '/api/v1/system/items/use', params: { name: '돌멩이' }, headers: headers

      expect(response).to have_http_status(422)
      expect(count('돌멩이')).to eq 1
    end

    it 'gifts items to another member' do
      post '/api/v1/system/items/gift', params: { name: '초콜릿 개구리', count: 2, acct: friend.account.username }, headers: headers

      expect(response).to have_http_status(200)
      expect(count('초콜릿 개구리')).to eq 1
      expect(count('초콜릿 개구리', friend.account)).to eq 2
    end

    it 'mentions the receiver from the system account' do
      system = Fabricate(:account, username: 'system')
      allow(Game::System).to receive(:account).and_return(system)

      post '/api/v1/system/items/gift', params: { name: '초콜릿 개구리', acct: friend.account.username }, headers: headers

      status = system.statuses.last
      expect(status).to have_attributes(visibility: 'direct')
      expect(status.text).to include("@#{friend.account.username}", '초콜릿 개구리 1개를 선물했습니다')
      expect(status.mentions.pluck(:account_id)).to eq [friend.account.id]
    end

    it 'does not gift to yourself' do
      post '/api/v1/system/items/gift', params: { name: '초콜릿 개구리', acct: user.account.username }, headers: headers

      expect(response).to have_http_status(422)
      expect(count('초콜릿 개구리')).to eq 3
    end

    it 'discards items' do
      post '/api/v1/system/items/discard', params: { name: '초콜릿 개구리', count: 9 }, headers: headers

      expect(response).to have_http_status(200)
      expect(count('초콜릿 개구리')).to eq 0
      expect(GameReward.where(account: user.account).order(:id).last.kind).to eq 'consume'
    end
  end

  it 'refuses items you do not have' do
    post '/api/v1/system/items/discard', params: { name: '투명 망토' }, headers: headers

    expect(response).to have_http_status(422)
  end
end
