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

  it 'only counts points since the last finished season' do
    GameSeason.create!(name: '1학기', starts_on: 10.days.ago.to_date, ends_on: 1.day.ago.to_date, status: 'finished', finished_at: 1.hour.from_now)

    get "/api/v1/system/houses/#{house.id}", headers: headers

    expect(response.parsed_body['house']['total']).to eq 0
    expect(response.parsed_body['top_gain']).to be_nil
  end
end
