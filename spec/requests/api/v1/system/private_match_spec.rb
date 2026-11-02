# frozen_string_literal: true

require 'rails_helper'

# 운영진의 비공개 대결: 컨텐츠 [시작하기]에서 두 사람을 골라 초대 → 둘의 DM 으로만, 점수·전적 없이
RSpec.describe 'POST /api/v1/system/commands (private match)' do
  let!(:system) { Fabricate(:account, username: 'system') }
  let(:staff) { Fabricate(:user, role: Fabricate(:user_role, name: 'Boss', permissions: UserRole::FLAGS[:administrator])) }
  let(:harry) { Fabricate(:user, account: Fabricate(:account, username: 'harry')) }
  let(:ron) { Fabricate(:user, account: Fabricate(:account, username: 'ron')) }
  let(:neville) { Fabricate(:user, account: Fabricate(:account, username: 'neville')) }

  def headers(user)
    { 'Authorization' => "Bearer #{Fabricate(:accessible_access_token, resource_owner_id: user.id, scopes: 'read write').token}" }
  end

  def reply(account, text)
    status = PostStatusService.new.call(account, text: "@system #{text}", visibility: 'direct')
    Game::Engine.new(status).call
  end

  before do
    allow(Game::System).to receive(:account).and_return(system)
    GameCharacter.for(harry.account).update!(name: '해리', house: GameHouse.create!(name: '그리핀도르', emoji: '🦁'))
    GameCharacter.for(ron.account).update!(name: '론', house: GameHouse.find_by(name: '그리핀도르'))
  end

  it 'lets staff invite two people to a DM-only match that counts for nothing' do
    post '/api/v1/system/commands', params: { kind: 'gobstones', private_match: true, players: %w(harry ron) }, headers: headers(staff)

    expect(response).to have_http_status(200)
    session = GameSession.find(response.parsed_body['session_id'])
    expect(session.visibility).to eq 'direct'
    expect(session.test?).to be true
    expect(session.players.map(&:account)).to eq [harry.account, ron.account] # 연 운영진은 참가하지 않는다
    expect(Status.find(session.root_status_id)).to have_attributes(visibility: 'direct', text: include('비공개 대결'))

    reply(harry.account, '[수락]')
    reply(ron.account, '[수락]')
    expect(session.reload.status).to eq 'active'

    session.kind_class.new(session).send(:finish!, winner: session.player_for(harry.account))
    expect(GameHousePoint.where(game_session_id: session.id)).to be_empty
    expect(Status.find(session.reload.last_status_id).text).to include('비공개 대결이라 점수와 보상은 없습니다')
    expect(GameSession.real.where(id: session.id)).to be_empty # 전적·순위·하루 횟수에서 빠진다

    # 운영진과 두 사람에게만 보인다
    get "/api/v1/system/sessions/#{session.id}", headers: headers(neville)
    expect(response).to have_http_status(404)
    get "/api/v1/system/sessions/#{session.id}", headers: headers(staff)
    expect(response).to have_http_status(200)
    get "/api/v1/system/sessions/#{session.id}", headers: headers(ron)
    expect(response).to have_http_status(200)
  end

  it 'refuses non-staff, the same person twice and people already in a game' do
    post '/api/v1/system/commands', params: { kind: 'gobstones', private_match: true, players: %w(harry ron) }, headers: headers(neville)
    expect(response).to have_http_status(403)

    post '/api/v1/system/commands', params: { kind: 'gobstones', private_match: true, players: %w(harry harry) }, headers: headers(staff)
    expect(response).to have_http_status(422)

    Game::Config.update!('common', 'one_game_per_person' => '1')
    post '/api/v1/system/commands', params: { kind: 'gobstones', private_match: true, players: %w(harry ron) }, headers: headers(staff)
    post '/api/v1/system/commands', params: { kind: 'jellybean', private_match: true, players: %w(harry neville) }, headers: headers(staff)
    expect(response).to have_http_status(422)
    expect(response.parsed_body['error']).to include('해리')
  end
end
