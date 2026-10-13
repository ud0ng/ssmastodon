# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'API V1 System' do
  let(:user) { Fabricate(:user) }
  let(:token) { Fabricate(:accessible_access_token, resource_owner_id: user.id, scopes: 'read') }
  let(:headers) { { 'Authorization' => "Bearer #{token.token}" } }
  let(:rival) { Fabricate(:account) }

  before do
    Fabricate(:account, username: 'system')
    house = GameHouse.create!(name: '그리핀도르', emoji: '🦁')
    GameCharacter.for(user.account).update!(name: '해리', house: house)
    GameHousePoint.create!(house: house, amount: 15)

    GameSession.create!(kind: 'jellybean', status: 'finished', finished_at: Time.now.utc).tap do |session|
      session.players.create!(account: user.account, seat: 0, result: 'win')
      session.players.create!(account: rival, seat: 1, result: 'lose')
    end
    GameSession.create!(kind: 'jellybean', status: 'active', turn: 2).tap do |session|
      session.players.create!(account: user.account, seat: 0)
      session.players.create!(account: rival, seat: 1)
    end
  end

  it 'returns houses, my character and record, and my games' do
    get '/api/v1/system', headers: headers

    expect(response).to have_http_status(200)
    expect(response.parsed_body).to include(
      'system_acct' => 'system',
      'house_term' => '기숙사',
      'houses' => [include('name' => '그리핀도르', 'total' => 15)],
      'character' => include('name' => '해리'),
      'record' => { 'win' => 1, 'lose' => 0, 'draw' => 0 },
      'active' => [include('kind' => 'jellybean', 'status' => 'active', 'turn' => 2)],
      'recent' => [include('result' => 'win')],
      'games' => include(include('key' => 'jellybean', 'command' => '젤리빈'), include('key' => 'duel', 'command' => '결투'))
    )
  end

  it 'requires a signed-in user' do
    get '/api/v1/system'
    expect(response).to have_http_status(401)
  end
end
