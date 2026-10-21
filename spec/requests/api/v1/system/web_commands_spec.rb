# frozen_string_literal: true

require 'rails_helper'

# 웹 전용 컨텐츠: 시작한 뒤의 행동은 웹에서 툿 없이 보내고, 진행 메시지는 웹 메시지로 내려온다 (앱에는 아무것도 안 나간다)
RSpec.describe 'Web-only content commands' do
  let!(:system) { Fabricate(:account, username: 'system') }
  let(:harry) { Fabricate(:user, account: Fabricate(:account, username: 'harry')) }
  let(:ron) { Fabricate(:user, account: Fabricate(:account, username: 'ron')) }
  let(:outsider) { Fabricate(:user, account: Fabricate(:account, username: 'outsider')) }

  def headers_for(user)
    { 'Authorization' => "Bearer #{Fabricate(:accessible_access_token, resource_owner_id: user.id, scopes: 'read write').token}" }
  end

  before do
    allow(Game::System).to receive(:account).and_return(system)
    [harry, ron, outsider].each { |member| GameCharacter.for(member.account) }
    Game::Events::Opening.open!(Game::Web::Maze, harry.account, mode: 'pick', players: [harry.account, ron.account])
    [harry, ron].each do |member|
      status = PostStatusService.new.call(member.account, text: '@system [참가]', visibility: 'private')
      Game::Engine.new(status).call
    end
    Game::Lobby.start!(GameSession.where(kind: 'maze').last.reload) # 대기방에서 모두 준비해 시작
  end

  let(:session) { GameSession.where(kind: 'maze').last.reload }

  it 'takes an action without posting a toot and shows the web messages only to the players' do
    expect(session.status).to eq 'active'
    expect(session.web_channel?).to be true
    toots = Status.where(account_id: [harry.account_id, ron.account_id, system.id]).count

    post '/api/v1/system/commands', headers: headers_for(harry), params: { session_id: session.id, command: '대기' }

    expect(response).to have_http_status(200)
    expect(Status.where(account_id: [harry.account_id, ron.account_id, system.id]).count).to eq toots # 툿이 늘지 않는다
    expect(session.reload.state['moves'].keys).to include(session.player_for(harry.account).seat.to_s)

    get "/api/v1/system/sessions/#{session.id}", headers: headers_for(harry)
    messages = response.parsed_body['messages']
    expect(messages.pluck('id').grep(/\Am\d+\z/).size).to be >= 2
    expect(messages.count { |message| message['secret'] }).to eq 2 # 내게 온 비밀 안내(이동 안내·접수)

    get "/api/v1/system/sessions/#{session.id}", headers: headers_for(ron)
    expect(response.parsed_body['messages'].count { |message| message['secret'] }).to eq 1 # 남의 비밀 안내는 안 보인다
  end

  it 'ignores commands from someone who is not in the game' do
    post '/api/v1/system/commands', headers: headers_for(outsider), params: { session_id: session.id, command: '대기' }

    expect(response).to have_http_status(200)
    expect(session.reload.state['moves']).to eq({})
  end
end
