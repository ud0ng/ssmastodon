# frozen_string_literal: true

require 'rails_helper'

# 남의 대화 안에서 신청한 판: 게임방 화면과 기록 지우기는 신청 툿과 그 아래로 이어진 답만 다룬다 (같은 대화의 다른 답은 상관없다)
RSpec.describe 'A game started inside someone else\'s conversation' do
  let!(:system) { Fabricate(:account, username: 'system') }
  let(:staff) { Fabricate(:user, role: Fabricate(:user_role, name: 'Boss', permissions: UserRole::FLAGS[:administrator])) }
  let(:robin) { Fabricate(:user, account: Fabricate(:account, username: 'robin')) }
  let(:becky) { Fabricate(:user, account: Fabricate(:account, username: 'becky')) }
  let(:daniel) { Fabricate(:user, account: Fabricate(:account, username: 'daniel')) }

  def headers(user)
    { 'Authorization' => "Bearer #{Fabricate(:accessible_access_token, resource_owner_id: user.id, scopes: 'read write').token}" }
  end

  let!(:opener) { PostStatusService.new.call(robin.account, text: '진실 게임 하자', visibility: 'private') }
  let!(:command) { PostStatusService.new.call(becky.account, text: "@#{robin.account.username} @system [젤리빈] 하자", thread: opener, visibility: 'private') }
  let!(:sibling) { PostStatusService.new.call(daniel.account, text: "@#{robin.account.username} 나는 있지!", thread: opener, visibility: 'private') }
  let!(:robin_aside) { PostStatusService.new.call(robin.account, text: "@#{daniel.account.username} 정말?", thread: sibling, visibility: 'private') }
  let!(:invite) { PostStatusService.new.call(system, text: "@#{becky.account.username} 신청했습니다", thread: command, visibility: 'private') }
  let!(:accept) { PostStatusService.new.call(robin.account, text: "@system [수락]", thread: invite, visibility: 'private') }
  let!(:session) do
    GameSession.create!(kind: 'jellybean', status: 'finished', visibility: 'private', root_status_id: command.id, last_status_id: accept.id, finished_at: Time.now.utc).tap do |created|
      created.players.create!(account: becky.account, seat: 0, result: 'win')
      created.players.create!(account: robin.account, seat: 1, result: 'lose')
    end
  end

  before { allow(Game::System).to receive(:account).and_return(system) }

  it 'shows only the command toot and the replies under it in the game room' do
    get "/api/v1/system/sessions/#{session.id}", headers: headers(becky)

    ids = response.parsed_body['messages'].filter_map { |message| message['id'] }
    expect(ids).to include(command.id.to_s, invite.id.to_s, accept.id.to_s)
    expect(ids).not_to include(sibling.id.to_s, robin_aside.id.to_s)
  end

  it 'deletes only that thread when staff remove the game record' do
    delete "/api/v1/system/sessions/#{session.id}", headers: headers(staff)
    Game::StatusCleanupWorker.drain

    expect(Status.unscoped.where(id: [command.id, invite.id, accept.id])).to be_empty
    expect(Status.unscoped.where(id: [opener.id, sibling.id, robin_aside.id]).count).to eq 3 # 로빈의 다른 답도 남는다
  end
end
