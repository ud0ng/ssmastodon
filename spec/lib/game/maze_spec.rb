# frozen_string_literal: true

require 'rails_helper'

# 트라이위저드 미로 (웹 전용 이벤트, 2~24명): 모두 동시에 웹에서 길을 고르고, 조우·마법 생물도 웹에서 고른다
RSpec.describe Game::Web::Maze do
  let!(:system) { Fabricate(:account, username: 'system') }
  let(:names) { %w(harry cedric fleur viktor) }
  let(:accounts) { names.map { |name| Fabricate(:account, username: name) } }
  let(:gryffindor) { GameHouse.create!(name: '그리핀도르', emoji: '🦁') }
  let(:hufflepuff) { GameHouse.create!(name: '후플푸프', emoji: '🦡') }

  before do
    allow(Game::System).to receive(:account).and_return(system)
    accounts.each_with_index { |account, index| GameCharacter.for(account).update!(house: index.even? ? gryffindor : hufflepuff) }
  end

  def session
    GameSession.where(kind: 'maze').order(:id).last.reload
  end

  def kind
    described_class.new(session)
  end

  def player(account)
    session.players.find { |each| each.account_id == account.id }
  end

  def act(account, command, args = [], targets: [])
    Game::WebCommand.play(session, account, command, args, targets: targets)
  end

  def start_game!(count = 4)
    current = GameSession.create!(kind: 'maze', status: 'lobby', visibility: 'private', state: { 'mode' => 'event' })
    accounts.first(count).each_with_index { |account, seat| current.players.create!(account: account, seat: seat, state: { 'accepted' => true }) }
    Game::Lobby.start!(current.reload)
  end

  # 벽 없는 빈 미로에 사람 위치만 정한다 (기본은 함정·생물·아이템·가짜 우승컵 없음)
  def open_field!(positions, cup: [7, 7], **extra)
    current = session
    count = current.state['size'] * current.state['size']
    current.state.merge!('traps' => [], 'creatures' => [], 'items' => [], 'fakes' => [], 'cup' => cup, 'cells' => Array.new(count, 15),
                         'positions' => positions.transform_keys(&:to_s), 'phase' => 'move', 'moves' => {}, 'met' => {}, **extra.transform_keys(&:to_s))
    current.save!
  end

  def stays(except: [])
    accounts.first(session.players.size).each { |account| act(account, '대기') unless except.include?(account) }
  end

  it 'builds the maze by the number of players and starts from the entrances' do
    start_game!(4)

    expect(session).to have_attributes(status: 'active', turn: 1)
    expect(session.state).to include('size' => 15, 'max_turns' => 25, 'fakes' => [], 'phase' => 'move')
    starts = session.state['positions'].values
    expect(starts.uniq.size).to eq 4 # 2~4명은 각자 다른 입구
    expect(starts).to all(satisfy { |spot| session.state['gates'].include?(spot) })
    expect(described_class.tier(7)).to include(size: 21, fakes: 1, turns: 30)
    expect(described_class.tier(20)).to include(size: 27, fakes: 2, turns: 40, entrances: 8)
    expect(described_class.event_only?).to be true
  end

  it 'shows a player only what is near, and spectators everything' do
    start_game!(2)
    view = kind.view_for(player(accounts.first))
    expect(view[:cells].size).to be < 15 * 15
    expect(view[:cups].pluck(:real).compact).to eq [] # 진짜인지는 알려 주지 않는다
    expect(kind.view_for(nil)).to include(full: true, spectator: true)
    expect(kind.view_for(nil)[:cups].find { |cup| cup[:real] }).to include(x: session.state['cup'][0])
  end

  it 'moves everyone at once and ends with the first to reach the real cup through the common finish' do
    Game::Config.update!('maze', 'points_win' => '10')
    start_game!(2)
    harry, cedric = accounts
    open_field!({ 0 => [5, 7], 1 => [0, 0] })

    act(harry, '이동', %w(동 동))
    expect(session.state['moves']).to have_key('0')
    act(cedric, '대기')

    expect(session.status).to eq 'finished'
    expect(player(harry).result).to eq 'win'
    expect(player(cedric).result).to eq 'lose'
    expect(GameHousePoint.where(game_session_id: session.id).sum(:amount)).to eq 10
    expect(session.state['ranks'].first).to include('seat' => 0, 'rank' => 1, 'dist' => 0)
  end

  it 'gives no points in a test play (the common finish)' do
    Game::Config.update!('maze', 'points_win' => '10')
    start_game!(2)
    current = session
    current.state['test'] = true
    current.save!
    open_field!({ 0 => [6, 7], 1 => [0, 0] })
    act(accounts.first, '이동', %w(동))
    act(accounts.second, '대기')

    expect(session.status).to eq 'finished'
    expect(GameHousePoint.where(game_session_id: session.id).count).to eq 0
  end

  it 'stops on a trap for a turn, and warps from a fake cup to an entrance' do
    start_game!(2)
    harry, cedric = accounts
    open_field!({ 0 => [2, 2], 1 => [10, 10] }, traps: [[3, 2]], fakes: [[10, 12]])

    act(harry, '이동', %w(동 동))
    act(cedric, '이동', %w(남 남))

    state = session.state
    expect(state['positions']['0']).to eq [3, 2]
    expect(state['status']['0']['stunned']).to eq 1
    expect(state['known_traps']['0']).to eq [[3, 2]]
    expect(state['gates']).to include(state['positions']['1'])
    expect(state['grabbed']['1']).to eq [[10, 12]]
    expect(kind.view_for(player(harry))[:cups]).to all(satisfy { |cup| !cup[:broken] })
    expect(session.status).to eq 'active'
  end

  it 'asks for a spell at a creature: the right one removes it, a wrong one stuns for two turns' do
    start_game!(2)
    harry, cedric = accounts
    open_field!({ 0 => [2, 2], 1 => [10, 10] }, creatures: [{ 'x' => 3, 'y' => 2, 'kind' => 'boggart' }, { 'x' => 11, 'y' => 10, 'kind' => 'dementor' }])

    act(harry, '이동', %w(동 동))
    act(cedric, '이동', %w(동))
    expect(session.state['phase']).to eq 'encounter'
    expect(kind.view_for(player(harry))[:encounter][:creature]).to include(name: '보가트', hint: a_string_including('웃음'))

    act(harry, '주문', ['리디큘러스'])
    act(cedric, '주문', ['stupefy'])

    state = session.state
    expect(state['phase']).to eq 'move'
    expect(state['creatures'].map { |each| each['kind'] }).to eq ['dementor']
    expect(state['status']['1']['stunned']).to eq 2
    expect(state['positions']['0']).to eq [3, 2] # 생물 칸에서 멈춘다
  end

  it 'lets players who meet choose in secret: cooperation shares maps, a hinder stuns and marks hostility' do
    start_game!(3)
    harry, cedric, fleur = accounts
    open_field!({ 0 => [5, 5], 1 => [6, 5], 2 => [5, 6] })
    stays
    expect(session.state['phase']).to eq 'encounter'
    expect(session.state['encounter']['groups']).to eq [%w(0 1 2)]

    act(harry, '협력')
    act(cedric, '협력')
    act(fleur, '방해', targets: [harry])

    state = session.state
    expect(state['status']['0']['stunned']).to eq 1
    expect(state['hostile']).to eq [[2, 0]]
    expect(state['seen']['0']).to eq state['seen']['1']
    expect(state['phase']).to eq 'move'
    expect(session.turn).to eq 2
  end

  it 'shares the map among teammates and never makes them meet in the house team mode' do
    Game::Config.update!('maze', 'team_mode' => '1')
    start_game!(4)
    harry, cedric, fleur = accounts
    expect(session.state['teams']['0']).to eq session.state['teams']['2'] # harry · fleur 그리핀도르
    open_field!({ 0 => [5, 5], 1 => [9, 9], 2 => [5, 6], 3 => [12, 12] })
    stays

    expect(session.state['phase']).to eq 'move' # 팀원끼리는 조우가 없다
    expect(session.state['seen']['0']).to eq session.state['seen']['2']
    open_field!({ 0 => [6, 7], 1 => [0, 0], 2 => [1, 1], 3 => [12, 12] })
    act(harry, '이동', %w(동))
    act(cedric, '대기')
    act(fleur, '대기')
    act(accounts[3], '대기')
    expect(player(fleur).result).to eq 'win'
    expect(session.state['team_ranks'].first).to include('rank' => 1)
  end

  it 'drops out with the red sparks and ends without a winner when everyone has' do
    start_game!(2)
    harry, cedric = accounts
    act(harry, '붉은불꽃')
    expect(session.state['out']).to eq [0]
    expect(session.status).to eq 'active'
    act(cedric, '붉은불꽃')
    expect(session.status).to eq 'finished'
    expect(session.players.map(&:result).uniq).to eq ['draw']
  end

  it 'uses point me once for the real cup direction and lumos to see further' do
    start_game!(2)
    harry, = accounts
    open_field!({ 0 => [2, 2], 1 => [12, 12] }, inventory: { '0' => { 'pointme' => 1, 'lumos' => 1 }, '1' => {} })
    act(harry, '포인트미')
    expect(session.state['hint']['0']['dir']).to eq '↘'
    expect(session.state['inventory']['0']['pointme']).to eq 0
    act(harry, '루모스')
    expect(kind.view_for(player(harry))[:vision]).to eq 3
  end
end
