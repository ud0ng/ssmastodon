# frozen_string_literal: true

require 'rails_helper'

# 소속 점수 화면: 합계, 가장 많이 획득/깎은 사람, 전체·획득·차감 내역
RSpec.describe 'GET /api/v1/system/houses/:id' do
  let(:user) { Fabricate(:user, account: Fabricate(:account, username: 'harry')) }
  let(:headers) { { 'Authorization' => "Bearer #{Fabricate(:accessible_access_token, resource_owner_id: user.id, scopes: 'read').token}" } }
  let(:ron) { Fabricate(:account, username: 'ron') }
  let(:house) { GameHouse.create!(name: '그리핀도르', color: '#ae0001', category: 'house') }

  before do
    GameCharacter.for(user.account).update!(name: '해리')
    GameCharacter.for(ron).update!(name: '론')
    GameHousePoint.create!(house: house, account: user.account, amount: 10, reason: 'jellybean')
    GameHousePoint.create!(house: house, account: user.account, amount: 5, reason: 'maze')
    GameHousePoint.create!(house: house, account: ron, amount: 4, reason: 'jellybean')
    GameHousePoint.create!(house: house, account: ron, amount: -7, reason: '교내 신고: 해리')
    GameHousePoint.create!(house: house, account: user.account, amount: -2, reason: '운영진 조정')
  end

  it 'counts the toot summary over the running season only, and over everything while no season runs' do
    today = Game::ActivitySnapshot.today
    GameActivityDay.create!(day: today - 9, account_id: user.account.id, posts: 50, post_chars: 5_000)
    GameActivityDay.create!(day: today, account_id: user.account.id, posts: 2, post_chars: 40)
    house_character = GameCharacter.for(user.account)
    house_character.update!(house: house)

    get "/api/v1/system/houses/#{house.id}", headers: headers
    expect(response.parsed_body.dig('house', 'summary')).to include('posts' => 52, 'season' => nil)

    GameSeason.create!(name: '시즌2', status: 'running', starts_on: today - 3)
    get "/api/v1/system/houses/#{house.id}", headers: headers
    expect(response.parsed_body.dig('house', 'summary')).to include('posts' => 2, 'chars' => 40, 'season' => '시즌2')
  end

  it 'shows the season total, the top earner, the top loser and the history' do
    get "/api/v1/system/houses/#{house.id}", headers: headers

    expect(response).to have_http_status(200)
    body = response.parsed_body
    expect(body['house']).to include('name' => '그리핀도르', 'total' => 10)
    expect(body['top_gain']).to include('name' => '해리', 'points' => 15)
    expect(body['top_loss']).to include('name' => '론', 'points' => -7)
    expect(body['records'].size).to eq 5
    expect(body['records'].first).to include('amount' => -2, 'reason' => '운영진 조정')
    expect(body['records'].pluck('reason')).to include('젤리빈 룰렛')
  end

  it 'filters the history to gains or losses and pages it' do
    get "/api/v1/system/houses/#{house.id}", headers: headers, params: { filter: 'gain' }
    expect(response.parsed_body['records'].pluck('amount')).to eq [4, 5, 10]

    get "/api/v1/system/houses/#{house.id}", headers: headers, params: { filter: 'loss' }
    expect(response.parsed_body['records'].pluck('amount')).to eq [-2, -7]
  end

  it 'shows the final points with the season end until a new season starts, then only counts the new season' do
    GameSeason.create!(name: '1학기', starts_on: 10.days.ago.to_date, ends_on: 1.day.ago.to_date, status: 'finished', finished_at: 1.hour.from_now)

    get "/api/v1/system/houses/#{house.id}", headers: headers
    body = response.parsed_body
    expect(body['house']['total']).to eq 10
    expect(body['house']['season']).to include('name' => '1학기', 'rank' => 1)

    travel 2.hours
    GameSeason.create!(name: '2학기')

    get "/api/v1/system/houses/#{house.id}", headers: headers
    expect(response.parsed_body['house']['total']).to eq 0
    expect(response.parsed_body['house']['season']).to be_nil
    expect(response.parsed_body['top_gain']).to be_nil
  end

  it 'lists the house members with the counters that affect house points and filters the history by counter' do
    report = GameCounter.create!(name: '벌점', max_count: 5, affects_house: true, house_amount: -2)
    praise = GameCounter.create!(name: '상점', max_count: 5, opposite: report)
    report.reload
    GameCharacter.for(user.account).update!(house: house)
    GameCharacter.for(ron).update!(house: house)
    report.add!(GameCharacter.for(ron), 10)
    praise.add!(GameCharacter.for(ron), 5)
    GameHousePoint.create!(house: house, account: ron, counter: report, amount: -10, reason: '벌점 5회')

    get "/api/v1/system/houses/#{house.id}", headers: headers

    body = response.parsed_body
    expect(body['counters'].pluck('name')).to eq %w(벌점 상점)
    ron_member = body['members'].find { |member| member['acct'] == 'ron' }
    # 상성은 상쇄하고 이긴 쪽만, 0 이면 배지 없음. points: 다음 반영 때 바뀔 점수, next_at: 그때
    expect(ron_member['counters'].pluck('name')).to eq %w(벌점)
    expect(ron_member['counters'].first).to include('value' => 5, 'points' => -10)
    expect(ron_member['counters'].first['next_at']).to be_present
    harry_member = body['members'].find { |member| member['acct'] == 'harry' }
    expect(harry_member['counters']).to eq []
    expect(ron_member['account_id']).to eq ron.id.to_s

    get "/api/v1/system/houses/#{house.id}", headers: headers, params: { counter: report.id }
    # 수치 탭은 소속 점수 내역이 아니라 그 수치(벌점 내역)의 기록: 이 소속 캐릭터의 변동만
    records = response.parsed_body['records']
    expect(records.pluck('amount')).to eq [10]
    expect(records.first).to include('counter' => '벌점', 'result' => 10)
    expect(records.first['character']).to include('name' => '론')

    # 소속 점수에 반영된 것은 획득·차감 탭에
    get "/api/v1/system/houses/#{house.id}", headers: headers, params: { filter: 'loss' }
    expect(response.parsed_body['records'].pluck('amount')).to include(-10)
  end
  it 'records who raised a counter in the counter history' do
    report = GameCounter.create!(name: '벌점', max_count: 5, affects_house: true, house_amount: -2)
    GameCharacter.for(user.account).update!(house: house)
    GameCharacter.for(ron).update!(house: house)
    report.add!(GameCharacter.for(ron), 1, source: user.account)

    get "/api/v1/system/houses/#{house.id}", headers: headers, params: { counter: report.id }

    expect(response.parsed_body['records'].first['source']).to include('name' => '해리')
  end
end
