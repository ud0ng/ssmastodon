# frozen_string_literal: true

require 'rails_helper'

# 글쓰기창 아래 재화 | 인벤토리 | 전적과 재화·인벤토리 화면
RSpec.describe 'API V1 System wallet' do
  let(:user) { Fabricate(:user) }
  let(:friend) { Fabricate(:user) }
  let(:token) { Fabricate(:accessible_access_token, resource_owner_id: user.id, scopes: 'read write') }
  let(:headers) { { 'Authorization' => "Bearer #{token.token}" } }

  before do
    GameCharacterField.ensure_defaults!
    GameShop.create!(name: '허니듀크').items.create!(name: '초콜릿 개구리', price: 2, description: '폴짝')
    Game::Wallet.apply!([{ account: user.account, money: 30, items: { '초콜릿 개구리' => 3, '투명 망토' => 1 } }], kind: 'admin', detail: '생일')
    Game::Wallet.apply!([{ account: user.account, money: -2 }], kind: 'purchase', detail: '사과 1개')
    Game::Wallet.apply!([{ account: user.account, items: { '투명 망토' => -1 } }], kind: 'consume', detail: '투명 망토 1개 버림')
  end

  it 'shows my currency, totals, inventory and record' do
    get '/api/v1/system/wallet', headers: headers

    expect(response).to have_http_status(200)
    body = response.parsed_body
    expect(body).to include('currency' => '갈레온', 'money' => 28, 'gained' => 30, 'spent' => -2, 'item_count' => 3,
                            'record' => { 'win' => 0, 'lose' => 0, 'draw' => 0 })
    expect(body['inventory']).to contain_exactly(a_hash_including('name' => '초콜릿 개구리', 'count' => 3, 'description' => '폴짝'))
  end

  it 'shows my toot totals from the daily activity snapshot: the days stored so far plus what today has added' do
    today = Game::ActivitySnapshot.today
    GameActivityDay.create!(day: today, account_id: user.account.id, posts: 3, post_chars: 210, dms: 1, dm_chars: 20)
    GameActivityDay.create!(day: today - 1, account_id: user.account.id, posts: 8, post_chars: 560)
    GameActivityDay.create!(day: today - 5, account_id: user.account.id, posts: 10, post_chars: 900)
    GameActivityDay.create!(day: today - 1, account_id: friend.account.id, posts: 99, post_chars: 9_999)

    get '/api/v1/system/wallet', headers: headers

    expect(response.parsed_body).to include('posts' => 22, 'post_chars' => 1_690) # DM 포함 전체
    expect(response.parsed_body).not_to have_key('activity')
  end

  it 'shows my toots per season under the total, each season over its own dates' do
    today = Game::ActivitySnapshot.today
    GameSeason.create!(name: '시즌1', status: 'finished', starts_on: today - 6, ends_on: today - 4, finished_at: Time.current)
    GameSeason.create!(name: '시즌2', status: 'running', starts_on: today - 3)
    GameActivityDay.create!(day: today - 5, account_id: user.account.id, posts: 10, post_chars: 900)
    GameActivityDay.create!(day: today - 1, account_id: user.account.id, posts: 8, post_chars: 560, dms: 1, dm_chars: 20)
    GameActivityDay.create!(day: today, account_id: user.account.id, posts: 3, post_chars: 210)

    get '/api/v1/system/wallet', headers: headers

    expect(response.parsed_body['seasons']).to eq([
      { 'name' => '시즌2', 'running' => true, 'posts' => 12, 'chars' => 790 },
      { 'name' => '시즌1', 'running' => false, 'posts' => 10, 'chars' => 900 },
    ])
  end

  it 'shows the group points for the bottom of the compose panel' do
    GameHouse.ensure_defaults!
    house = GameHouse.houses.first
    GameCharacter.for(user.account).update!(house: house)
    GameHousePoint.create!(house: house, amount: 12, reason: 'test')

    get '/api/v1/system/wallet', headers: headers

    body = response.parsed_body
    expect(body).to include('house_term' => '기숙사', 'my_house_id' => house.id.to_s)
    expect(body['houses']).to include('id' => house.id.to_s, 'name' => house.name, 'color' => house.color, 'total' => 12, 'counters' => 0, 'fx' => nil, 'fx_until' => nil)
    expect(body['houses'].size).to eq GameHouse.houses.count
  end

  it 'sums the result values of the house point counters per house so a change can raise the badge' do
    GameHouse.ensure_defaults!
    report = GameCounter.create!(name: '벌점', max_count: 5, affects_house: true)
    house = GameHouse.houses.first
    GameCharacter.for(user.account).update!(house: house)
    report.add!(GameCharacter.for(user.account), 3)

    get '/api/v1/system/wallet', headers: headers

    expect(response.parsed_body['houses'].find { |entry| entry['id'] == house.id.to_s }['counters']).to eq 3
  end

  it 'pages the history and filters it' do
    get '/api/v1/system/wallet/records', headers: headers

    expect(response.parsed_body['records'].pluck('kind', 'money', 'reason')).to eq [['consume', 0, '투명 망토 1개 버림'], ['purchase', -2, '사과 1개'], ['admin', 30, '생일']]
    expect(response.parsed_body['next_max_id']).to be_nil

    get '/api/v1/system/wallet/records', params: { filter: 'spend' }, headers: headers
    expect(response.parsed_body['records'].pluck('kind')).to eq %w(purchase)

    get '/api/v1/system/wallet/records', params: { filter: 'items' }, headers: headers
    expect(response.parsed_body['records'].pluck('kind')).to eq %w(consume admin)

    stub_const('Api::V1::System::WalletsController::RECORDS', 2)
    get '/api/v1/system/wallet/records', headers: headers
    next_max_id = response.parsed_body['next_max_id']
    get '/api/v1/system/wallet/records', params: { max_id: next_max_id }, headers: headers
    expect(response.parsed_body['records'].pluck('kind')).to eq %w(admin)
  end

  it 'gifts money and mentions the receiver' do
    system = Fabricate(:account, username: 'system')
    allow(Game::System).to receive(:account).and_return(system)

    post '/api/v1/system/wallet/gift', params: { acct: friend.account.username, amount: 10 }, headers: headers

    expect(response).to have_http_status(200)
    expect(GameCharacter.for(user.account).reload.money).to eq 18
    expect(GameCharacter.for(friend.account).reload.money).to eq 10
    expect(user.account.statuses.reorder(:id).last.text).to include("@#{friend.account.username}", '10갈레온을 선물했습니다')

    post '/api/v1/system/wallet/gift', params: { acct: friend.account.username, amount: 100 }, headers: headers
    expect(response).to have_http_status(422)
  end

  it 'tells the web client when the wallet changes' do
    redis = instance_double(Redis, publish: 1)
    allow(GameReward).to receive(:new).and_wrap_original { |original, *args| original.call(*args).tap { |record| allow(record).to receive(:redis).and_return(redis) } }

    Game::Wallet.apply!([{ account: user.account, money: 1 }], kind: 'admin')

    expect(redis).to have_received(:publish).with("timeline:#{user.account.id}", a_string_including('wallet.changed'))
  end

  it 'needs a signed-in user' do
    get '/api/v1/system/wallet'

    expect(response).to have_http_status(401)
  end
  it 'shows who an item or currency was given by or to in the history' do
    Game::Wallet.apply!([{ account: user.account, items: { '초콜릿 개구리' => -1 }, other: friend.account, other_dir: 'to' },
                         { account: friend.account, items: { '초콜릿 개구리' => 1 }, other: user.account, other_dir: 'from' }], kind: 'transfer', detail: '초콜릿 개구리 1개 → 친구')
    Game::Wallet.apply!([{ account: user.account, items: { '초콜릿 개구리' => 2 }, other: friend.account, other_dir: 'from' }], kind: 'transfer', detail: '받음')

    get '/api/v1/system/wallet/records', headers: headers

    others = response.parsed_body['records'].filter_map { |record| record['other']&.slice('acct', 'dir') }
    expect(others).to eq [{ 'acct' => friend.account.acct, 'dir' => 'from' }, { 'acct' => friend.account.acct, 'dir' => 'to' }]
  end
  it 'leaves test plays out of the record' do
    real = GameSession.create!(kind: 'jellybean', status: 'finished', finished_at: Time.now.utc, visibility: 'private')
    real.players.create!(account: user.account, seat: 0, result: 'win')
    test = GameSession.create!(kind: 'flying', status: 'finished', finished_at: Time.now.utc, visibility: 'direct', state: { 'test' => true })
    test.players.create!(account: user.account, seat: 0, result: 'win')

    get '/api/v1/system/wallet', headers: headers

    expect(response.parsed_body['record']).to eq('win' => 1, 'lose' => 0, 'draw' => 0)
  end
  it 'badges the events menu for someone who was invited to a waiting room and has not answered yet' do
    friend = Fabricate(:user)
    GameCharacter.for(friend.account)
    session = GameSession.create!(kind: 'flying', status: 'lobby', visibility: 'private', state: { 'mode' => 'event', 'invited' => [friend.account.id], 'lobby' => { 'ready' => [], 'start_at' => nil } })
    friend_headers = { 'Authorization' => "Bearer #{Fabricate(:accessible_access_token, resource_owner_id: friend.id, scopes: 'read write').token}" }

    get '/api/v1/system/wallet', headers: friend_headers
    expect(response.parsed_body['todo'].pluck('session_id')).to include(session.id.to_s)

    get '/api/v1/system/wallet', headers: headers
    expect(response.parsed_body['todo'].pluck('session_id')).to_not include(session.id.to_s)
  end
  describe 'the "cannot be used on the same house" option' do
    let(:house) { GameHouse.create!(name: '그리핀도르', color: '#ae0001', category: 'house') }
    let(:other_house) { GameHouse.create!(name: '슬리데린', color: '#1a472a', category: 'house') }
    let(:ron) { Fabricate(:account, username: 'ron') }
    let(:effects) { [{ 'type' => 'currency', 'currency' => 'house_points', 'value' => '10' }] }

    before do
      shop = GameShop.create!(name: '특수')
      shop.items.create!(name: '응원봉', price: 5, block_same_house: true, item_effects: effects)
      shop.items.create!(name: '자유봉', price: 5, item_effects: effects)
      GameCharacter.for(user.account).update!(house: house)
      Game::Wallet.apply!([{ account: user.account, items: { '응원봉' => 2, '자유봉' => 2 } }], kind: 'admin')
    end

    it 'cannot be gifted to someone in the same house, but can to another house' do
      GameCharacter.for(ron).update!(house: house)
      expect { Game::Wallet.apply!([{ account: user.account, items: { '응원봉' => -1 } }, { account: ron, items: { '응원봉' => 1 } }], kind: 'transfer') }
        .to raise_error(Game::Wallet::Error, /같은 소속/)

      GameCharacter.for(ron).update!(house: other_house)
      expect { Game::Wallet.apply!([{ account: user.account, items: { '응원봉' => -1 } }, { account: ron, items: { '응원봉' => 1 } }], kind: 'transfer') }.to_not raise_error
    end

    it 'cannot be used on your own house, but can on another house' do
      post '/api/v1/system/items/use', params: { name: '응원봉', house_id: house.id.to_s }, headers: headers
      expect(response).to have_http_status(422)
      expect(GameHousePoint.count).to eq 0
      expect(GameCharacter.for(user.account).inventory.find { |item| item['name'] == '응원봉' }['count']).to eq 2

      post '/api/v1/system/items/use', params: { name: '응원봉', house_id: other_house.id.to_s }, headers: headers
      expect(response).to have_http_status(200)
      expect(GameHousePoint.sum(:amount)).to eq 10
    end

    it 'does not limit items without the option, even when they raise house points' do
      GameCharacter.for(ron).update!(house: house)
      expect { Game::Wallet.apply!([{ account: user.account, items: { '자유봉' => -1 } }, { account: ron, items: { '자유봉' => 1 } }], kind: 'transfer') }.to_not raise_error

      post '/api/v1/system/items/use', params: { name: '자유봉', house_id: house.id.to_s }, headers: headers
      expect(response).to have_http_status(200)
      expect(GameHousePoint.sum(:amount)).to eq 10
    end
  end
end
