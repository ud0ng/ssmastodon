# frozen_string_literal: true

require 'rails_helper'

# 여럿이 하는 컨텐츠 대기방: 모집이 끝나면 대기방 → 준비 → 모두 준비하면 카운트다운 → 시작 (진행은 웹에만)
RSpec.describe 'Waiting room' do
  let!(:system) { Fabricate(:account, username: 'system') }
  let(:harry) { Fabricate(:user, account: Fabricate(:account, username: 'harry')) }
  let(:ron) { Fabricate(:user, account: Fabricate(:account, username: 'ron')) }
  let(:outsider) { Fabricate(:user, account: Fabricate(:account, username: 'outsider')) }
  let(:admin) { Fabricate(:user, role: UserRole.find_by(name: 'Owner')) }

  def headers_for(user)
    { 'Authorization' => "Bearer #{Fabricate(:accessible_access_token, resource_owner_id: user.id, scopes: 'read write').token}" }
  end

  before do
    allow(Game::System).to receive(:account).and_return(system)
    [harry, ron, outsider, admin].each { |member| GameCharacter.for(member.account) }
    Game::Events::Opening.open!(Game::Web::Maze, admin.account, mode: 'pick', players: [harry.account, ron.account])
    [harry, ron].each do |member|
      status = PostStatusService.new.call(member.account, text: '@system [참가]', visibility: 'private')
      Game::Engine.new(status).call
    end
  end

  let(:session) { GameSession.where(kind: 'maze').last.reload }

  it 'opens a waiting room when everyone has accepted instead of starting right away' do
    expect(session.status).to eq 'lobby'
    expect(session.web_channel?).to be true
    expect(session.state['moves']).to be_nil # 아직 시작하지 않았다
    expect(session.messages.pick(:text)).to include('대기방')

    get "/api/v1/system/sessions/#{session.id}", headers: headers_for(harry)

    lobby = response.parsed_body['lobby']
    expect(lobby['players'].pluck('acct')).to eq %w(harry ron)
    expect(lobby).to include('me' => harry.account_id.to_s, 'can_manage' => false, 'start_at' => nil)
    expect(lobby['players'].pluck('ready')).to eq [false, false]
  end

  it 'counts down when everyone is ready and starts the game, and a cancel makes everyone ready again' do
    post "/api/v1/system/sessions/#{session.id}/ready", headers: headers_for(harry), params: { ready: true }
    expect(response.parsed_body['lobby']['players'].pluck('ready')).to eq [true, false]
    expect(response.parsed_body['lobby']['start_at']).to be_nil

    post "/api/v1/system/sessions/#{session.id}/ready", headers: headers_for(ron), params: { ready: true }
    start_at = session.reload.state.dig('lobby', 'start_at')
    expect(start_at).to be_present
    expect(response.parsed_body['lobby']['start_at']).to be_present
    expect(Game::LobbyStartWorker.jobs.size).to be >= 1

    post "/api/v1/system/sessions/#{session.id}/cancel_start", headers: headers_for(ron)
    expect(session.reload.state['lobby']).to include('ready' => [], 'start_at' => nil)
    expect(session.status).to eq 'lobby'
    Game::LobbyStartWorker.new.perform(session.id, start_at) # 묵은 카운트다운은 아무것도 하지 않는다
    expect(session.reload.status).to eq 'lobby'

    [harry, ron].each { |member| post "/api/v1/system/sessions/#{session.id}/ready", headers: headers_for(member), params: { ready: true } }
    start_at = session.reload.state.dig('lobby', 'start_at')
    before = Status.where(account: system).count
    Game::LobbyStartWorker.new.perform(session.id, start_at)

    expect(session.reload.status).to eq 'active'
    expect(session.state).to_not have_key('lobby')
    expect(session.state['moves']).to eq({})
    expect(Status.where(account: system).count).to eq before # 시작한 뒤의 진행은 웹 메시지
  end

  it 'stops the countdown when somebody takes the ready back' do
    [harry, ron].each { |member| post "/api/v1/system/sessions/#{session.id}/ready", headers: headers_for(member), params: { ready: true } }
    expect(session.reload.state.dig('lobby', 'start_at')).to be_present

    post "/api/v1/system/sessions/#{session.id}/ready", headers: headers_for(ron), params: { ready: false }

    expect(session.reload.state.dig('lobby', 'start_at')).to be_nil
    expect(session.state.dig('lobby', 'ready')).to eq [harry.account_id]
  end

  it 'lets only staff change the ready of other characters' do
    post "/api/v1/system/sessions/#{session.id}/ready", headers: headers_for(harry), params: { ready: true, acct: 'ron' }
    expect(response).to have_http_status(403)

    post "/api/v1/system/sessions/#{session.id}/ready", headers: headers_for(admin), params: { ready: true, acct: 'ron' }
    expect(response).to have_http_status(200)
    expect(session.reload.state.dig('lobby', 'ready')).to eq [ron.account_id]
    expect(response.parsed_body['lobby']['can_manage']).to be true
  end

  it 'shows chat bubbles in the room to everyone in it and keeps outsiders out' do
    post "/api/v1/system/sessions/#{session.id}/chat", headers: headers_for(harry), params: { text: '준비됐어!' }
    expect(response).to have_http_status(200)

    chat = response.parsed_body['messages'].find { |message| message['chat'] }
    expect(chat).to include('text' => '준비됐어!', 'mine' => true)

    get "/api/v1/system/sessions/#{session.id}", headers: headers_for(ron)
    expect(response.parsed_body['messages'].find { |message| message['chat'] }).to include('text' => '준비됐어!', 'mine' => false)

    post "/api/v1/system/sessions/#{session.id}/chat", headers: headers_for(outsider), params: { text: '나도' }
    expect(response).to have_http_status(403)
    expect(session.messages.where(kind: 'chat').count).to eq 1
  end

  it 'lets staff start the waiting room right away from the admin control' do
    Game::SessionControl.advance!(session)

    expect(session.reload.status).to eq 'active'
  end
end
