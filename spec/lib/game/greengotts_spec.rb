# frozen_string_literal: true

require 'rails_helper'

# 그린고츠 (웹 전용 이벤트, 4~24명 개인전): 혼자 고른 가장 작은 숫자에게 금화, 가장 많이 몰린 숫자에는 세금
RSpec.describe Game::Web::Greengotts do
  let!(:system) { Fabricate(:account, username: 'system') }
  let(:accounts) { Array.new(24) { |index| Fabricate(:account, username: "student#{index}") } }

  before do
    allow(Game::System).to receive(:account).and_return(system)
    allow(Game::Engine).to receive(:set_deadline_in!)
  end

  def session
    GameSession.where(kind: 'greengotts').order(:id).last.reload
  end

  def kind
    described_class.new(session)
  end

  def start_game!(count = 5, test: false)
    current = GameSession.create!(kind: 'greengotts', status: 'lobby', visibility: 'private', state: { 'mode' => 'event', 'test' => test || nil }.compact)
    accounts.first(count).each_with_index { |account, seat| current.players.create!(account: account, seat: seat, state: { 'accepted' => true }) }
    Game::Lobby.start!(current.reload)
  end

  def pick(seat, number)
    Game::WebCommand.play(session, accounts[seat], '입찰', [number.to_s])
  end

  # 자리 순서대로 숫자를 낸다 (모두 내면 바로 계산된다)
  def pick_all!(numbers)
    numbers.each_with_index { |number, seat| pick(seat, number) }
  end

  def scores
    session.state['scores'].transform_keys(&:to_i)
  end

  it 'starts in the pick phase with everybody at zero and a number range of players + 5' do
    start_game!(5)

    expect(session.state).to include('phase' => 'pick', 'round' => 1)
    expect(scores.values).to all(eq(0))
    expect(kind.view_for(session.players.first)[:max_number]).to eq 10
  end

  it 'pays the three smallest numbers chosen by one person: +3 / +2 / +1' do
    start_game!(6)
    pick_all!([5, 1, 1, 2, 4, 3]) # 혼자: 2(seat3) 3(seat5) 4(seat4) 5(seat0) — 1은 둘이라 무효

    result = session.state['results'].last
    expect(result['ranks'].map { |rank| [rank['seat'], rank['number'], rank['points']] }).to eq [[3, 2, 3], [5, 3, 2], [4, 4, 1]]
    expect(scores).to include(3 => 3, 5 => 2, 4 => 1, 0 => 0)
    expect(session.state['phase']).to eq 'reveal'
  end

  it 'taxes the people who chose the most popular number (2 or more) by 1 point' do
    start_game!(6)
    pick_all!([5, 1, 1, 1, 2, 3]) # 1을 셋이 골랐다 → 세금, 혼자: 2(seat4) 3(seat5) 5(seat0)

    expect(session.state['results'].last['taxed_numbers']).to eq [1]
    expect(scores).to include(1 => -1, 2 => -1, 3 => -1, 4 => 3, 5 => 2, 0 => 1)
  end

  it 'taxes every number that ties for the most popular, and nobody when all numbers are different' do
    start_game!(6)
    pick_all!([1, 1, 2, 2, 3, 4]) # 1 과 2 가 둘씩 → 둘 다 세금
    expect(session.state['results'].last['taxed_numbers']).to eq [1, 2]
    expect(scores).to include(0 => -1, 1 => -1, 2 => -1, 3 => -1, 4 => 3, 5 => 2)

    kind.timeout! # 공개가 끝나면 다음 라운드
    expect(session.state).to include('phase' => 'pick', 'round' => 2)
    pick_all!([6, 5, 4, 3, 2, 1])
    expect(session.state['results'].last['taxed_numbers']).to eq []
  end

  it 'gives nothing when no number was chosen by a single person' do
    start_game!(4)
    pick_all!([2, 2, 3, 3])

    result = session.state['results'].last
    expect(result['ranks']).to eq []
    expect(scores.values.sort).to eq [-1, -1, -1, -1]
  end

  it 'ignores out-of-range numbers and lets a player change the pick until everybody is in' do
    start_game!(4)
    pick(0, 0)
    pick(0, 10) # 4명 + 5 = 9 까지
    expect(session.state['picks']).to eq({})

    pick(0, 3)
    pick(0, 4)
    expect(session.state['picks']).to eq('0' => 4)
  end

  it 'drops people who did not pick in time from that round (no points, no tax, not counted)' do
    start_game!(5)
    pick(0, 1)
    pick(1, 1)
    pick(2, 2)
    kind.timeout! # 3, 4번은 못 냈다

    result = session.state['results'].last
    expect(result['absent']).to eq [3, 4]
    expect(result['counts']).to eq('1' => 2, '2' => 1)
    expect(scores).to include(0 => -1, 1 => -1, 2 => 3, 3 => 0, 4 => 0)
  end

  it 'hides this round\'s numbers until they are revealed' do
    start_game!(4)
    pick(0, 3)
    pick(1, 3)

    view = kind.view_for(session.players.find { |player| player.seat == 2 })
    expect(view[:reveal]).to be_nil
    expect(view[:my_pick]).to be_nil
    expect(view[:players].map { |player| player[:submitted] }).to eq [true, true, false, false]
    expect(kind.view_for(session.players.find { |player| player.seat == 0 })[:my_pick]).to eq 3

    pick(2, 1)
    pick(3, 2)
    expect(kind.view_for(nil)[:reveal]['picks']).to eq('0' => 3, '1' => 3, '2' => 1, '3' => 2)
  end

  it 'finishes after the configured rounds; the top score wins (ties share the win)' do
    Game::Config.update!('greengotts', 'rounds' => '2')
    start_game!(4)
    pick_all!([1, 2, 3, 4]) # seat0 +3, seat1 +2, seat2 +1
    kind.timeout!
    pick_all!([2, 1, 3, 4]) # seat1 +3, seat0 +2, seat2 +1
    kind.timeout!

    expect(session.status).to eq 'finished'
    expect(session.state['winner_seats']).to eq [0, 1] # 5점 동점
    expect(session.players.map(&:result)).to eq %w(win win lose lose)
  end

  it 'never stalls: when time runs out in every phase the game moves on until it ends' do
    Game::Config.update!('greengotts', 'rounds' => '3')
    start_game!(4)

    6.times { kind.timeout! if session.status == 'active' }
    expect(session.status).to eq 'finished'
    expect(session.state['results'].size).to eq 3
  end

  it 'gives points and rewards to the winner, but nothing in a test play' do
    Game::Config.update!('greengotts', 'points_win' => '10', 'rounds' => '1')
    house = GameHouse.create!(name: '그리핀도르', emoji: '🦁')
    accounts.first(4).each { |account| GameCharacter.for(account).update!(house: house) }
    start_game!(4)
    pick_all!([1, 2, 3, 4])
    kind.timeout!

    expect(session.state['winner_seats']).to eq [0]
    expect(GameHousePoint.where(game_session_id: session.id).sum(:amount)).to eq 10

    start_game!(4, test: true)
    pick_all!([1, 2, 3, 4])
    kind.timeout!
    expect(session.status).to eq 'finished'
    expect(GameHousePoint.where(game_session_id: session.id).count).to eq 0
  end
end
