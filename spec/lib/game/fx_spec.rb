# frozen_string_literal: true

require 'rails_helper'

# 효과: 스킨 자리·영구·목록 안 효과 고치기/지우기 (관리 화면 캐릭터 상세·소속)
RSpec.describe Game::Fx do
  let(:effect) { GameEffect.create!(kind: 'character', slot: 'skin', preset: 'debut', name: '데뷔탕트 스킨') }

  it 'has a skin slot for characters and a debut look' do
    expect(described_class::SLOTS['character']).to include('skin')
    expect(described_class::PRESETS['skin']).to include('debut')
    expect(described_class::PRESETS['title']).to include('debut')
    expect(described_class::PRESETS['deco']).to include('debut')
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
end
