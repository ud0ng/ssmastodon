# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Admin open event' do
  let!(:system) { Fabricate(:account, username: 'system') }

  before do
    allow(Game::System).to receive(:account).and_return(system)
    sign_in Fabricate(:admin_user)
  end

  it 'opens recruiting events, one per content' do
    post admin_game_event_path, params: { kind: 'maze' }

    expect(response).to redirect_to(admin_game_events_settings_path)
    expect(GameSession.where(kind: 'maze', status: 'pending').count).to eq 1

    post admin_game_event_path, params: { kind: 'maze' }
    expect(flash[:alert]).to include('이미 진행 중')
    expect(GameSession.where(kind: 'maze').count).to eq 1

    post admin_game_event_path, params: { kind: 'flying' }
    expect(GameSession.where(kind: 'flying', status: 'pending').count).to eq 1
  end

  it 'shows a badge to members who have not joined and a join button state on the content page' do
    member = Fabricate(:user, account: Fabricate(:account, username: 'harry'))
    GameCharacter.for(member.account)
    Game::Events::Opening.open!(Game::Web::Maze, member.account)
    token = Fabricate(:accessible_access_token, resource_owner_id: member.id, scopes: 'read write')

    stranger = Fabricate(:user, account: Fabricate(:account, username: 'ron'))
    stranger_token = Fabricate(:accessible_access_token, resource_owner_id: stranger.id, scopes: 'read write')
    headers = { 'Authorization' => "Bearer #{stranger_token.token}" }

    get '/api/v1/system/wallet', headers: headers
    expect(response.parsed_body['todo'].pluck('name')).to include('트라이위저드 미로')

    get '/api/v1/system/games/maze', headers: headers
    expect(response.parsed_body['recruiting']).to include('count' => 0)

    post '/api/v1/system/commands', headers: headers, params: { kind: 'maze', join: true }
    expect(response).to have_http_status(200)
    expect(token).to be_present
    expect(GameSession.where(kind: 'maze').last.players.map(&:account_id)).to eq [stranger.account.id]

    get '/api/v1/system/games/maze', headers: headers
    expect(response.parsed_body['recruiting']).to be_nil
  end
end
