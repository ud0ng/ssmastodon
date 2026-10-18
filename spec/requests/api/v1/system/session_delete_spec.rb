# frozen_string_literal: true

require 'rails_helper'

# 운영진이 끝난 판 기록을 지운다 (판 + 스레드의 멘션·DM 툿)
RSpec.describe 'DELETE /api/v1/system/sessions/:id' do
  let!(:system) { Fabricate(:account, username: 'system') }
  let(:staff) { Fabricate(:user, role: Fabricate(:user_role, name: 'Boss', permissions: UserRole::FLAGS[:administrator])) }
  let(:member) { Fabricate(:user, account: Fabricate(:account, username: 'harry')) }
  let(:other) { Fabricate(:user, account: Fabricate(:account, username: 'ron')) }

  def headers(user)
    { 'Authorization' => "Bearer #{Fabricate(:accessible_access_token, resource_owner_id: user.id, scopes: 'read write').token}" }
  end

  let!(:thread_status) { PostStatusService.new.call(member.account, text: "@system @#{other.account.username} [미로]", visibility: 'private') }
  let!(:reply) { PostStatusService.new.call(system, text: "@#{member.account.username} 시작!", thread: thread_status, visibility: 'private') }
  let!(:unrelated) { PostStatusService.new.call(other.account, text: '상관없는 글', visibility: 'unlisted') }
  let!(:session) do
    GameSession.create!(kind: 'maze', status: 'finished', visibility: 'private', root_status_id: thread_status.id, last_status_id: reply.id, finished_at: Time.now.utc).tap do |created|
      created.players.create!(account: member.account, seat: 0, result: 'win')
      created.players.create!(account: other.account, seat: 1, result: 'lose')
    end
  end

  before { allow(Game::System).to receive(:account).and_return(system) }

  it 'lets staff delete a finished game with its mentions, keeping rewards and unrelated posts' do
    GameCharacter.for(member.account)
    Game::Wallet.apply!([{ account: member.account, money: 5 }], kind: 'content', detail: 'game:maze')
    GameReward.where(account: member.account).update_all(game_session_id: session.id)

    delete "/api/v1/system/sessions/#{session.id}", headers: headers(staff)
    Game::StatusCleanupWorker.drain

    expect(response).to have_http_status(200)
    expect(GameSession.exists?(session.id)).to be false
    expect(Status.unscoped.where(id: [thread_status.id, reply.id])).to be_empty
    expect(Status.unscoped.exists?(unrelated.id)).to be true
    expect(GameReward.where(account: member.account).count).to eq 1
  end

  it 'refuses non-staff and games still in progress' do
    delete "/api/v1/system/sessions/#{session.id}", headers: headers(member)
    expect(response).to have_http_status(403)
    expect(GameSession.exists?(session.id)).to be true

    session.update!(status: 'active')
    delete "/api/v1/system/sessions/#{session.id}", headers: headers(staff)
    expect(response).to have_http_status(422)
    expect(GameSession.exists?(session.id)).to be true
  end
end
