# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Game::Points do
  let(:alice) { Fabricate(:account) }
  let(:bob) { Fabricate(:account) }
  let(:gryffindor) { GameHouse.create!(name: '그리핀도르', emoji: '🦁') }
  let(:slytherin) { GameHouse.create!(name: '슬리데린', emoji: '🐍') }

  def finished_session
    GameSession.create!(kind: 'jellybean', status: 'finished').tap do |session|
      session.players.create!(account: alice, seat: 0)
      session.players.create!(account: bob, seat: 1)
    end
  end

  before do
    GameCharacter.for(alice).update!(house: gryffindor)
    GameCharacter.for(bob).update!(house: slytherin)
  end

  it 'awards points to the house and returns the announcement' do
    session = finished_session
    expect(described_class.award(session, session.players.first, 10)).to include('그리핀도르 +10점')
    expect(gryffindor.total).to eq 10
  end

  it 'pays the set points every time, whoever the opponent is' do
    GameCharacter.for(bob).update!(house: gryffindor)
    4.times do
      session = finished_session
      described_class.award(session, session.players.first, 10)
    end
    expect(gryffindor.total).to eq 40
  end

  it 'gives one point per won game in games mode' do
    Game::Config.update!('common', 'scoring_mode' => 'games')
    session = finished_session
    described_class.award(session, session.players.first, 50, outcome: 'win')
    described_class.award(session, session.players.second, 30, outcome: 'lose')

    expect([gryffindor.total, slytherin.total]).to eq [1, 0]
  end

  it 'starts counting again after a season ends' do
    first = finished_session
    described_class.award(first, first.players.first, 10)
    season = GameSeason.create!(name: '1학기')
    Game::Summary.season_final!(season)

    expect(gryffindor.total).to eq 0
    expect(season.reload).to have_attributes(status: 'finished')
    expect(season.results.first).to include('name' => '그리핀도르', 'total' => 10)
    later = finished_session
    described_class.award(later, later.players.first, 5)
    expect(gryffindor.total).to eq 5
  end

  it 'uses the configured name for houses (e.g. 진영 for the adult period)' do
    Game::Config.update!('common', 'house_label' => '진영')
    GameCharacter.for(alice).update!(house: nil)
    session = finished_session
    expect(described_class.award(session, session.players.first, 10)).to include('아직 진영이 없어')
    expect(described_class.board).to start_with('🏆 진영 점수')
  end

  it 'tells when the player has no house' do
    GameCharacter.for(alice).update!(house: nil)
    session = finished_session
    expect(described_class.award(session, session.players.first, 10)).to include('기숙사가 없어')
  end
end

RSpec.describe Game::Text do
  it 'fills placeholders and picks Korean particles by the final consonant' do
    expect(described_class.render('%{a}{이가} %{b}{을를} 먹었다', a: '해리', b: '젤리빈')).to eq '해리가 젤리빈을 먹었다'
    expect(described_class.render('%{a}{은는} %{b}{으로로}', a: '론', b: '교실')).to eq '론은 교실로'
    expect(described_class.render('%{a}{과와}', a: 'Ron')).to eq 'Ron과(와)'
    expect(described_class.render('「%{a}」{이가} 완성', a: '진실의 약')).to eq '「진실의 약」이 완성'
    expect(described_class.render('[%{a}]{으로로}', a: '강')).to eq '[강]으로'
  end
end

RSpec.describe 'Game::Points by faction' do
  let(:alice) { Fabricate(:account) }
  let(:bob) { Fabricate(:account) }

  it 'pays the faction when factions are the scoring unit' do
    GameHouse.ensure_defaults!
    order = GameHouse.factions.first
    house = GameHouse.houses.first
    GameCharacter.for(alice).update!(house: house, faction: order)
    Game::Config.merge!('common', 'group_mode' => 'faction')
    session = GameSession.create!(kind: 'jellybean', status: 'finished')
    session.players.create!(account: alice, seat: 0)
    session.players.create!(account: bob, seat: 1)

    expect(Game::Points.award(session, session.players.first, 10)).to include('진영').or include(order.name)
    expect(order.total).to eq 10
    expect(house.total).to eq 0
    expect(Game::Points.board).to include(order.name)
  end
end
