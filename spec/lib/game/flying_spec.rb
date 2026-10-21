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

  it 'lets two survivors win together when the field cannot shrink further' do
    session = start!(4)
    [[0, 1], [1, 1], [2, 2], [3, 3]].each { |index, lane| pick(session, index, lane) }

    session.reload
    expect(session.status).to eq 'finished'
    expect(results(session)).to eq %w(lose lose win win)
    expect(session.state['ranks']).to eq [{ 'rank' => 1, 'seats' => [2, 3] }, { 'rank' => 2, 'seats' => [0, 1] }]
    expect(session.state['history'].first['results']).to eq('0' => 'crash', '1' => 'crash', '2' => 'pass', '3' => 'pass')
  end

  it 'keeps flying until one is left and ranks the fallen by the round they dropped' do
    session = start!(5)
    [[0, 1], [1, 1], [2, 2], [3, 3], [4, 4]].each { |index, lane| pick(session, index, lane) }

    expect(session.reload.status).to eq 'active'
    expect(session.state['alive']).to eq %w(2 3 4)
    expect(session.state['lanes']).to eq 2
    expect(session.state['round']).to eq 2

    [[2, 1], [3, 2], [4, 2]].each { |index, lane| pick(session, index, lane) }

    session.reload
    expect(session.status).to eq 'finished'
    expect(results(session)).to eq %w(lose lose win lose lose)
    expect(session.state['ranks']).to eq [{ 'rank' => 1, 'seats' => [2] }, { 'rank' => 2, 'seats' => [3, 4] }, { 'rank' => 3, 'seats' => [0, 1] }]
  end

  it 'drops the ones who did not choose when the time is up' do
    session = start!(4)
    [[0, 1], [1, 2], [2, 3]].each { |index, lane| pick(session, index, lane) }

    expect(session.reload.status).to eq 'active'
    described_class.new(session).timeout!

    session.reload
    expect(session.state['out']).to eq('3' => 1)
    expect(session.state['history'].first['results']['3']).to eq 'idle'
    expect(session.state['alive']).to eq %w(0 1 2)
  end

  it 'is a draw when everyone crashes in the first round' do
    session = start!(3)
    3.times { |index| pick(session, index, 1) }

    session.reload
    expect(session.status).to eq 'finished'
    expect(results(session)).to eq %w(draw draw draw)
  end

  it 'picks the silliest scenes for the MVP' do
    session = start!(5)
    [[0, 1], [1, 1], [2, 1], [3, 2], [4, 3]].each { |index, lane| pick(session, index, lane) }

    mvp = session.reload.state['mvp']
    expect(mvp.first).to include('kind' => 'pileup', 'round' => 1, 'seats' => [0, 1, 2])
    expect(mvp.first['text']).to include('같은 길로 몰려')
  end

  it 'ignores the picks of fallen players and unknown lanes' do
    session = start!(5)
    pick(session, 0, 9)
    expect(session.state['choices']).to eq({})
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
end
