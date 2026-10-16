# frozen_string_literal: true

require 'rails_helper'

# 시스템 툿마다 남기는 컨텐츠 카드 (PC 웹에서 툿 대신 카드로 그린다)
RSpec.describe Game::Card do
  let!(:system) { Fabricate(:account, username: 'system') }
  let(:alice) { Fabricate(:account, username: 'alice') }
  let(:bob) { Fabricate(:account, username: 'bob') }
  let(:gryffindor) { GameHouse.create!(name: '그리핀도르', emoji: '🦁', color: '#ae0001') }

  before do
    GameCharacter.for(alice).update!(name: '해리', house: gryffindor)
    GameCharacter.for(bob).update!(name: '드레이코')
  end

  def toot(account, text, visibility: 'private')
    status = PostStatusService.new.call(account, text: text, visibility: visibility)
    Game::Engine.new(status).call
    status
  end

  def last_card
    GameEvent.order(:id).last
  end

  it 'records the invite with players and accept/decline buttons for the invited player' do
    toot(alice, '@system @bob [젤리빈]')

    event = last_card
    expect(event.status.account).to eq system
    expect(event.payload).to include('kind' => 'jellybean', 'phase' => 'pending')
    expect(event.payload['players']).to contain_exactly(
      a_hash_including('name' => '해리', 'accepted' => true, 'house' => a_hash_including('name' => '그리핀도르', 'color' => '#ae0001')),
      a_hash_including('name' => '드레이코', 'accepted' => false, 'house' => nil)
    )
    expect(event.payload['actions'].pluck('command')).to eq %w(수락 거절 신청취소)
    expect(event.payload['actions'].first['seats']).to eq [1]
    # 신청 취소는 신청한 사람(자리 0)에게만, 차례 알림에는 세지 않는 보조 버튼
    expect(event.payload['actions'].last).to include('seats' => [0], 'meta' => true)
    expect(event).to be_live
  end

  it 'tracks the jellybean bag, the eaten beans and whose turn it is' do
    toot(alice, '@system @bob [젤리빈]')
    toot(bob, '@system [수락]')

    start = last_card.payload
    expect(start).to include('phase' => 'active', 'turn' => 1)
    expect(start['data']).to include('remaining' => 10, 'total' => 10, 'worst_total' => 1)
    current = start['data']['current_seat']
    expect(start['actions'].first).to include('command' => '먹기', 'seats' => [current], 'dm' => false)

    eater = current.zero? ? alice : bob
    session = GameSession.last
    session.update!(state: session.state.merge('bag' => Array.new(10) { { 'flavor' => '딸기 맛', 'worst' => false } }))
    toot(eater, '@system [먹기/2]')

    turn = last_card.payload
    expect(turn['data']).to include('remaining' => 8, 'last_eaten' => a_hash_including('seat' => current))
    expect(turn['data']['last_eaten']['beans'].size).to eq 2
    expect(turn['data']['current_seat']).to_not eq current
  end

  it 'keeps only the newest card of an open game live and drops buttons when it ends' do
    toot(alice, '@system @bob [젤리빈]')
    invite = last_card
    toot(bob, '@system [거절]')

    expect(invite.reload).to_not be_live
    expect(last_card.payload).to include('phase' => 'cancelled', 'actions' => [])
  end

  it 'shows the card in the API only for system toots' do
    toot(alice, '@system @bob [젤리빈]')
    system_status = last_card.status
    human_status = Status.where(account: alice).last

    json = ActiveModelSerializers::SerializableResource.new(system_status, serializer: REST::StatusSerializer, scope: nil, scope_name: :current_user).as_json
    expect(json[:game_card]).to include('kind' => 'jellybean', 'live' => true)

    json = ActiveModelSerializers::SerializableResource.new(human_status, serializer: REST::StatusSerializer, scope: nil, scope_name: :current_user).as_json
    expect(json).to_not have_key(:game_card)
  end
end
