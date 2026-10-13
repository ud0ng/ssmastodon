# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Admin character roster' do
  before do
    sign_in Fabricate(:admin_user)
    GameCharacterField.ensure_defaults!
  end

  let(:faction) { GameCharacterField.find_by(name: '진영') }
  let(:character) { GameCharacter.for(Fabricate(:account)) }

  it 'saves profile fields, combat stats, money and inventory' do
    patch admin_game_character_path(character), params: {
      game_character: {
        name: '해리',
        money: 120,
        profile: { faction.id.to_s => '불사조 기사단', '999' => 'x' },
        stat_values: { '체력' => '10', '공격' => '', '방어' => '3' },
        extra_stats_text: "행운=2\n체력=1",
        inventory_text: '투명 망토|1|',
      },
    }

    expect(response).to redirect_to(admin_game_characters_path)
    expect(character.reload).to have_attributes(
      name: '해리',
      money: 120,
      profile: { faction.id.to_s => '불사조 기사단' },
      stats: { '행운' => '2', '체력' => '10', '방어' => '3' },
      inventory: [{ 'name' => '투명 망토', 'count' => 1, 'note' => '' }]
    )
  end

  it 'ignores a choice that is not in the list' do
    patch admin_game_character_path(character), params: { game_character: { profile: { faction.id.to_s => '없는 진영' } } }

    expect(character.reload.profile).to eq({})
  end

  it 'sets a faction for several characters at once and clears it again' do
    other = GameCharacter.for(Fabricate(:account))

    patch bulk_admin_game_characters_path, params: { ids: [character.id, other.id], target: "field:#{faction.id}:죽음을 먹는 자들" }
    expect([character, other].map { |item| item.reload.profile[faction.id.to_s] }).to eq ['죽음을 먹는 자들'] * 2

    patch bulk_admin_game_characters_path, params: { ids: [character.id], target: "field:#{faction.id}:" }
    expect(character.reload.profile).to eq({})
  end

  it 'moves stat values when a stat field is renamed' do
    character.update!(stats: { '체력' => '7' })
    field = GameCharacterField.find_by(name: '체력')

    patch admin_game_character_field_path(field), params: { game_character_field: { name: 'HP' } }

    expect(character.reload.stats).to eq('HP' => '7')
  end

  it 'adds a select field with choices' do
    post admin_game_character_fields_path, params: { game_character_field: { name: '혈통', kind: 'select', section: 'profile', choices_text: "순수혈통|#ffffff\n혼혈" } }

    expect(GameCharacterField.find_by(name: '혈통').choices.pluck('name')).to eq %w(순수혈통 혼혈)
  end

  it 'redirects the old houses address' do
    get '/admin/games/houses'

    expect(response).to redirect_to('/admin/characters/houses')
  end
end
