# frozen_string_literal: true

require 'rails_helper'

# 시즌 결산 툿: 중간 결산, 시즌 종료
RSpec.describe Game::Summary do
  let!(:system) { Fabricate(:account, username: 'system') }
  let(:gryffindor) { GameHouse.create!(name: '그리핀도르') }
  let(:slytherin) { GameHouse.create!(name: '슬리데린') }
  let(:season) { GameSeason.create!(name: '1학기', starts_on: Date.new(2026, 10, 1), ends_on: Date.new(2026, 11, 30)) }

  before do
    GameHousePoint.create!(house: gryffindor, amount: 10, reason: 'test')
    GameHousePoint.create!(house: slytherin, amount: 3, reason: 'test')
  end

  it 'posts the interim results with a card and keeps the season running' do
    expect { described_class.season_interim!(season) }.to change { Status.where(account: system).count }.by(1)

    status = Status.where(account: system).last
    expect(status.text).to include('1학기 중간 결산', '1. 그리핀도르 10점', '2. 슬리데린 3점')
    expect(status.game_event.payload['data']['houses'].first).to include('total' => 10)
    expect(season.reload).to be_running
  end

  it 'announces the final results and starts the points again' do
    described_class.season_final!(season)

    status = Status.where(account: system).last
    expect(status.text).to include('1학기 종료', '우승 기숙사: 그리핀도르')
    expect(season.reload).to have_attributes(status: 'finished')
    expect([gryffindor.total, slytherin.total]).to eq [0, 0]
  end
end
