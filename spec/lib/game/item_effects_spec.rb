# frozen_string_literal: true

require 'rails_helper'

# 아이템 효과 상자들 (상점 설정 > 아이템 모달 > 효과)
RSpec.describe Game::ItemEffects do
  before { GameCharacterField.ensure_defaults! }

  it 'keeps only filled boxes in screen order and turns durations into minutes' do
    effects = described_class.normalize({
      '1' => { 'type' => 'currency', 'currency' => 'item', 'item' => '사과', 'value' => '2' },
      '0' => { 'type' => 'stat', 'stat' => '힘', 'value' => '3', 'minutes' => '2', 'unit' => 'hour' },
      '2' => { 'type' => 'currency', 'currency' => 'money', 'value' => '' },
      '3' => { 'type' => 'special', 'kind' => 'rumor', 'text' => '호울러가 울린다 @모두' },
      '4' => { 'type' => 'nope' },
    })

    expect(effects).to eq [
      { 'type' => 'stat', 'stat' => '힘', 'value' => '3', 'minutes' => 120 },
      { 'type' => 'currency', 'currency' => 'item', 'value' => '2', 'item' => '사과' },
      { 'type' => 'special', 'kind' => 'rumor', 'text' => '호울러가 울린다 모두' },
    ]
  end

  it 'says what to pick when using and sums the effects up' do
    effects = described_class.normalize([{ type: 'currency', currency: 'house_points', value: '-10' }, { type: 'stat', stat: '힘', value: '1d6', minutes: 1, unit: 'day' }])

    expect(described_class.needs_house?(effects)).to be true
    expect(described_class.needs_character?(effects)).to be true
    expect(described_class.needs_text?(effects)).to be false
    expect(described_class.summary(effects)).to eq ['소속 점수 -10', '힘 +1d6 (1일)']
  end

  it 'checks stats, values and effect kinds' do
    house_fx = GameEffect.create!(kind: 'house', slot: 'card', preset: 'gold', name: '반짝')
    effects = described_class.normalize([{ type: 'stat', stat: '없음', value: 'abc' }, { type: 'fx', target: 'character', effect_id: house_fx.id }])

    expect(described_class.errors(effects)).to contain_exactly("'없음' 스탯이 없습니다.", a_string_including('abc'), a_string_including('캐릭터 효과가 아닙니다'))
  end

  it 'converts the old one-field items when migrating' do
    item = Struct.new(:use_target, :stat_name, :stat_value, :stat_minutes, :special_kind, :score_delta, :special_limit)
    migration = CreateGameEffects.new

    expect(migration.send(:convert, item.new('character', '힘', '2', 30, 'staff', 0, 5))).to eq [{ 'type' => 'character', 'kind' => 'rp' }, { 'type' => 'stat', 'stat' => '힘', 'value' => '2', 'minutes' => 30 }]
    expect(migration.send(:convert, item.new('special', '', '', 60, 'bomb', -10, 5))).to eq [{ 'type' => 'currency', 'currency' => 'house_points', 'value' => '-10' }]
    allow(migration).to receive(:report_counter_id).and_return(7)
    expect(migration.send(:convert, item.new('special', '', '', 60, 'report', -5, 2))).to eq [{ 'type' => 'counter', 'counter_id' => 7, 'value' => '1' }]
  end
end

require Rails.root.join('db/migrate/20261019000100_create_game_effects')
