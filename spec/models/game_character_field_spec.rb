# frozen_string_literal: true

require 'rails_helper'

RSpec.describe GameCharacterField do
  it 'creates the default stats once' do
    described_class.ensure_defaults!
    described_class.ensure_defaults!

    expect(described_class.base_stats.pluck(:name)).to eq %w(힘 민첩)
    expect(described_class.statuses.pluck(:name)).to eq %w(체력)
  end

  describe 'status values' do
    before { described_class.ensure_defaults! }

    it 'needs a formula that only uses existing stats' do
      expect(described_class.new(name: '마력', section: 'stat', stat_type: 'status', formula: '')).to_not be_valid
      expect(described_class.new(name: '마력', section: 'stat', stat_type: 'status', formula: '{{지능}}*2')).to_not be_valid
      expect(described_class.new(name: '마력', section: 'stat', stat_type: 'status', formula: '{{힘}}**')).to_not be_valid
      expect(described_class.new(name: '마력', section: 'stat', stat_type: 'status', formula: '({{힘}}+{{민첩}})/2')).to be_valid
    end

    it 'rejects a max that is below the min' do
      expect(described_class.new(name: '운', section: 'stat', stat_type: 'stat', min_value: 5, max_value: 1)).to_not be_valid
    end

    it 'calculates a character status from its stats (clamped to the stat range)' do
      character = GameCharacter.for(Fabricate(:account))
      character.update!(stats: { '힘' => '10', '민첩' => '4' })
      health = described_class.find_by(name: '체력')

      expect(character.status_value(health)).to eq 50
      character.update!(stats: { '힘' => '500' })
      expect(character.stat_value(described_class.find_by(name: '힘'))).to eq 100
      expect(character.status_value(health)).to eq 500
    end
  end

  it 'creates the default stats even when old profile fields are left over' do
    described_class.unscoped.delete_all
    described_class.create!(name: '혈통', kind: 'select', section: 'profile')

    described_class.ensure_defaults!

    expect(described_class.base_stats.pluck(:name)).to eq %w(힘 민첩)
  end
end

RSpec.describe GameCharacter do
  let(:character) { described_class.for(Fabricate(:account)) }

  it 'reads the inventory from name|count|note lines' do
    character.inventory_text = "투명 망토|1|아버지 유품\n초콜릿 개구리|3\n|2"

    expect(character.inventory).to eq [
      { 'name' => '투명 망토', 'count' => 1, 'note' => '아버지 유품' },
      { 'name' => '초콜릿 개구리', 'count' => 3, 'note' => '' },
    ]
    expect(character.item_count).to eq 4
    expect(character.inventory_text).to eq "투명 망토|1|아버지 유품\n초콜릿 개구리|3"
  end
end
