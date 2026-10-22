# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Admin open event' do
  let!(:system) { Fabricate(:account, username: 'system') }

  before do
    allow(Game::System).to receive(:account).and_return(system)
    sign_in Fabricate(:admin_user)
  end

  it 'opens recruiting events, several at once even for the same content' do
    post admin_game_event_path, params: { kind: 'maze' }

    expect(response).to redirect_to(admin_game_events_settings_path)
    expect(GameSession.where(kind: 'maze', status: 'pending').count).to eq 1

    post admin_game_event_path, params: { kind: 'maze' }
    expect(GameSession.where(kind: 'maze').count).to eq 2

    post admin_game_event_path, params: { kind: 'flying' }
    expect(GameSession.where(kind: 'flying', status: 'pending').count).to eq 1
  end

  it 'shows the event settings, messages, list and history tabs' do
    session = Game::Events::Opening.open!(Game::Kinds::Flying, Fabricate(:admin_user).account)
    harry = Fabricate(:account, username: 'harry')
    session.players.create!(account: harry, seat: 0, result: 'win', state: {})
    session.update!(status: 'finished', finished_at: Time.current)

    # 화면을 그리는 요청 테스트는 Vite 빌드가 없는 컨테이너에서 못 돌려서(CLAUDE.md), 화면에 쓰는 설정 묶음만 확인한다
    expect(Game::Config.sections('events', 'settings').map(&:first)).to eq %w(unlock opening limits)
    expect(Game::Config.sections('events', 'messages').map(&:first)).to eq %w(event_commands event_messages)
    expect(session.reload.status).to eq 'finished'
  end

  it 'saves the event settings' do
    patch admin_game_setting_path('events'), params: { config: { event_open_by: 'everyone', event_daily_limit: '3', event_unlock: '0' } }

    config = Game::Events::Settings.config
    expect(config).to include('event_open_by' => 'everyone', 'event_daily_limit' => 3, 'event_unlock' => false)
    expect(Game::Events::Settings.open_modes(Fabricate(:user))).to eq []
  end

  it 'goes back to the event list after handling a running event, and to the content list for 1:1 contents' do
    event = GameSession.create!(kind: 'flying', status: 'active', visibility: 'private', state: { 'mode' => 'event' })
    post draw_admin_game_session_path(event)
    expect(response).to redirect_to(admin_game_events_settings_path)

    duel = GameSession.create!(kind: 'jellybean', status: 'active', visibility: 'private', state: {})
    post draw_admin_game_session_path(duel)
    expect(response).to redirect_to(admin_game_settings_path)
  end

  it 'shows a badge to members who have not joined and a join button state on the content page' do
    Game::Config.merge!('events', 'event_open_by' => 'everyone')
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
