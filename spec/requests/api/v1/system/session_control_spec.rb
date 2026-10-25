# frozen_string_literal: true

require 'rails_helper'

# 운영진이 이벤트 목록에서 오른쪽 클릭으로 진행 중인 판을 다룬다 (단계 넘기기 · 무승부 종료 · 취소)
RSpec.describe 'POST /api/v1/system/sessions/:id/control' do
  let!(:system) { Fabricate(:account, username: 'system') }
  let(:staff) { Fabricate(:user, role: Fabricate(:user_role, name: 'Boss', permissions: UserRole::FLAGS[:administrator])) }
  let(:member) { Fabricate(:user, account: Fabricate(:account, username: 'harry')) }
  let(:other) { Fabricate(:user, account: Fabricate(:account, username: 'ron')) }
  let!(:session) do
    GameSession.create!(kind: 'maze', status: 'active', visibility: 'private', state: { 'mode' => 'event' }).tap do |created|
      created.players.create!(account: member.account, seat: 0)
      created.players.create!(account: other.account, seat: 1)
    end
  end

  def headers(user)
    { 'Authorization' => "Bearer #{Fabricate(:accessible_access_token, resource_owner_id: user.id, scopes: 'read write').token}" }
  end

  before { allow(Game::System).to receive(:account).and_return(system) }

  it 'lets staff end a running game as a draw' do
    post "/api/v1/system/sessions/#{session.id}/control", params: { op: 'draw' }, headers: headers(staff)

    expect(response).to have_http_status(200)
    expect(session.reload.status).to eq 'finished'
    expect(session.players.pluck(:result).uniq).to eq ['draw']
  end

  it 'lets staff cancel a running game' do
    post "/api/v1/system/sessions/#{session.id}/control", params: { op: 'cancel' }, headers: headers(staff)

    expect(response).to have_http_status(200)
    expect(session.reload.status).to eq 'cancelled'
  end

  it 'refuses non-staff, unknown actions and finished games' do
    post "/api/v1/system/sessions/#{session.id}/control", params: { op: 'cancel' }, headers: headers(member)
    expect(response).to have_http_status(403)

    post "/api/v1/system/sessions/#{session.id}/control", params: { op: 'explode' }, headers: headers(staff)
    expect(response).to have_http_status(422)

    session.update!(status: 'finished')
    post "/api/v1/system/sessions/#{session.id}/control", params: { op: 'draw' }, headers: headers(staff)
    expect(response).to have_http_status(422)
    expect(session.reload.status).to eq 'finished'
  end
end
