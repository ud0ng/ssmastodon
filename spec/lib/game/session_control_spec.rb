# frozen_string_literal: true

require 'rails_helper'

# 운영진이 멈추거나 잘못된 판을 직접 다루는 일 (관리 > 컨텐츠 > 진행 중)
RSpec.describe Game::SessionControl do
  let!(:system) { Fabricate(:account, username: 'system') }
  let!(:alice) { Fabricate(:account, username: 'alice') }
  let!(:bob) { Fabricate(:account, username: 'bob') }

  def toot(account, text, visibility: 'private')
    status = PostStatusService.new.call(account, text: text, visibility: visibility)
    Game::Engine.new(status).call
    status
  end

  def start_duel!
    toot(alice, '@system @bob [결투]')
    toot(bob, '@system [수락]')
    GameSession.where(kind: 'duel').order(:id).last
  end

  it 'cancels a game without results' do
    session = start_duel!
    described_class.cancel!(session)

    expect(session.reload.status).to eq 'cancelled'
    expect(session.players.map(&:result)).to all(be_nil)
  end

  it 'ends a game as a draw' do
    session = start_duel!
    described_class.draw!(session)

    expect(session.reload.status).to eq 'finished'
    expect(session.players.map(&:result)).to all(eq 'draw')
  end

  it 'ends a game with the chosen winner' do
    session = start_duel!
    described_class.decide!(session, session.player_for(bob))

    expect(session.reload.status).to eq 'finished'
    expect(session.player_for(bob).result).to eq 'win'
    expect(session.player_for(alice).result).to eq 'lose'
  end

  it 'advances a stuck turn as if the time ran out and closes an unanswered invite' do
    session = start_duel!
    turn = session.turn
    described_class.advance!(session)
    expect(session.reload.turn).to be >= turn

    toot(alice, '@system @bob [결투]')
    pending = GameSession.where(kind: 'duel').order(:id).last
    pending.players.where(account: bob).update_all("state = '{}'") if pending.status == 'pending'
    described_class.advance!(pending)
    expect(pending.reload.status).to eq('cancelled').or eq('active')
  end

  it 'leaves tournament matches to the tournament screen' do
    session = start_duel!
    session.update!(state: session.state.merge('tournament_match_id' => '1'))
    described_class.cancel!(session)

    expect(session.reload.status).to eq 'active'
  end
end
