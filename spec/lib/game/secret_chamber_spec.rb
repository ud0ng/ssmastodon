# frozen_string_literal: true

require 'rails_helper'

# 비밀의방 (마피아형 서버 이벤트)
RSpec.describe Game::Events::SecretChamber do
  let!(:system) { Fabricate(:account, username: 'system') }
  let(:accounts) { %w(harry ron hermione draco neville).map { |name| Fabricate(:account, username: name) } }
  let(:house) { GameHouse.create!(name: '그리핀도르', emoji: '🦁') }

  before do
    accounts.each { |account| GameCharacter.for(account).update!(house: house) }
  end

  def toot(account, text, visibility: 'private')
    status = PostStatusService.new.call(account, text: text, visibility: visibility)
    Game::Engine.new(status).call
    status
  end

  def session
    GameSession.where(kind: 'secret_chamber').order(:id).last
  end

  def kind
    described_class.new(session.reload)
  end

  def player_with(role)
    session.reload.players.find { |player| session.state['roles'][player.seat.to_s] == role }
  end

  def players_without(role)
    session.reload.players.reject { |player| session.state['roles'][player.seat.to_s] == role }
  end

  def start_game!
    toot(accounts.first, '@system [비밀의방]')
    accounts.each { |account| toot(account, '@system [참가]') }
    session.with_lock { kind.recruitment_over! }
  end

  it 'recruits, then deals roles by DM and starts the first day' do
    start_game!

    expect(session).to have_attributes(status: 'active')
    expect(session.state).to include('phase' => 'day', 'day' => 1)
    expect(session.state['roles'].values.tally).to include('traitor' => 1, 'auror' => 1, 'healer' => 1, 'seer' => 1, 'student' => 1)
    dms = Status.where(account: system, visibility: :direct)
    expect(dms.count).to eq 5
    expect(GameEvent.last.payload['data']).to include('phase' => 'day', 'alive' => [0, 1, 2, 3, 4])
  end

  it 'cancels when too few join' do
    toot(accounts.first, '@system [비밀의방]')
    toot(accounts.second, '@system [참가]')
    session.with_lock { kind.recruitment_over! }

    expect(session.status).to eq 'cancelled'
  end

  it 'expels the most accused player and ends when the traitor is gone' do
    start_game!
    traitor = player_with('traitor')
    players_without('traitor').each do |player|
      toot(player.account, "@system [고발] @#{traitor.account.username}")
    end
    session.with_lock { kind.timeout! }

    expect(session.reload).to have_attributes(status: 'finished')
    expect(session.state['winner']).to eq 'light'
    expect(traitor.reload.result).to eq 'lose'
    expect(GameHousePoint.where(game_session_id: session.id).sum(:amount)).to be_positive
  end

  it 'petrifies at night unless the healer protects, and lets the auror investigate by DM' do
    start_game!
    session.with_lock { kind.timeout! } # 아무도 고발하지 않은 낮 → 밤

    expect(session.reload.state['phase']).to eq 'night'
    traitor = player_with('traitor')
    student = player_with('student')
    auror = player_with('auror')

    toot(auror.account, "@system [조사] @#{traitor.account.username}", visibility: 'direct')
    expect(Status.where(account: system, visibility: :direct).map(&:text)).to include(a_string_including('진영은 「어둠」'))

    toot(traitor.account, "@system [석화] @#{student.account.username}", visibility: 'direct')
    session.with_lock { kind.timeout! }

    expect(session.reload.state['alive']).to_not include(student.seat)
    expect(session.state).to include('phase' => 'day', 'day' => 2)
  end

  it 'ignores night actions sent publicly or by the wrong role' do
    start_game!
    session.with_lock { kind.timeout! }
    student = player_with('student')
    traitor = player_with('traitor')

    toot(student.account, "@system [석화] @#{traitor.account.username}", visibility: 'direct')
    expect(session.reload.state.dig('night', 'petrify')).to be_empty
  end
end
