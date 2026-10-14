# frozen_string_literal: true

require 'rails_helper'

# 정기 툿: 주간 결산, 학기 마감
RSpec.describe Game::Summary do
  let!(:system) { Fabricate(:account, username: 'system') }
  let(:harry) { Fabricate(:account, username: 'harry') }
  let(:gryffindor) { GameHouse.create!(name: '그리핀도르', emoji: '🦁') }
  let(:slytherin) { GameHouse.create!(name: '슬리데린', emoji: '🐍') }

  before do
    GameCharacter.for(harry).update!(name: '해리', house: gryffindor)
    GameHousePoint.create!(house: gryffindor, amount: 10, reason: 'test')
    GameHousePoint.create!(house: slytherin, amount: 3, reason: 'test', created_at: 10.days.ago)
  end

  it 'is due only on the configured weekday and hour (Korean time)' do
    sunday_nine_pm = Time.zone.parse('2026-10-18 12:00 UTC') # 21:00 KST, Sunday
    expect(described_class.weekly_due?(sunday_nine_pm)).to be true
    expect(described_class.weekly_due?(sunday_nine_pm + 1.hour)).to be false
  end

  it 'posts the weekly summary once per week with a card' do
    now = Time.now.utc
    expect { described_class.weekly!(now) }.to change { Status.where(account: system).count }.by(1)
    expect { described_class.weekly!(now) }.to_not(change { Status.where(account: system).count })

    status = Status.where(account: system).last
    expect(status.text).to include('그리핀도르 +10', '슬리데린 +0')
    expect(status.game_event.payload).to include('kind' => 'weekly')
  end

  it 'announces the end of term with the champion and subject toppers' do
    GameGrade.create!(account: harry, subject: 'levitation', grade: 'O', mode: 'study')
    described_class.term_end!

    status = Status.where(account: system).last
    expect(status.text).to include('그리핀도르', '해리 (O)')
    expect(status.game_event.payload['data']['champion']).to include('name' => '그리핀도르')
  end
end
