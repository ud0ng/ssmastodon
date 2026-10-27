# frozen_string_literal: true

require 'rails_helper'

# 캐릭터 관리 > 활동 > 시즌별: 시즌의 날짜 범위만큼의 일일 활동을 더한다 (시즌마다 0부터)
RSpec.describe Admin::GameActivitiesController do
  subject(:controller) { described_class.new }

  let(:account) { Fabricate(:user).account }

  def day(date, posts)
    GameActivityDay.create!(day: date, account_id: account.id, posts: posts, post_chars: posts * 10)
  end

  def rows
    controller.send(:load_season_rows, [account.id])
    controller.instance_variable_get(:@season_rows).to_h { |season, from, to, totals| [season.name, [from, to, totals.posts]] }
  end

  it 'adds up each season over its own dates and starts the next season from zero' do
    base = Date.new(2026, 10, 14)
    GameSeason.create!(name: '시즌1', status: 'finished', starts_on: base, ends_on: base + 1, finished_at: Time.zone.local(2026, 10, 15, 23, 0))
    GameSeason.create!(name: '시즌2', status: 'running', starts_on: base + 2, ends_on: base + 3)
    day(base - 1, 100) # 시즌 전
    day(base, 3)
    day(base + 1, 4)
    day(base + 2, 5)
    day(base + 3, 6)
    day(base + 4, 7) # 시즌2가 끝난 뒤

    expect(rows).to include('시즌1' => [base, base + 1, 7], '시즌2' => [base + 2, base + 3, 11])
  end

  it 'lets a season without dates start the day after the previous one and a running one count up to today' do
    first = GameSeason.create!(name: '시즌1', status: 'finished', starts_on: Date.new(2026, 10, 14), ends_on: Date.new(2026, 10, 15), finished_at: Time.current)
    expect(first).to be_finished
    GameSeason.create!(name: '시즌2', status: 'running')
    today = Game::ActivitySnapshot.today
    day(Date.new(2026, 10, 15), 2)
    day(Date.new(2026, 10, 16), 3)
    day(today, 4)

    result = rows
    expect(result['시즌2']).to eq [Date.new(2026, 10, 16), nil, 3 + (today == Date.new(2026, 10, 16) ? 0 : 4)]
    expect(result['시즌1'][2]).to eq 2
  end
end
