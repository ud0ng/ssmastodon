# frozen_string_literal: true

require 'rails_helper'

# 웹 신청 창: 하루 횟수를 넘으면 신청하지 않고 안내 문구를 돌려준다 (모달에 표시)
RSpec.describe 'Daily limits on the web challenge' do
  let!(:system) { Fabricate(:account, username: 'system') }
  let(:harry) { Fabricate(:user, account: Fabricate(:account, username: 'harry')) }
  let!(:ron) { Fabricate(:user, account: Fabricate(:account, username: 'ron')) }
  let(:headers) { { 'Authorization' => "Bearer #{Fabricate(:accessible_access_token, resource_owner_id: harry.id, scopes: 'read write').token}" } }

  before do
    allow(Game::System).to receive(:account).and_return(system)
    Game::Config.merge!('common', 'daily_game_limit' => 1, 'one_game_per_person' => false)
    GameSession.create!(kind: 'jellybean', status: 'finished', visibility: 'private').players.create!(account: harry.account, seat: 0)
  end

  it 'returns the limit message instead of posting the invite' do
    expect { post '/api/v1/system/commands', headers: headers, params: { kind: 'gobstones', opponents: ['ron'] } }.not_to(change { Status.count })

    expect(response).to have_http_status(422)
    expect(response.parsed_body).to include('limit' => true)
    expect(response.parsed_body['error']).to include('하루 최대 1회')
  end

  it 'tells the content page to show the limit modal before choosing an opponent' do
    get '/api/v1/system/games/gobstones', headers: headers

    expect(response.parsed_body['daily_limit_message']).to include('하루 최대 1회')
  end
end
