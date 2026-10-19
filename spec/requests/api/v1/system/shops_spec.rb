# frozen_string_literal: true

require 'rails_helper'

# 웹 상점 메뉴와 인벤토리 아이템 모달 ([구매] [사용] [선물] [버리기])
RSpec.describe 'API V1 System shop and items' do
  let(:user) { Fabricate(:user) }
  let(:friend) { Fabricate(:user) }
  let(:token) { Fabricate(:accessible_access_token, resource_owner_id: user.id, scopes: 'read write') }
  let(:headers) { { 'Authorization' => "Bearer #{token.token}" } }
  let(:shop) { GameShop.create!(name: '허니듀크', description: '과자 가게') }
  let(:frog) { shop.items.create!(name: '초콜릿 개구리', price: 5, description: '폴짝', item_effects: [{ type: 'stat', stat: '힘', value: '3', minutes: 60 }]) }

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

    it 'uses an item on a chosen character (yourself too) and changes the stat for a while' do
      stat = GameCharacterField.base_stats.find_by(name: '힘')
      raw = character.raw_stat_value(stat)

      post '/api/v1/system/items/use', params: { name: '초콜릿개구리' }, headers: headers
      expect(response).to have_http_status(422)
      expect(response.parsed_body['error']).to include('캐릭터를 골라')

      post '/api/v1/system/items/use', params: { name: '초콜릿개구리', acct: 'me' }, headers: headers

      expect(response).to have_http_status(200)
      expect(response.parsed_body['message']).to include('자신에게 초콜릿 개구리를 사용했습니다.', '힘 +3 (1시간 동안)')
      expect(count('초콜릿 개구리')).to eq 2
      expect(character.raw_stat_value(stat)).to eq raw
      expect(character.stat_value(stat)).to eq stat.clamp(raw + 3)
      expect(GameReward.where(account: user.account).order(:id).last.kind).to eq 'use'

      travel_to 61.minutes.from_now do
        expect(character.stat_value(stat)).to eq raw
      end
    end

    it 'changes a status value for good' do
      frog.update!(item_effects: [{ type: 'stat', stat: '체력', value: '30' }])
      status = GameCharacterField.statuses.find_by(name: '체력')
      before_value = character.status_value(status)

      post '/api/v1/system/items/use', params: { name: '초콜릿 개구리', acct: 'me' }, headers: headers

      expect(response.parsed_body['message']).to include('체력 +30')
      expect(character.status_value(status)).to eq before_value + 30
    end

    it 'keeps a permanent item after using it, and a normal one loses one' do
      frog.update!(permanent: true)

      post '/api/v1/system/items/use', params: { name: '초콜릿 개구리', acct: 'me' }, headers: headers

      expect(response).to have_http_status(200)
      expect(count('초콜릿 개구리')).to eq 3

      frog.update!(permanent: false)
      post '/api/v1/system/items/use', params: { name: '초콜릿 개구리', acct: 'me' }, headers: headers
      expect(count('초콜릿 개구리')).to eq 2
    end

    it 'refuses an item whose stat is gone, like the bot' do
      frog.update_column(:item_effects, [{ 'type' => 'stat', 'stat' => '없는 스탯', 'value' => '3', 'minutes' => 60 }])

      post '/api/v1/system/items/use', params: { name: '초콜릿 개구리', acct: 'me' }, headers: headers

      expect(response).to have_http_status(422)
      expect(response.parsed_body['error']).to include('스탯이 없습니다')
      expect(count('초콜릿 개구리')).to eq 3
    end

    it 'tags the other character in the toot it sends, so they get a mention' do
      system = Fabricate(:account, username: 'system')
      allow(Game::System).to receive(:account).and_return(system)
      stat = GameCharacterField.base_stats.find_by(name: '힘')

      post '/api/v1/system/items/use', params: { name: '초콜릿 개구리', acct: friend.account.username }, headers: headers

      expect(response).to have_http_status(200)
      expect(character(friend.account).stat_value(stat)).to eq stat.clamp(character(friend.account).raw_stat_value(stat) + 3)
      sent = user.account.statuses.reorder(:id).last
      expect(sent.text).to include("［사용/초콜릿 개구리/@#{friend.account.username}］")
      expect(sent.mentions.map(&:account_id)).to include(friend.account.id)
    end

    context 'with currency, special and effect items' do
      let(:system) { Fabricate(:account, username: 'system') }
      let(:house) { GameHouse.create!(name: '그리핀도르', emoji: '🦁') }

      before do
        allow(Game::System).to receive(:account).and_return(system)
        GameEffect.ensure_defaults!
        GameCharacter.for(friend.account).update!(house: house)
        Game::Wallet.apply!([{ account: friend.account, money: 3, items: { '돌멩이' => 1 } }], kind: 'admin')
        poop = GameEffect.find_by(slot: 'card', preset: 'poop')
        title = GameEffect.find_by(slot: 'title')
        shop.items.create!(name: '소매치기', price: 1, item_effects: [{ type: 'currency', currency: 'money', value: '-5' }, { type: 'currency', currency: 'item', item: '돌멩이', value: '-1' }])
        shop.items.create!(name: '똥폭탄', price: 1, item_effects: [{ type: 'currency', currency: 'house_points', value: '-10' }, { type: 'fx', target: 'house', effect_id: poop.id, minutes: 2, unit: 'hour' }])
        shop.items.create!(name: '왕관', price: 1, item_effects: [{ type: 'fx', target: 'character', effect_id: title.id, minutes: 1, unit: 'day' }])
        shop.items.create!(name: '호울러', price: 1, item_effects: [{ type: 'special', kind: 'rumor', text: '연회장에 호울러가 울린다' }])
        shop.items.create!(name: '부엉이', price: 1, item_effects: [{ type: 'special', kind: 'staff' }])
        Game::Wallet.apply!([{ account: user.account, items: { '소매치기' => 1, '똥폭탄' => 1, '왕관' => 1, '호울러' => 1, '부엉이' => 1 } }], kind: 'admin')
      end

      it 'takes money and items from the chosen character, only as much as they have' do
        post '/api/v1/system/items/use', params: { name: '소매치기', acct: friend.account.username }, headers: headers

        expect(response).to have_http_status(200)
        expect(character(friend.account).money).to eq 0
        expect(count('돌멩이', friend.account)).to eq 0
        expect(response.parsed_body['message']).to include('-3', '돌멩이 -1개')
      end

      it 'bombs a chosen house and puts an effect on its card for a while' do
        post '/api/v1/system/items/use', params: { name: '똥폭탄', house_id: house.id }, headers: headers

        expect(response).to have_http_status(200)
        expect(GameHousePoint.where(house: house).sum(:amount)).to eq(-10)
        expect(Game::Fx.house_preset(house.reload)).to eq 'poop'
        bomb = user.account.statuses.reorder(:id).last
        expect(bomb).to have_attributes(visibility: 'private')
        expect(bomb.text).to include('［사용/똥폭탄/그리핀도르］')

        get '/api/v1/system/wallet', headers: headers
        expect(response.parsed_body['houses'].find { |item| item['name'] == '그리핀도르' }['fx']).to eq 'poop'

        Game::Config.merge!('currency', 'effects_enabled' => false)
        expect(Game::Fx.house_preset(house.reload)).to be_nil

        travel_to 3.hours.from_now do
          Game::Config.merge!('currency', 'effects_enabled' => true)
          expect(Game::Fx.house_preset(house.reload)).to be_nil
        end
      end

      it 'puts a title effect on the chosen character, shown on their toots' do
        post '/api/v1/system/items/use', params: { name: '왕관', acct: friend.account.username }, headers: headers

        expect(response).to have_http_status(200)
        expect(Game::Fx.for_account_id(friend.account.id)).to eq('title' => 'gold')
        get '/api/v1/system/fx', headers: headers
        expect(response.parsed_body['accounts']).to eq(friend.account.id.to_s => { 'title' => 'gold' })

        Game::Config.merge!('currency', 'effects_enabled' => false)
        get '/api/v1/system/fx', headers: headers
        expect(response.parsed_body['accounts']).to eq({})
      end

      it 'adds to a counter like reports and puts the effect for each count reached' do
        counter = GameCounter.create!(name: '신고')
        deco = GameEffect.find_by(slot: 'deco', preset: 'hearts')
        poop = GameEffect.find_by(slot: 'card', preset: 'poop')
        counter.rules.create!(threshold: 2, game_effect_id: deco.id, minutes: 60)
        counter.rules.create!(threshold: 3, game_effect_id: poop.id, minutes: 60)
        shop.items.create!(name: '신고권', price: 1, item_effects: [{ type: 'counter', counter_id: counter.id, value: '2' }])
        Game::Wallet.apply!([{ account: user.account, items: { '신고권' => 2 } }], kind: 'admin')

        post '/api/v1/system/items/use', params: { name: '신고권', acct: friend.account.username }, headers: headers
        expect(response).to have_http_status(200)
        expect(response.parsed_body['message']).to include('신고 +2 (누적 2회)', '2회 누적')
        expect(Game::Fx.for_account_id(friend.account.id)).to eq('deco' => 'hearts')
        expect(Game::Fx.house_preset(house.reload)).to be_nil

        post '/api/v1/system/items/use', params: { name: '신고권', acct: friend.account.username }, headers: headers
        expect(counter.count_for(character(friend.account))).to eq 4
        expect(Game::Fx.house_preset(house.reload)).to eq 'poop'
        sent = user.account.statuses.reorder(:id).last
        expect(sent.mentions.map(&:account_id)).to include(friend.account.id)
      end

      it 'posts the hall text to followers, spreads a rumor to everyone and sends a staff DM to the system account' do
        post '/api/v1/system/items/use', params: { name: '호울러' }, headers: headers
        expect(response).to have_http_status(422)

        post '/api/v1/system/items/use', params: { name: '호울러', text: '교장실 앞에 용이 나타났다 @모두' }, headers: headers
        expect(response).to have_http_status(200)
        hall = system.statuses.reorder(:id).find { |status| status.text.include?('연회장에 호울러가 울린다') }
        expect(hall).to have_attributes(visibility: 'private')
        expect(hall.mentions).to be_empty
        rumors = system.statuses.reorder(:id).select { |status| status.text.include?('용이 나타났다') && status.mentions.any? }
        expect(rumors.flat_map { |status| status.mentions.map(&:account_id) }).to include(friend.account.id, user.account.id)
        expect(rumors.map { |status| status.mentions.size }.uniq).to eq [1]
        expect(rumors.map(&:text).join).to_not include('@모두')
        expect(rumors.first.text).to include("연회장에 호울러가 울린다\n\n교장실 앞에 용이 나타났다")
        # 순서: 쓴 사람의 시스템 DM → 연회장 문구 툿 → 모든 캐릭터에게 내용 DM
        expect(user.account.statuses.reorder(:id).find { |status| status.text.include?('［사용/호울러/') }.id).to be < hall.id
        expect(hall.id).to be < rumors.map(&:id).min
        expect(response.parsed_body['message']).to include('명에게 전달')
        secret = user.account.statuses.reorder(:id).last
        expect(secret).to have_attributes(visibility: 'direct')
        expect(secret.mentions.map(&:account_id)).to eq [system.id]

        post '/api/v1/system/items/use', params: { name: '부엉이' }, headers: headers
        expect(response).to have_http_status(200)
        dm = user.account.statuses.reorder(:id).last
        expect(dm).to have_attributes(visibility: 'direct')
        expect(dm.text).to include('@system', '［사용/부엉이］')
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
      expect(status.text).to include("@#{friend.account.username}", '@ssbot', '［양도/초콜릿 개구리: 1/', '초콜릿 개구리 1개를 선물했습니다')
      expect(status.text).to_not include('[양도')
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
