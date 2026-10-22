# frozen_string_literal: true

require 'rails_helper'

# 비행 대결 (이벤트, 웹 전용): 혼자 고른 길만 통과, 겹치면 추락, 마지막 1인(더 줄일 수 없으면 2인)이 남을 때까지
RSpec.describe Game::Kinds::Flying do
  let!(:system) { Fabricate(:account, username: 'system') }
  let(:accounts) { %w(harry ron draco luna cedric).map { |name| Fabricate(:account, username: name) } }

  def start!(count)
    session = GameSession.create!(kind: 'flying', status: 'active', visibility: 'private', state: { 'mode' => 'event' })
    accounts.first(count).each_with_index { |account, index| session.players.create!(account: account, seat: index, state: { 'accepted' => true }) }
    described_class.new(session).start!
    session.reload
  end

  def pick(session, index, lane)
    Game::WebCommand.play(session.reload, accounts[index], '비행', [lane.to_s])
    session.reload
  end

  def results(session)
    session.players.order(:seat).map(&:result)
  end

  it 'is an event with fewer lanes than players and hides the choices of the round' do
    session = start!(4)

    expect(Game::Guide.group_of(described_class)).to eq 'group'
    expect(described_class.web?).to be true
    expect(session.status).to eq 'active'
    expect(session.state['lanes']).to eq 3
    expect(session.state['routes'].size).to eq 3

    pick(session, 0, 1)
    view = described_class.new(session).view_for(session.players.first)
    expect(view[:my_choice]).to eq 1
    expect(view[:players].map { |entry| entry[:chosen] }).to eq [true, false, false, false]
    expect(view[:history]).to eq []
  end

  # 내구도 2: 충돌 한 번은 내구도 -1, 두 번째에 추락. 금빛 고리 없이 시험하려고 고리는 끈다
  before { Game::Config.merge!('flying', 'ring_route' => false) }

  it 'takes one durability per crash and drops a flyer at zero' do
    session = start!(4)
    [[0, 1], [1, 1], [2, 2], [3, 3]].each { |index, lane| pick(session, index, lane) }

    session.reload
    expect(session.status).to eq 'active'
    expect(session.state['hp']).to eq('0' => 1, '1' => 1, '2' => 2, '3' => 2)
    expect(session.state['history'].first).to include('results' => { '0' => 'crash', '1' => 'crash', '2' => 'pass', '3' => 'pass' }, 'fell' => [], 'void' => false)

    # 3개 길 중 2개 (2라운드): 0·1이 또 부딪혀 둘 다 추락 → 남은 2·3은 내구도가 같아 공동 우승
    [[0, 1], [1, 1], [2, 2], [3, 3]].each { |index, lane| pick(session, index, lane) }
    session.reload
    expect(session.status).to eq 'finished'
    expect(results(session)).to eq %w(lose lose win win)
    expect(session.state['ranks']).to eq [{ 'rank' => 1, 'seats' => [2, 3] }, { 'rank' => 2, 'seats' => [0, 1] }]
  end

  it 'ranks the survivors by durability and the fallen by the round they dropped' do
    session = start!(5)
    session.state['hp'] = { '0' => 1, '1' => 1, '2' => 2, '3' => 2, '4' => 1 }
    session.save!
    [[0, 1], [1, 1], [2, 2], [3, 3], [4, 4]].each { |index, lane| pick(session, index, lane) }

    session.reload
    expect(session.state['out']).to eq('0' => 1, '1' => 1)
    expect(session.state['alive']).to eq %w(2 3 4)
    expect(session.state['round']).to eq 2

    [[2, 1], [3, 2], [4, 2]].each { |index, lane| pick(session, index, lane) }

    session.reload
    expect(session.status).to eq 'finished'
    expect(results(session)).to eq %w(lose lose win lose lose)
    expect(session.state['ranks']).to eq [{ 'rank' => 1, 'seats' => [2] }, { 'rank' => 2, 'seats' => [3] }, { 'rank' => 3, 'seats' => [4] }, { 'rank' => 4, 'seats' => [0, 1] }]
  end

  it 'drops no one who keeps durability, and the ones who did not choose lose one' do
    session = start!(4)
    [[0, 1], [1, 2], [2, 3]].each { |index, lane| pick(session, index, lane) }

    expect(session.reload.status).to eq 'active'
    described_class.new(session).timeout!

    session.reload
    expect(session.state['out']).to eq({})
    expect(session.state['hp']['3']).to eq 1
    expect(session.state['history'].first['results']['3']).to eq 'idle'
    expect(session.state['alive']).to eq %w(0 1 2 3)
  end

  it 'voids a round in which everybody would fall and picks the routes again' do
    session = start!(3)
    session.state['hp'] = { '0' => 1, '1' => 1, '2' => 1 }
    session.save!
    3.times { |index| pick(session, index, 1) }

    session.reload
    expect(session.status).to eq 'active'
    expect(session.state['history'].first).to include('void' => true, 'fell' => [])
    expect(session.state['hp']).to eq('0' => 1, '1' => 1, '2' => 1)
    expect(session.state['alive']).to eq %w(0 1 2)
    expect(session.state['round']).to eq 2
    expect(session.state['choices']).to eq({})
  end

  it 'gives one durability back to whoever flies the golden ring alone, up to the starting value' do
    Game::Config.merge!('flying', 'ring_route' => true)
    session = start!(4)
    session.state['hp'] = { '0' => 1, '1' => 2, '2' => 2, '3' => 2 }
    session.state['ring'] = 2
    session.save!
    [[0, 2], [1, 1], [2, 1], [3, 3]].each { |index, lane| pick(session, index, lane) }

    session.reload
    expect(session.state['history'].first['ring_gain']).to eq ['0']
    expect(session.state['hp']).to eq('0' => 2, '1' => 1, '2' => 1, '3' => 2)
  end

  it 'picks the silliest scenes for the MVP' do
    session = start!(5)
    session.state['hp'] = session.state['hp'].transform_values { 1 }
    session.save!
    [[0, 1], [1, 1], [2, 1], [3, 2], [4, 3]].each { |index, lane| pick(session, index, lane) }

    mvp = session.reload.state['mvp']
    expect(mvp.first).to include('kind' => 'pileup', 'round' => 1, 'seats' => [0, 1, 2])
    expect(mvp.first['text']).to include('같은 길로 몰려')
  end

  it 'ignores the picks of fallen players and unknown lanes' do
    session = start!(5)
    pick(session, 0, 9)
    expect(session.state['choices']).to eq({})
    session.state['hp'] = session.state['hp'].merge('0' => 1, '1' => 1)
    session.save!
    [[0, 1], [1, 1], [2, 2], [3, 3], [4, 4]].each { |index, lane| pick(session, index, lane) }

    pick(session, 0, 1)
    expect(session.state['choices']).to eq({})
  end
  it 'shows the waiting room with the recruiting time while players are being gathered' do
    session = GameSession.create!(kind: 'flying', status: 'pending', visibility: 'private', deadline_at: 20.minutes.from_now, state: { 'mode' => 'event', 'phase' => 'recruit' })
    session.players.create!(account: accounts.first, seat: 0, state: { 'accepted' => true })

    expect(Game::Lobby.recruiting?(session)).to be true
    view = Game::Lobby.view(session, accounts.first, staff: false)
    expect(view).to include(recruiting: true)
    expect(view[:recruit_ends_at]).to be_present
    expect(view[:players].size).to eq 1
  end
  it 'lets members join and cancel joining from the web before the game starts' do
    session = GameSession.create!(kind: 'flying', status: 'pending', visibility: 'private', deadline_at: 20.minutes.from_now, state: { 'mode' => 'event', 'phase' => 'recruit' })
    session.players.create!(account: accounts.first, seat: 0, state: { 'accepted' => true })
    newcomer = accounts.second
    allow(GameCharacter).to receive(:eligible_accounts).and_return(Account.where(id: accounts.map(&:id)))

    expect(Game::Lobby.view(session, newcomer, staff: false)).to include(can_join: true, can_leave: false)
    expect(Game::Lobby.join!(session, newcomer)).to eq :ok
    expect(Game::Lobby.join!(session, newcomer)).to eq :joined
    expect(session.reload.players.size).to eq 2
    expect(Game::Lobby.view(session, newcomer, staff: false)).to include(can_join: false, can_leave: true)

    expect(Game::Lobby.leave!(session, newcomer)).to eq :ok
    expect(session.reload.players.size).to eq 1
    expect(Game::Lobby.leave!(session, newcomer)).to eq :absent

    session.update!(status: 'active')
    expect(Game::Lobby.join!(session, newcomer)).to eq :closed
  end
  it 'opens straight into the waiting room for invited players, who accept or decline there, and keeps everyone else out' do
    allow(GameCharacter).to receive(:eligible_accounts).and_return(Account.where(id: accounts.map(&:id)))
    opener = Fabricate(:admin_user, account: Fabricate(:account, username: 'professor')).account
    session = Game::Events::Opening.open!(Game::Kinds.registry['flying'], opener, mode: 'pick', players: accounts.first(4))

    expect(session.reload.status).to eq 'lobby'
    view = Game::Lobby.view(session, accounts.first, staff: false)
    expect(view[:players].pluck(:waiting)).to eq [true, true, true, true]
    expect(view).to include(invite: true, can_respond: true, can_join: false)
    expect(Game::Lobby.view(session, accounts.last, staff: false)).to include(can_respond: false, can_join: false)
    expect(Game::Lobby.join!(session, accounts.last)).to eq :invite_only
    expect(Game::Lobby.accept_invite!(session, accounts.last)).to eq :not_invited

    expect(Game::Lobby.accept_invite!(session, accounts[0])).to eq :ok
    expect(Game::Lobby.accept_invite!(session, accounts[1])).to eq :ok
    expect(Game::Lobby.accept_invite!(session, accounts[2])).to eq :ok
    Game::Lobby.set_ready!(session.reload, accounts[0], true)
    expect(Game::Lobby.all_ready?(session)).to be false # 아직 답하지 않은 사람이 있다

    expect(Game::Lobby.decline_invite!(session, accounts[3])).to eq :ok
    expect(Game::Lobby.view(session.reload, accounts.first, staff: false)[:players].pluck(:waiting)).to eq [nil, nil, nil]
  end
end
