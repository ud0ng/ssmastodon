# frozen_string_literal: true

require 'rails_helper'

# 글쓰기창 아래 재화 | 인벤토리 | 전적과 재화·인벤토리 화면
RSpec.describe 'API V1 System wallet' do
  let(:user) { Fabricate(:user) }
  let(:token) { Fabricate(:accessible_access_token, resource_owner_id: user.id, scopes: 'read') }
  let(:headers) { { 'Authorization' => "Bearer #{token.token}" } }

  before do
    GameCharacterField.ensure_defaults!
    GameShop.create!(name: '허니듀크').items.create!(name: '초콜릿 개구리', price: 2, description: '폴짝')
    Game::Wallet.apply!([{ account: user.account, money: 30, items: { '초콜릿 개구리' => 3, '투명 망토' => 1 } }], kind: 'admin', detail: '생일')
    Game::Wallet.apply!([{ account: user.account, money: -2 }], kind: 'purchase', detail: '사과 1개')
  end

  it 'shows my currency, history, inventory and record' do
    get '/api/v1/system/wallet', headers: headers

    expect(response).to have_http_status(200)
    body = response.parsed_body
    expect(body).to include('currency' => '갈레온', 'money' => 28, 'item_count' => 4, 'record' => { 'win' => 0, 'lose' => 0, 'draw' => 0 })
    expect(body['records'].pluck('kind', 'money', 'reason')).to eq [['purchase', -2, '사과 1개'], ['admin', 30, '생일']]
    expect(body['inventory']).to include(a_hash_including('name' => '초콜릿 개구리', 'count' => 3, 'description' => '폴짝'),
                                         a_hash_including('name' => '투명 망토', 'count' => 1, 'image' => nil))
  end

  it 'needs a signed-in user' do
    get '/api/v1/system/wallet'

    expect(response).to have_http_status(401)
  end
end
