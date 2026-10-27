# frozen_string_literal: true

require 'rails_helper'

# 효과: 스킨 자리·영구·목록 안 효과 고치기/지우기 (관리 화면 캐릭터 상세·소속)
RSpec.describe Game::Fx do
  let(:effect) { GameEffect.create!(kind: 'character', slot: 'skin', preset: 'debut', name: '데뷔탕트 스킨') }

  it 'has a skin slot for characters and a debut look' do
    expect(described_class::SLOTS['character']).to include('skin')
    expect(described_class::PRESETS['skin']).to include('debut', 'debut2')
    expect(described_class::PRESETS.values_at('title', 'deco').map { |presets| presets.key?('debut2') }).to eq [true, true]
    expect(described_class::PRESETS['title']).to include('debut')
    expect(described_class::PRESETS['deco']).to include('debut')
  end

  it 'has house victory looks (card, title, deco, skin) for all four houses in the default effect list' do
    houses = %w(gryffindor hufflepuff slytherin ravenclaw)
    %w(card title deco skin).each { |slot| expect(described_class::PRESETS[slot].keys).to include(*houses) }

    defaults = described_class.defaults.select { |item| houses.include?(item[:preset]) }
    expect(defaults.size).to eq 16
    expect(defaults.find { |item| item[:slot] == 'title' && item[:preset] == 'slytherin' }).to include(kind: 'character', name: '슬리데린 승리 칭호')
    expect(defaults.find { |item| item[:slot] == 'card' && item[:preset] == 'ravenclaw' }).to include(kind: 'house', name: '래번클로 승리')
    expect(defaults.pluck(:description)).to all(include('승리 보상'))
    expect([described_class.particle_count('ravenclaw'), described_class.particle_count('gold')]).to eq [30, 6]

    GameEffect.seed_missing!
    expect(GameEffect.where(preset: houses).count).to eq 16
  end

  it 'makes permanent entries that stay active' do
    entry = described_class.entry(effect, 10, permanent: true)

    expect(described_class.permanent?(entry)).to be true
    expect(described_class.active([entry])).to eq [entry]
    expect(described_class.permanent?(described_class.entry(effect, 60))).to be false
  end

  it 'changes or removes one entry only when the effect id matches' do
    list = [described_class.entry(effect, 60), described_class.entry(effect, 120)]
    later = 3.days.from_now.change(usec: 0)

    changed = described_class.change_entry(list, 1, effect.id, later)
    expect(Time.zone.parse(changed[1]['until'])).to eq later
    expect(changed[0]).to eq list[0]

    expect(described_class.change_entry(list, 1, effect.id + 1, later)).to eq list
    expect(described_class.change_entry(list, 0, effect.id, nil)).to eq [list[1]]
  end
  it 'lists what a character is wearing per slot (last one wins, ended ones are left out)' do
    title = GameEffect.create!(kind: 'character', slot: 'title', preset: 'gold', name: '금빛 칭호')
    deco = GameEffect.create!(kind: 'character', slot: 'deco', preset: 'gold', name: '금빛 데코')
    character = GameCharacter.for(Fabricate(:account))
    ended = described_class.entry(deco, 60).merge('until' => 1.minute.ago.iso8601)
    character.update!(effects: [described_class.entry(title, 60), ended, described_class.entry(effect, 10, permanent: true)].map { |entry| entry.merge('kind' => 'fx') })

    wearing = described_class.wearing(character)

    expect(wearing.pluck(:slot)).to eq %w(title skin)
    expect(wearing.first).to include(preset: 'gold', name: '금빛 칭호', permanent: false)
    expect(wearing.last[:permanent]).to be true
  end
end
