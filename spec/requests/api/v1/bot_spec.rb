# frozen_string_literal: true

require 'rails_helper'

# 자동봇(ssbot) 전용 API: 캐릭터·재화·상점
RSpec.describe 'API V1 Bot' do
  let(:bot) { Fabricate(:user, account: Fabricate(:account, username: 'ssbot')) }
  let(:token) { Fabricate(:accessible_access_token, resource_owner_id: bot.id, scopes: 'read write') }
  let(:headers) { { 'Authorization' => "Bearer #{token.token}" } }
  let(:harry) { Fabricate(:user, account: Fabricate(:account, username: 'harry')).account }
  let(:ron) { Fabricate(:user, account: Fabricate(:account, username: 'ron')).account }

  before do
    Game::Config.merge!('common', 'bot_usernames' => 'ssbot, other')
    GameCharacterField.ensure_defaults!
    GameCharacter.for(harry).update!(name: '해리', money: 10, inventory: [{ 'name' => '초콜릿 개구리', 'count' => 2, 'note' => '' }], stats: { '힘' => '5' })
    GameCharacter.for(ron).update!(name: '론', money: 1)
  end

  it 'refuses accounts that are not set up as the bot' do
    stranger = Fabricate(:user)
    stranger_token = Fabricate(:accessible_access_token, resource_owner_id: stranger.id, scopes: 'read write')

    get '/api/v1/bot/characters', headers: { 'Authorization' => "Bearer #{stranger_token.token}" }

    expect(response).to have_http_status(403)
  end

  it 'lists characters with money, items, stats and computed statuses' do
    get '/api/v1/bot/characters', headers: headers

    expect(response).to have_http_status(200)
    harry_json = response.parsed_body.find { |character| character['acct'] == 'harry' }
    expect(harry_json).to include('name' => '해리', 'money' => 10)
    expect(harry_json['items']).to eq [{ 'name' => '초콜릿 개구리', 'count' => 2, 'note' => '' }]
    expect(harry_json['stats']).to include({ 'name' => '힘', 'value' => 5, 'type' => 'stat', 'min' => 0, 'max' => 100 },
                                           { 'name' => '체력', 'value' => 25, 'type' => 'status' })
  end

  it 'finds a character by account or character name' do
    get "/api/v1/bot/characters/#{ERB::Util.url_encode('론')}", headers: headers
    expect(response.parsed_body['acct']).to eq 'ron'

    get '/api/v1/bot/characters/@harry', headers: headers
    expect(response.parsed_body['name']).to eq '해리'

    get '/api/v1/bot/characters/nobody', headers: headers
    expect(response).to have_http_status(404)
  end

  it 'buys an item and records it' do
    post '/api/v1/bot/characters/apply', headers: headers, as: :json,
                                         params: { kind: 'purchase', detail: '사과 2개', changes: [{ acct: 'harry', money: -4, items: { '사과' => 2 } }] }

    expect(response).to have_http_status(200)
    expect(GameCharacter.for(harry).reload).to have_attributes(money: 6)
    expect(GameCharacter.for(harry).inventory.pluck('name', 'count')).to eq [['초콜릿 개구리', 2], ['사과', 2]]
    expect(GameReward.last).to have_attributes(account: harry, kind: 'purchase', money: -4, reason: '사과 2개', actor: 'ssbot')
  end

  it 'transfers between characters atomically and refuses when short' do
    post '/api/v1/bot/characters/apply', headers: headers, as: :json,
                                         params: { kind: 'transfer', changes: [{ acct: 'ron', money: -5 }, { acct: 'harry', money: 5 }] }

    expect(response).to have_http_status(422)
    expect(response.parsed_body).to include('code' => 'insufficient_money')
    expect([GameCharacter.for(harry).reload.money, GameCharacter.for(ron).reload.money]).to eq [10, 1]

    post '/api/v1/bot/characters/apply', headers: headers, as: :json,
                                         params: { kind: 'transfer', changes: [{ acct: 'harry', items: { '초콜릿개구리' => -2 } }, { acct: 'ron', items: { '초콜릿 개구리' => 2 } }] }

    expect(response).to have_http_status(200)
    expect(GameCharacter.for(harry).reload.inventory).to eq []
    expect(GameCharacter.for(ron).reload.inventory.pluck('name', 'count')).to eq [['초콜릿 개구리', 2]]
  end

  it 'gives attendance once a day' do
    2.times do
      post '/api/v1/bot/characters/apply', headers: headers, as: :json,
                                           params: { kind: 'attendance', once_per_day: true, changes: [{ acct: 'harry', money: 1 }] }
    end

    expect(response).to have_http_status(422)
    expect(response.parsed_body['code']).to eq 'already_done'
    expect(GameCharacter.for(harry).reload.money).to eq 11
  end

  it 'changes base stats within their range but not computed statuses' do
    post '/api/v1/bot/characters/apply', headers: headers, as: :json,
                                         params: { kind: 'use', changes: [{ acct: 'harry', stats: { '힘' => 500 } }] }
    expect(GameCharacter.for(harry).reload.stats['힘']).to eq '100'

    post '/api/v1/bot/characters/apply', headers: headers, as: :json,
                                         params: { kind: 'use', changes: [{ acct: 'harry', stats: { '체력' => 1 } }] }
    expect(response.parsed_body['code']).to eq 'unknown_stat'
  end

  it 'shows the shop and the currency settings' do
    shop = GameShop.create!(name: '허니듀크')
    shop.items.create!(name: '사과', price: 2, description: '아삭', stat_name: '힘', stat_value: '1d6')
    shop.items.create!(name: '아몬드', price: nil, usable: false)

    get '/api/v1/bot/shops', headers: headers
    expect(response.parsed_body.first['items']).to contain_exactly(
      a_hash_including('name' => '사과', 'price' => 2, 'stat' => '힘', 'value' => '1d6', 'usable' => true),
      a_hash_including('name' => '아몬드', 'price' => nil, 'usable' => false)
    )

    get '/api/v1/bot/config', headers: headers
    expect(response.parsed_body).to include('currency' => '갈레온', 'transfer_enabled' => true, 'attendance_reward' => 1)
    expect(response.parsed_body['help']).to include('[양도/n갈레온/캐릭터명] 재화를 캐릭터에게 양도합니다.')
  end

  it 'gives renamed shop and admin commands, admins and matching help lines' do
    Game::Config.merge!('currency', 'cmd_buy' => '사기', 'cmd_stat_change' => '조정', 'admin_usernames' => ['manager', '@luna'], 'transfer_enabled' => false)

    get '/api/v1/bot/config', headers: headers

    body = response.parsed_body
    expect(body['commands']).to include('buy' => '사기', 'bag' => '가방', 'stat_change' => '조정', 'money_add' => '소지금 추가')
    expect(body['admins']).to eq %w(manager luna)
    expect(body['help']).to include('[사기/아이템명] 원하는 아이템을 구매합니다.')
    expect(body['help'].join).to_not include('양도')
    expect(body['admin_help']).to include('[힘 조정/+3/캐릭터명] 스탯을 바꿉니다. (캐릭터 관리 > 스탯)')
  end

  it 'gives the shop bot help and leaves content help to the system bot' do
    get '/api/v1/bot/config', headers: headers

    body = response.parsed_body
    expect(body['help'].join).to_not include('도움말')
    expect(body).to_not have_key('content_help')
    expect(body).to include('help_command' => '도움말')
    expect(body['basic_help']).to include('[운세] 오늘의 운세를 확인합니다.', '컨텐츠 명령어는 @system에게 [도움말]을 보내 확인하세요.')
    expect(body['help_topics'].pluck('key')).to eq %w(shop admin)
    expect(body['help_topics'].last).to include('command' => '운영진 도움말', 'admin' => true)
  end

  it 'builds the content help from the contents that are on' do
    Game::Config.merge!('jellybean', 'command' => '젤리')
    Game::Config.merge!('gobstones', 'enabled' => false)

    text = Game::Help.system_text
    expect(text).to start_with("도움말

컨텐츠 명령어는 @system에게 멘션으로 보냅니다.
▸ 대결
[젤리] @상대 젤리빈 룰렛을 신청합니다.")
    expect(text).to include('[수락] 받은 신청을 받아들입니다.', "

▸ 점수·전적
[점수]")
    expect(text).to_not include('곱스톤')
  end

  it 'uses the help set in the content settings' do
    Game::Config.merge!('help', 'cmd_shop_help' => '가게 안내', 'rows_shop' => "가방|가방 보기
▸ 사고팔기|
구매/템|사기")

    get '/api/v1/bot/config', headers: headers

    body = response.parsed_body
    expect(body['help']).to eq ['[가방] 가방 보기', '', '▸ 사고팔기', '[구매/템] 사기']
    expect(body['help_topics'].first).to include('command' => '가게 안내')
  end
end
