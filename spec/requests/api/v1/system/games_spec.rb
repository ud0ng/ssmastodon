# frozen_string_literal: true

require 'rails_helper'

# 웹 게임 화면: 컨텐츠별 정보, 상대 목록, 버튼(서버원 대신 시스템에게 툿)
RSpec.describe 'API V1 System games' do
  let(:user) { Fabricate(:user) }
  let(:token) { Fabricate(:accessible_access_token, resource_owner_id: user.id, scopes: 'read write') }
  let(:headers) { { 'Authorization' => "Bearer #{token.token}" } }
  let(:rival) { Fabricate(:user).account }
  let!(:system) { Fabricate(:account, username: 'system') }

  def finished_game(winner, loser, visibility: 'private')
    GameSession.create!(kind: 'jellybean', status: 'finished', finished_at: Time.now.utc, visibility: visibility).tap do |session|
      session.players.create!(account: winner, seat: 0, result: 'win')
      session.players.create!(account: loser, seat: 1, result: 'lose')
    end
  end

  it 'shows how to play, my record, my game, other games and the ranking' do
    finished_game(user.account, rival)
    hidden = finished_game(rival, Fabricate(:account), visibility: 'direct')
    current = GameSession.create!(kind: 'jellybean', status: 'active', turn: 2).tap do |session|
      session.players.create!(account: user.account, seat: 0)
      session.players.create!(account: rival, seat: 1)
    end

    get '/api/v1/system/games/jellybean', headers: headers

    expect(response).to have_http_status(200)
    body = response.parsed_body
    expect(body).to include('name' => '젤리빈 룰렛', 'group' => 'duel', 'command' => '젤리빈', 'my_session_id' => current.id.to_s)
    expect(body['steps'].first).to include('[젤리빈] @상대')
    expect(body['record']).to eq('win' => 1, 'lose' => 0, 'draw' => 0)
    expect(body['recent'].pluck('id')).to_not include(hidden.id.to_s)
    expect(body['ranking'].first).to include('wins' => 1, 'me' => true)
  end

  it 'lists the content catalog by group on the overview' do
    get '/api/v1/system', headers: headers

    groups = response.parsed_body['catalog'].to_h { |group| [group['key'], group['games'].pluck('key')] }
    expect(groups['duel']).to include('jellybean', 'duel')
    expect(groups['group']).to include('flying', 'maze', 'marauders_map')
    expect(groups['group']).to_not include('quidditch')
    expect(groups['group']).to include('secret_chamber')
    expect(groups.keys).to eq %w(duel group)
  end

  it 'returns 404 for an unknown game' do
    get '/api/v1/system/games/chess', headers: headers

    expect(response).to have_http_status(404)
  end

  it 'lists members to challenge' do
    rival
    get '/api/v1/system/members', headers: headers

    expect(response.parsed_body.pluck('acct')).to include(rival.acct)
    expect(response.parsed_body.pluck('acct')).to_not include(user.account.acct, 'system')
  end

  it 'posts an invite toot on behalf of the member' do
    post '/api/v1/system/commands', headers: headers, params: { kind: 'jellybean', opponents: [rival.acct] }

    expect(response).to have_http_status(200)
    status = Status.find(response.parsed_body['status_id'])
    expect(status.account).to eq user.account
    expect(status.text).to eq "@system @#{rival.acct} [젤리빈]"
    expect(status.visibility).to eq 'private'
  end

  it 'answers in the game thread, tagging the other players, or by DM for secret moves' do
    session = GameSession.create!(kind: 'duel', status: 'active', turn: 1, visibility: 'private').tap do |created|
      created.players.create!(account: user.account, seat: 0)
      created.players.create!(account: rival, seat: 1)
    end
    last = PostStatusService.new.call(system, text: 'turn 1', visibility: 'private')
    session.update!(last_status_id: last.id)

    post '/api/v1/system/commands', headers: headers, params: { session_id: session.id, command: '항복' }
    reply = Status.find(response.parsed_body['status_id'])
    expect(reply.text).to eq "@system @#{rival.acct} [항복]"
    expect(reply.in_reply_to_id).to eq last.id

    post '/api/v1/system/commands', headers: headers, params: { session_id: session.id, command: '공격', args: '필살', dm: true }
    secret = Status.find(response.parsed_body['status_id'])
    expect(secret.text).to eq '@system [공격/필살]'
    expect(secret.visibility).to eq 'direct'
  end

  it 'lists my finished games with what each one gave me' do
    game = finished_game(user.account, rival)
    house = GameHouse.create!(name: '그리핀도르')
    GameHousePoint.create!(house: house, account: user.account, session: game, amount: 5, reason: 'jellybean')
    GameReward.create!(account: user.account, session: game, money: 10, items: [{ 'name' => '깃펜', 'count' => 1 }], reason: 'game:jellybean')
    finished_game(rival, user.account)

    get '/api/v1/system/history', headers: headers

    games = response.parsed_body['games']
    expect(games.size).to eq 2
    expect(games.last).to include('session_id' => game.id.to_s, 'name' => '젤리빈 룰렛', 'result' => 'win', 'points' => 5, 'money' => 10,
                                  'items' => [{ 'name' => '깃펜', 'count' => 1 }])
    expect(games.first).to include('result' => 'lose')
    expect(response.parsed_body['next_max_id']).to be_nil

    get '/api/v1/system/history', headers: headers, params: { filter: 'win' }
    expect(response.parsed_body['games'].pluck('result')).to eq %w(win)
  end

  it 'uses the description set in the content settings' do
    Game::Config.merge!('jellybean', 'description' => '젤리빈 한 봉지로 겨루기')

    get '/api/v1/system/games/jellybean', headers: headers

    expect(response.parsed_body['summary']).to eq '젤리빈 한 봉지로 겨루기'
  end
  describe 'group contents are opened by staff' do
    let(:admin) { Fabricate(:user, role: UserRole.find_by(name: 'Owner')) }
    let(:admin_headers) { { 'Authorization' => "Bearer #{Fabricate(:accessible_access_token, resource_owner_id: admin.id, scopes: 'read write').token}" } }

    it 'marks the group contents as recruiting events and lets only staff open an event' do
      get '/api/v1/system/games/flying', headers: headers
      expect(response.parsed_body).to include('event' => true, 'can_open' => false, 'web_open' => true)

      get '/api/v1/system/games/jellybean', headers: headers
      expect(response.parsed_body).to include('event' => false)

      get '/api/v1/system/games/flying', headers: admin_headers
      expect(response.parsed_body).to include('can_open' => true)

      post '/api/v1/system/games/flying/open', headers: headers
      expect(response).to have_http_status(403)
    end

    it 'lets staff test play with picked players: staff see it with a lock, players once they accepted, nobody else' do
      Game::Config.merge!('flying', 'event_min_players' => '2')
      harry = Fabricate(:user, account: Fabricate(:account, username: 'harry'))
      ron = Fabricate(:user, account: Fabricate(:account, username: 'ron'))
      [harry, ron, user].each { |member| GameCharacter.for(member.account) }
      harry_headers = { 'Authorization' => "Bearer #{Fabricate(:accessible_access_token, resource_owner_id: harry.id, scopes: 'read write').token}" }

      post '/api/v1/system/games/flying/open', headers: headers, params: { mode: 'test', accts: %w(harry ron) }
      expect(response).to have_http_status(403)

      post '/api/v1/system/games/flying/open', headers: admin_headers, params: { mode: 'test', accts: %w(harry nobody) }
      expect(response).to have_http_status(422)

      post '/api/v1/system/games/flying/open', headers: admin_headers, params: { mode: 'test', accts: %w(harry ron) }
      expect(response).to have_http_status(200)

      get '/api/v1/system/games/flying', headers: admin_headers
      expect(response.parsed_body['active'].pluck('test')).to eq [true]

      # 초대한 사람에게만 그 방이 보인다 (바로 대기방). 고르지 않은 사람에게는 모집 알림도, 목록에도 안 뜬다
      get '/api/v1/system/games/flying', headers: harry_headers
      expect(response.parsed_body['active'].size).to eq 1
      get '/api/v1/system/games/flying', headers: headers
      expect(response.parsed_body['recruiting']).to be_nil
      expect(response.parsed_body['active']).to eq []

      [harry, ron].each do |member|
        status = PostStatusService.new.call(member.account, text: '@system [참가]', visibility: 'direct')
        Game::Engine.new(status).call
      end
      get '/api/v1/system/games/flying', headers: harry_headers
      expect(response.parsed_body['active'].size).to eq 1

      get '/api/v1/system/games/flying', headers: headers
      expect(response.parsed_body['active']).to eq []
      session = GameSession.where(kind: 'flying').last
      get "/api/v1/system/sessions/#{session.id}", headers: headers
      expect(response).to have_http_status(404)
      get "/api/v1/system/sessions/#{session.id}", headers: admin_headers
      expect(response).to have_http_status(200)
    end
  end
  it 'shows an invited waiting room only to the invited, with a waiting mark, and sends no end DM for it' do
    harry = Fabricate(:user, account: Fabricate(:account, username: 'harry'))
    ron = Fabricate(:user, account: Fabricate(:account, username: 'ron'))
    [harry, ron].each { |member| GameCharacter.for(member.account) }
    harry_headers = { 'Authorization' => "Bearer #{Fabricate(:accessible_access_token, resource_owner_id: harry.id, scopes: 'read write').token}" }
    ron_headers = { 'Authorization' => "Bearer #{Fabricate(:accessible_access_token, resource_owner_id: ron.id, scopes: 'read write').token}" }
    session = GameSession.create!(kind: 'flying', status: 'lobby', visibility: 'private', state: { 'mode' => 'event', 'invited' => [harry.account.id], 'lobby' => { 'ready' => [], 'start_at' => nil } })

    get '/api/v1/system', headers: harry_headers
    flying = response.parsed_body['catalog'].flat_map { |group| group['games'] }.find { |game| game['key'] == 'flying' }
    expect(flying).to include('invited' => 1, 'recruiting' => 0)
    get '/api/v1/system/games/flying', headers: harry_headers
    expect(response.parsed_body['recruiting']).to be_present
    expect(response.parsed_body['active'].pluck('waiting')).to eq [true]

    get '/api/v1/system', headers: ron_headers
    flying = response.parsed_body['catalog'].flat_map { |group| group['games'] }.find { |game| game['key'] == 'flying' }
    expect(flying).to include('invited' => 0, 'recruiting' => 0)

    before = Status.maximum(:id).to_i
    session.update!(status: 'active')
    session.update!(status: 'finished', finished_at: Time.now.utc)
    expect(Status.where('id > ?', before).where('text LIKE ?', '%끝났어요%')).to be_empty
  end
end
