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
    shop.items.create!(name: '부적', price: 1, giftable: false)
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
    expect(response.parsed_body['shops'].first['items'].pluck('name')).to eq %w(초콜릿\ 개구리 돌멩이 부적)
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

    it 'changes a stat only for a while (stat type) and permanently (status type)' do
      stat = GameCharacterField.base_stats.find_by(name: '힘')
      frog.update!(stat_minutes: 30)
      raw = character.raw_stat_value(stat)

      post '/api/v1/system/items/use', params: { name: '초콜릿 개구리' }, headers: headers

      expect(response).to have_http_status(200)
      expect(response.parsed_body['message']).to include('힘 +3 (30분 동안)')
      expect(character.raw_stat_value(stat)).to eq raw
      expect(character.stat_value(stat)).to eq stat.clamp(raw + 3)
      expect(character.active_effects.size).to eq 1

      travel_to 31.minutes.from_now do
        expect(character.stat_value(stat)).to eq raw
      end

      frog.update!(stat_name: '체력', stat_value: '30')
      status = GameCharacterField.statuses.find_by(name: '체력')
      before_value = character.status_value(status)

      post '/api/v1/system/items/use', params: { name: '초콜릿 개구리' }, headers: headers

      expect(response.parsed_body['message']).to include('체력 +30 (영구)')
      expect(character.status_value(status)).to eq before_value + 30
    end

    it 'uses a character item on the tagged account, even yourself, and tells the other one' do
      system = Fabricate(:account, username: 'system')
      allow(Game::System).to receive(:account).and_return(system)
      stat = GameCharacterField.base_stats.find_by(name: '힘')
      frog.update!(use_target: 'character')

      post '/api/v1/system/items/use', params: { name: '초콜릿 개구리' }, headers: headers
      expect(response).to have_http_status(422)
      expect(response.parsed_body['error']).to include('캐릭터를 골라')

      post '/api/v1/system/items/use', params: { name: '초콜릿 개구리', acct: friend.account.username }, headers: headers
      expect(response).to have_http_status(200)
      expect(character(friend.account).stat_value(stat)).to eq stat.clamp(character(friend.account).raw_stat_value(stat) + 3)
      expect(count('초콜릿 개구리')).to eq 2
      sent = user.account.statuses.reorder(:id).last
      expect(sent.mentions.map(&:account_id)).to eq [friend.account.id]

      post '/api/v1/system/items/use', params: { name: '초콜릿 개구리', acct: user.account.username }, headers: headers
      expect(response).to have_http_status(200)
      expect(response.parsed_body['message']).to include('자신에게')
    end

    it 'sends a DM to the system account for a special item' do
      system = Fabricate(:account, username: 'system')
      allow(Game::System).to receive(:account).and_return(system)
      frog.update!(use_target: 'special')

      post '/api/v1/system/items/use', params: { name: '초콜릿 개구리' }, headers: headers

      expect(response).to have_http_status(200)
      expect(count('초콜릿 개구리')).to eq 2
      dm = user.account.statuses.reorder(:id).last
      expect(dm).to have_attributes(visibility: 'direct')
      expect(dm.text).to include("@system [사용/초콜릿 개구리]")
    end

    context 'with special and wearable items' do
      let(:system) { Fabricate(:account, username: 'system') }
      let(:house) { GameHouse.create!(name: '그리핀도르', emoji: '🦁') }

      before do
        allow(Game::System).to receive(:account).and_return(system)
        GameCharacter.for(friend.account).update!(house: house)
        shop.items.create!(name: '동물 귀', price: 1, use_target: 'character', allow_random: true, wear_label: '동물 귀', stat_minutes: 1440, effect: '24시간 착용')
        shop.items.create!(name: '신고권', price: 1, use_target: 'special', special_kind: 'report', score_delta: -5, special_limit: 2)
        shop.items.create!(name: '똥폭탄', price: 1, use_target: 'special', special_kind: 'bomb', score_delta: -10)
        shop.items.create!(name: '호울러', price: 1, use_target: 'special', special_kind: 'howler', score_delta: -10)
        Game::Wallet.apply!([{ account: user.account, items: { '동물 귀' => 2, '신고권' => 2, '똥폭탄' => 1, '호울러' => 1 } }], kind: 'admin')
      end

      it 'puts a wearable on a chosen or random character for its time and tells them' do
        post '/api/v1/system/items/use', params: { name: '동물 귀', acct: 'random' }, headers: headers

        expect(response).to have_http_status(200)
        expect(response.parsed_body['message']).to include('동물 귀 착용 (24시간 동안)')
        expect(character(friend.account).wearing.pluck('label')).to eq ['동물 귀']
        expect(user.account.statuses.reorder(:id).last.text).to include('24시간 착용')

        post '/api/v1/system/items/use', params: { name: '동물 귀', acct: user.account.username }, headers: headers
        expect(character.wearing.pluck('label')).to eq ['동물 귀']

        travel_to 25.hours.from_now do
          expect(character(friend.account).wearing).to eq []
        end
      end

      it 'does not allow random for items that do not permit it' do
        shop.items.find_by(name: '동물 귀').update!(allow_random: false)

        post '/api/v1/system/items/use', params: { name: '동물 귀', acct: 'random' }, headers: headers

        expect(response).to have_http_status(422)
        expect(count('동물 귀')).to eq 2
      end

      it 'reports a character, deducts house points, counts reports and sends volunteer work at the limit' do
        post '/api/v1/system/items/use', params: { name: '신고권', acct: friend.account.username }, headers: headers
        expect(response).to have_http_status(200)
        expect(GameHousePoint.where(house: house).sum(:amount)).to eq(-5)
        expect(character(friend.account).reports_count).to eq 1

        post '/api/v1/system/items/use', params: { name: '신고권', acct: friend.account.username }, headers: headers
        expect(response.parsed_body['message']).to include('봉사활동')
        expect(character(friend.account).reports_count).to eq 0
        expect(GameHousePoint.where(house: house).sum(:amount)).to eq(-10)
        expect(user.account.statuses.where(visibility: :direct).count).to eq 2

        post '/api/v1/system/items/use', params: { name: '신고권', acct: user.account.username }, headers: headers
        expect(response).to have_http_status(422)
      end

      it 'bombs a chosen house and spreads a howler rumor to everyone' do
        post '/api/v1/system/items/use', params: { name: '똥폭탄', house_id: house.id }, headers: headers
        expect(response).to have_http_status(200)
        expect(GameHousePoint.where(house: house).sum(:amount)).to eq(-10)

        post '/api/v1/system/items/use', params: { name: '호울러' }, headers: headers
        expect(response).to have_http_status(422)

        post '/api/v1/system/items/use', params: { name: '호울러', text: '교장실 앞에 용이 나타났다 @모두' }, headers: headers
        expect(response).to have_http_status(200)
        rumor = system.statuses.reorder(:id).last
        expect(rumor.text).to include('용이 나타났다')
        expect(rumor.text).to_not include('@모두')
        expect(rumor.mentions.map(&:account_id)).to include(friend.account.id)
      end
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

    it 'refuses to gift items that cannot be gifted, in the web and from the bot' do
      Game::Wallet.apply!([{ account: user.account, items: { '부적' => 1 } }], kind: 'admin')

      post '/api/v1/system/items/gift', params: { name: '부적', acct: friend.account.username }, headers: headers

      expect(response).to have_http_status(422)
      expect(response.parsed_body['error']).to include('선물할 수 없는')
      expect(count('부적')).to eq 1

      get '/api/v1/system/wallet', headers: headers
      inventory = response.parsed_body['inventory']
      expect(inventory.find { |item| item['name'] == '부적' }).to include('giftable' => false)
      expect(inventory.find { |item| item['name'] == '초콜릿 개구리' }).to include('giftable' => true, 'usable' => true)
    end

    it 'sends a DM from the giver that mentions the receiver and the shop bot' do
      bot = Fabricate(:account, username: 'ssbot')
      Game::Config.merge!('common', 'bot_usernames' => 'ssbot')

      post '/api/v1/system/items/gift', params: { name: '초콜릿 개구리', acct: friend.account.username }, headers: headers

      status = user.account.statuses.reorder(:id).last
      expect(status).to have_attributes(visibility: 'direct')
      expect(status.text).to include("@#{friend.account.username}", '@ssbot', '초콜릿 개구리 1개를 선물했습니다')
      expect(status.mentions.pluck(:account_id)).to contain_exactly(friend.account.id, bot.id)
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

  it 'closes the shop when it is not unlocked' do
    Game::Config.merge!('currency', 'shop_open' => false)

    get '/api/v1/system/shop', headers: headers
    expect(response).to have_http_status(403)

    post '/api/v1/system/shop/purchase', params: { item_id: frog.id }, headers: headers
    expect(response).to have_http_status(403)
    expect(count('초콜릿 개구리')).to eq 0
  end

  it 'refuses items you do not have' do
    post '/api/v1/system/items/discard', params: { name: '투명 망토' }, headers: headers

    expect(response).to have_http_status(422)
  end
end
