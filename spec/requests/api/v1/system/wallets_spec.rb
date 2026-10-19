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

  it 'shows the group points for the bottom of the compose panel' do
    GameHouse.ensure_defaults!
    house = GameHouse.houses.first
    GameCharacter.for(user.account).update!(house: house)
    GameHousePoint.create!(house: house, amount: 12, reason: 'test')

    get '/api/v1/system/wallet', headers: headers

    body = response.parsed_body
    expect(body).to include('house_term' => '기숙사', 'my_house_id' => house.id.to_s)
    expect(body['houses']).to include('id' => house.id.to_s, 'name' => house.name, 'color' => house.color, 'total' => 12, 'fx' => nil)
    expect(body['houses'].size).to eq GameHouse.houses.count
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
end
