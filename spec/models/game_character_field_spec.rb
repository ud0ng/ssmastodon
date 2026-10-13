# frozen_string_literal: true

require 'rails_helper'

RSpec.describe GameCharacterField do
  it 'creates the default fields once, including factions' do
    described_class.ensure_defaults!
    described_class.ensure_defaults!

    faction = described_class.find_by(name: '진영')
    expect(faction.choices.pluck('name')).to eq ['불사조 기사단', '죽음을 먹는 자들']
    expect(described_class.stats.pluck(:name)).to eq %w(체력 공격 방어)
  end

  it 'reads choices from name|colour lines and drops bad colours' do
    field = described_class.new(name: '혈통', kind: 'select')
    field.choices_text = "순수혈통|#123456\n혼혈|red\n\n머글 태생"

    expect(field.choices).to eq [
      { 'name' => '순수혈통', 'color' => '#123456' },
      { 'name' => '혼혈', 'color' => '' },
      { 'name' => '머글 태생', 'color' => '' },
    ]
    expect(field.choices_text).to eq "순수혈통|#123456\n혼혈\n머글 태생"
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

  it 'lists only the stats that are not set up as fields' do
    character.stats = { '체력' => '10', '행운' => '3' }

    expect(character.extra_stats_text(%w(체력))).to eq '행운=3'
  end
end
