# frozen_string_literal: true

require 'rails_helper'

# 비밀의방 (마피아형 서버 이벤트)
RSpec.describe Game::Events::SecretChamber do
  let!(:system) { Fabricate(:account, username: 'system') }
  let(:accounts) { %w(harry ron hermione draco neville luna ginny).map { |name| Fabricate(:account, username: name) } }
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
    expect(session.state['roles'].values.tally).to include('traitor' => 1, 'auror' => 1, 'healer' => 1, 'seer' => 1, 'student' => 3)
    dms = Status.where(account: system, visibility: :direct)
    expect(dms.count).to eq 7
    expect(GameEvent.last.payload['data']).to include('phase' => 'day', 'alive' => [0, 1, 2, 3, 4, 5, 6])
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

  it 'refuses more players than the maximum' do
    Game::Config.update!('secret_chamber', 'max_players' => '7', 'min_players' => '7')
    start_game!
    extra = Fabricate(:account, username: 'late')
    toot(accounts.first, '@system [비밀의방]') # 이미 진행 중이라 무시
    expect(session.players.size).to eq 7
    expect(extra).to be_persisted
  end

  it 'delivers the prophecy the traitor chose to the seer and keeps it in her notes, and shares secret chat only with traitors' do
    Game::Config.update!('secret_chamber', 'traitor_percent' => '30')
    start_game!
    session.with_lock { kind.timeout! }
    traitor = player_with('traitor')
    seer = player_with('seer')

    toot(traitor.account, '@system [예언/학생 중에 방주가 있다]', visibility: 'direct')
    expect(session.reload.state.dig('night', 'prophecy', 'text')).to eq '학생 중에 방주가 있다'
    session.with_lock { kind.timeout! }

    expect(session.reload.state.dig('notes', seer.seat.to_s).last['text']).to include('학생 중에 방주가 있다')
    expect(kind.view_for(seer)[:notes].size).to eq 1
    expect(kind.view_for(seer)[:dark_chat]).to eq []
    expect(kind.view_for(traitor)[:my_role][:name]).to eq '방주'
  end

  it 'reveals every role to eliminated players and hides them from the living' do
    start_game!
    session.with_lock { kind.timeout! }
    student = player_with('student')
    traitor = player_with('traitor')
    toot(traitor.account, "@system [석화] @#{student.account.username}", visibility: 'direct')
    session.with_lock { kind.timeout! }

    expect(kind.view_for(student)[:players].map { |p| p[:role_name] }).to all(be_present)
    other = players_without('traitor').find { |p| p.seat != student.seat && session.state['alive'].include?(p.seat) }
    expect(kind.view_for(other)[:players].reject { |p| p[:seat] == other.seat || p[:out] }.map { |p| p[:role_name] }.compact).to eq []
  end

  it 'ends when the phase limit is reached, with the dark side winning by default' do
    Game::Config.update!('secret_chamber', 'max_phases' => '2')
    start_game!
    session.with_lock { kind.timeout! } # 낮 → 밤 (1페이즈 지남)
    session.with_lock { kind.timeout! } # 밤 → 낮이 시작되려는데 페이즈 한도

    expect(session.reload.status).to eq 'finished'
    expect(session.state['winner']).to eq 'dark'
  end
end
