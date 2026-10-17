# frozen_string_literal: true

require 'rails_helper'

# 컨텐츠 방(채팅), 컨텐츠 메뉴 배지(받은 신청), 웹 알림에서 컨텐츠 알림 빼기
RSpec.describe 'API V1 System rooms' do
  let(:user) { Fabricate(:user) }
  let(:token) { Fabricate(:accessible_access_token, resource_owner_id: user.id, scopes: 'read write') }
  let(:headers) { { 'Authorization' => "Bearer #{token.token}" } }
  let(:rival) { Fabricate(:user).account }
  let!(:system) { Fabricate(:account, username: 'system') }

  def toot(account, text, visibility: 'private')
    status = PostStatusService.new.call(account, text: text, visibility: visibility)
    Game::Engine.new(status).call
    status
  end

  it 'lists what waits for me (an invite, then my turn) for the contents menu badge and alerts' do
    toot(rival, "@system @#{user.account.username} [젤리빈]")

    get '/api/v1/system/wallet', headers: headers
    expect(response.parsed_body['invites']).to eq 1
    expect(response.parsed_body['todo'].size).to eq 1

    toot(user.account, '@system [수락]')
    session = GameSession.where(kind: 'jellybean').last
    my_turn = session.state['seat'] == session.player_for(user.account).seat

    get '/api/v1/system/wallet', headers: headers
    expect(response.parsed_body['todo'].size).to eq(my_turn ? 1 : 0)
  end

  it 'shows the game thread as chat messages, system messages with their cards' do
    toot(user.account, "@system @#{rival.username} [젤리빈]")
    session = GameSession.where(kind: 'jellybean').last

    get "/api/v1/system/sessions/#{session.id}", headers: headers

    body = response.parsed_body
    expect(body['player']).to be true
    first, second = body['messages']
    expect(first).to include('system' => false, 'mine' => true, 'text' => '[젤리빈]')
    expect(second).to include('system' => true, 'mine' => false)
    expect(second['card']).to include('kind' => 'jellybean')
  end

  it 'leaves game notifications out of the web notification list' do
    other = Sidekiq::Testing.inline! do
      PostStatusService.new.call(rival, text: "@system @#{user.account.username} [젤리빈]", visibility: 'private')
      PostStatusService.new.call(rival, text: "@#{user.account.username} 안녕", visibility: 'private')
    end

    get '/api/v2/notifications', headers: headers, params: { exclude_game: true }
    ids = response.parsed_body['notification_groups'].pluck('status_id')
    expect(ids).to eq [other.id.to_s]

    get '/api/v2/notifications', headers: headers
    expect(response.parsed_body['notification_groups'].size).to be > 1
  end
end
