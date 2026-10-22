# frozen_string_literal: true

require 'rails_helper'

# 누적 수치: 최대 누적치·상성 상쇄·최대치/영구 효과 (상점 설정 > 누적 수치 목록)
RSpec.describe GameCounter do
  let!(:harry) { Fabricate(:account, username: 'harry') }
  let(:character) { GameCharacter.for(harry) }
  let!(:report) { described_class.create!(name: '신고', max_count: 5, position: 0) }
  let!(:praise) { described_class.create!(name: '칭찬', max_count: 5, position: 1, opposite: report) }

  before { report.reload }

  it 'pairs the opposite counters both ways' do
    expect(report.reload.opposite).to eq praise
  end

  it 'cancels the opposite counter out of the result' do
    report.add!(character, 5)
    praise.add!(character, 2)

    expect(report.net_for(character.reload)).to eq 3
    expect(praise.net_for(character)).to eq 0
    expect(report.raw_for(character)).to eq 5

    praise.add!(character, 6)
    expect(praise.net_for(character.reload)).to eq 3
    expect(report.net_for(character)).to eq 0
  end

  it 'keeps counting past the max and logs change, result and total' do
    report.add!(character, 7)
    _before, after, = report.add!(character, 1, item: '고발장')

    expect(after).to eq 8
    log = report.logs.order(:id).last
    expect([log.delta, log.net, log.raw, log.reason]).to eq [1, 8, 8, '고발장']
  end

  context 'with effects' do
    let(:fx) { GameEffect.create!(kind: 'character', slot: 'title', preset: 'gold', name: '반짝') }
    let(:four_fx) { GameEffect.create!(kind: 'character', slot: 'deco', preset: 'gold', name: '네번째') }

    before do
      report.rules.create!(at_max: true, game_effect_id: fx.id, minutes: 60)
      report.rules.create!(threshold: 4, game_effect_id: four_fx.id, minutes: 60)
    end

    it 'adds the permanent max effect at the max and removes it when it drops, bringing the 4 effect back' do
      report.add!(character, 4)
      expect(character.reload.active_effects.map { |effect| effect['effect_id'] }).to eq [four_fx.id]

      _, _, notes = report.add!(character, 1)
      expect(notes.join).to include('최대치').and include('영구')
      expect(character.reload.active_effects.map { |effect| effect['effect_id'] }).to contain_exactly(four_fx.id, fx.id)

      report.add!(character, 3) # 8 → 계속 올라간다
      expect(report.net_for(character.reload)).to eq 8

      praise.add!(character, 4) # 결과값 8 → 4: 최대치 효과를 거두고 4 효과가 다시 붙는다
      effects = character.reload.active_effects
      expect(effects.map { |effect| effect['effect_id'] }).to eq [four_fx.id]
    end

    it 'does not stack the same rule effect twice' do
      report.add!(character, 5)
      report.add!(character, -1)
      report.add!(character, 1)

      expect(character.reload.active_effects.count { |effect| effect['effect_id'] == fx.id }).to eq 1
    end
  end

  describe 'house points' do
    let!(:ron) { Fabricate(:account, username: 'ron') }
    let(:house) { GameHouse.create!(name: '그리핀도르', color: '#ae0001', category: 'house') }

    before do
      GameHouse.where.not(id: house.id).delete_all
      GameCharacter.for(harry).update!(house: house)
      GameCharacter.for(ron).update!(house: house)
    end

    it 'does not turn the opposite counter on and keeps their own interval and amount' do
      report.update!(affects_house: true, house_interval_minutes: 60, house_amount: -2)

      expect(praise.reload.affects_house).to be false
      praise.update!(house_interval_minutes: 120, house_amount: 3)
      expect(report.reload).to have_attributes(affects_house: true, house_interval_minutes: 60, house_amount: -2)
      expect(praise.reload.affects_house).to be false
    end

    it 'takes house points every interval by the result value times the amount, never twice for the same interval' do
      report.update!(affects_house: true, house_interval_minutes: 60, house_amount: -2)
      report.add!(GameCharacter.for(harry), 4)
      report.add!(GameCharacter.for(ron), 1)
      start = Time.zone.parse('2026-10-20 10:00')

      report.apply_house_points!(start)
      expect(GameHousePoint.count).to eq 0 # 처음 켠 때부터 센다

      report.apply_house_points!(start + 30.minutes)
      expect(GameHousePoint.count).to eq 0

      report.apply_house_points!(start + 61.minutes)
      points = GameHousePoint.where(game_counter_id: report.id)
      expect(points.pluck(:amount)).to contain_exactly(-8, -2)
      expect(points.first.reason).to include('신고')
      expect(house.reload.total).to eq(-10)

      report.apply_house_points!(start + 62.minutes)
      expect(GameHousePoint.where(game_counter_id: report.id).count).to eq 2
    end

    it 'uses the result value after the opposite counter cancels it' do
      report.update!(affects_house: true, house_amount: -1)
      report.add!(GameCharacter.for(harry), 10)
      praise.add!(GameCharacter.for(harry), 5)
      start = Time.zone.parse('2026-10-20 10:00')

      report.apply_house_points!(start)
      report.apply_house_points!(start + 1.hour)

      expect(GameHousePoint.pluck(:amount)).to eq [-5]
    end
  end
end
