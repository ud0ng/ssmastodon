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
end
