# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Game::Tournament do
  let!(:system) { Fabricate(:account, username: 'system') }
  let(:gryffindor) { GameHouse.create!(name: '그리핀도르', emoji: '🦁') }
  let(:slytherin) { GameHouse.create!(name: '슬리데린', emoji: '🐍') }
  let(:harry) { Fabricate(:account, username: 'harry') }
  let(:ron) { Fabricate(:account, username: 'ron') }
  let(:draco) { Fabricate(:account, username: 'draco') }
  let(:pansy) { Fabricate(:account, username: 'pansy') }
  let(:tournament) { GameTournament.create!(name: '기숙사 대항전', size: 4, reward: 50) }

  before do
    { harry => gryffindor, ron => gryffindor, draco => slytherin, pansy => slytherin }.each do |account, house|
      GameCharacter.for(account).update!(house: house)
    end
    Game::Config.update!('common', 'scoring_mode' => 'tournament')
  end

  def semifinal(position)
    tournament.matches.reload.find { |match| match.round == 1 && match.position == position }
  end

  def final
    tournament.matches.reload.find { |match| match.round == 2 }
  end

  def set_up_semifinals
    semifinal(0).update!(kind: 'jellybean', scheduled_at: 1.hour.from_now, player_a: harry, player_b: draco)
    semifinal(1).update!(kind: 'jellybean', scheduled_at: 2.hours.from_now, player_a: ron, player_b: pansy)
  end

  it 'builds the bracket for the number of people' do
    expect(tournament.matches.size).to eq 3
    expect(tournament.rounds).to eq 2
    expect(tournament.round_name(2)).to eq '결승'
  end

  it 'schedules ready matches when started and opens them on time' do
    set_up_semifinals
    described_class.start!(tournament)

    expect(semifinal(0).status).to eq 'ready'
    expect(final.status).to eq 'waiting'
    expect(Game::TournamentWorker.jobs.size).to eq 2

    match = semifinal(0)
    Game::TournamentWorker.new.perform(match.id, match.schedule_token)
    match.reload
    expect(match.status).to eq 'playing'
    expect(match.session).to have_attributes(kind: 'jellybean', status: 'active')
    expect(Status.find(match.session.root_status_id).text).to include('기숙사 대항전', '준결승', '1경기')
  end

  it 'ignores a stale schedule after the time changed' do
    set_up_semifinals
    described_class.start!(tournament)
    match = semifinal(0)
    token = match.schedule_token
    match.update!(scheduled_at: 3.hours.from_now)

    Game::TournamentWorker.new.perform(match.id, token)
    expect(match.reload.status).to eq 'ready'
  end

  it 'moves winners up, waits for staff on timeouts, and crowns the house with the most wins' do
    set_up_semifinals
    described_class.start!(tournament)

    # 준결승 1: 해리 승 (말포이가 기권)
    first = semifinal(0)
    Game::TournamentWorker.new.perform(first.id, first.schedule_token)
    first.reload.session.kind_class.new(first.session).forfeit!(first.session.player_for(draco))
    expect(semifinal(0)).to have_attributes(status: 'done', winner: harry)
    expect(final.player_a).to eq harry

    # 준결승 2: 시간 초과 → 운영진 판정으로 팬지 승
    second = semifinal(1)
    Game::TournamentWorker.new.perform(second.id, second.schedule_token)
    session = second.reload.session
    described_class.judging!(session, '응답 없음')
    expect(semifinal(1).status).to eq 'judging'
    described_class.decide!(semifinal(1), pansy)
    expect(final.player_b).to eq pansy

    # 결승: 팬지 승 → 1:1 동률, 결승 승자의 소속(슬리데린) 우승
    final.update!(kind: 'jellybean', scheduled_at: Time.now.utc)
    described_class.schedule!(final)
    Game::TournamentWorker.new.perform(final.id, final.schedule_token)
    described_class.decide!(final, pansy)

    expect(tournament.reload).to have_attributes(status: 'finished', winner_house: slytherin)
    expect(slytherin.total).to eq 50
    expect(gryffindor.total).to eq 0
    expect(Status.where(account: system).map(&:text)).to include(a_string_including('우승: 슬리데린'))
  end

  it 'gives no points for regular content in tournament mode' do
    session = GameSession.create!(kind: 'jellybean', status: 'finished').tap do |created|
      created.players.create!(account: harry, seat: 0)
      created.players.create!(account: draco, seat: 1)
    end
    expect(Game::Points.award(session, session.players.first, 10)).to be_nil
    expect(GameHousePoint.count).to eq 0
  end
end
