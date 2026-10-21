# frozen_string_literal: true

require 'rails_helper'

# 운영진 [시작하기]: 모집을 끝내고 바로 시작 (최소 인원이 되어야 한다), 일반 회원은 못 한다
RSpec.describe 'POST /api/v1/system/sessions/:id/start_now' do
  let(:admin) { Fabricate(:user, role: UserRole.find_by(name: 'Owner')) }
  let(:member) { Fabricate(:user) }
  let(:admin_headers) { { 'Authorization' => "Bearer #{Fabricate(:accessible_access_token, resource_owner_id: admin.id, scopes: 'read write').token}" } }
  let(:member_headers) { { 'Authorization' => "Bearer #{Fabricate(:accessible_access_token, resource_owner_id: member.id, scopes: 'read write').token}" } }
  let(:session) { GameSession.create!(kind: 'flying', status: 'pending', visibility: 'private', deadline_at: 20.minutes.from_now, state: { 'mode' => 'event', 'phase' => 'recruit' }) }

  before { Fabricate(:account, username: 'system') }

  it 'refuses members and too few players, then starts right away for the staff' do
    post "/api/v1/system/sessions/#{session.id}/start_now", headers: member_headers
    expect(response).to have_http_status(403)

    post "/api/v1/system/sessions/#{session.id}/start_now", headers: admin_headers
    expect(response).to have_http_status(422)
    expect(session.reload.status).to eq 'pending'

    3.times { |index| session.players.create!(account: Fabricate(:account), seat: index, state: { 'accepted' => true }) }
    post "/api/v1/system/sessions/#{session.id}/start_now", headers: admin_headers

    expect(response).to have_http_status(200)
    expect(session.reload.status).to eq 'active'
  end

  it 'allows up to 20 players for the flying event and counts down 5 seconds' do
    expect(Game::Kinds.registry['flying'].config['event_max_players'].to_i).to eq 20
    expect(Game::Lobby::COUNTDOWN_SECONDS).to eq 5
  end
end
