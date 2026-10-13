# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Admin character roster' do
  before do
    sign_in Fabricate(:admin_user)
    GameCharacterField.ensure_defaults!
    GameHouse.ensure_defaults!
  end

  let(:blood) { GameCharacterField.create!(name: '혈통', kind: 'select', section: 'profile', choices: [{ 'name' => '순수혈통', 'color' => '' }, { 'name' => '혼혈', 'color' => '' }]) }
  let(:order) { GameHouse.factions.find_by(name: '불사조 기사단') }
  let(:eaters) { GameHouse.factions.find_by(name: '죽음을 먹는 자들') }
  let(:character) { GameCharacter.for(Fabricate(:account)) }

  it 'saves faction, profile fields, combat stats, money and inventory' do
    patch admin_game_character_path(character), params: {
      game_character: {
        name: '해리',
        money: 120,
        game_faction_id: order.id,
        profile: { blood.id.to_s => '혼혈', '999' => 'x' },
        stat_values: { '체력' => '10', '공격' => '', '방어' => '3' },
        extra_stats_text: "행운=2\n체력=1",
        inventory_text: '투명 망토|1|',
      },
    }

    expect(response).to redirect_to(admin_game_characters_path)
    expect(character.reload).to have_attributes(
      name: '해리',
      money: 120,
      faction: order,
      profile: { blood.id.to_s => '혼혈' },
      stats: { '행운' => '2', '체력' => '10', '방어' => '3' },
      inventory: [{ 'name' => '투명 망토', 'count' => 1, 'note' => '' }]
    )
  end

  it 'ignores a choice that is not in the list' do
    patch admin_game_character_path(character), params: { game_character: { profile: { blood.id.to_s => '없는 값' } } }

    expect(character.reload.profile).to eq({})
  end

  it 'sets a faction for several characters at once and clears it again' do
    other = GameCharacter.for(Fabricate(:account))

    patch bulk_admin_game_characters_path, params: { ids: [character.id, other.id], target: "faction:#{eaters.id}" }
    expect([character, other].map { |item| item.reload.faction }).to eq [eaters] * 2

    patch bulk_admin_game_characters_path, params: { ids: [character.id], target: 'faction:none' }
    expect(character.reload.faction).to be_nil
  end

  it 'sets a select field for several characters at once' do
    patch bulk_admin_game_characters_path, params: { ids: [character.id], target: "field:#{blood.id}:순수혈통" }

    expect(character.reload.profile).to eq(blood.id.to_s => '순수혈통')
  end

  it 'switches the scoring unit to factions without touching house points' do
    gryffindor = GameHouse.houses.first
    character.update!(house: gryffindor, faction: order)
    GameHousePoint.create!(house: gryffindor, amount: 30, reason: 'test')

    post mode_admin_game_houses_path, params: { mode: 'faction' }

    expect(GameHouse.mode).to eq 'faction'
    expect(GameHouse.active).to eq [order, eaters]
    expect(character.reload.group).to eq order
    expect(gryffindor.total).to eq 30
    expect(Game::Config.for('common')['house_term']).to eq '진영'
  end

  it 'adds a faction from the groups tab' do
    post admin_game_houses_path, params: { game_house: { name: '중립', emoji: '⚖️', color: '#888888', category: 'faction' } }

    expect(GameHouse.factions.pluck(:name)).to include('중립')
  end

  it 'moves stat values when a stat field is renamed' do
    character.update!(stats: { '체력' => '7' })
    field = GameCharacterField.find_by(name: '체력')

    patch admin_game_character_field_path(field), params: { game_character_field: { name: 'HP' } }

    expect(character.reload.stats).to eq('HP' => '7')
  end

  it 'adds a select field with choices' do
    post admin_game_character_fields_path, params: { game_character_field: { name: '지팡이', kind: 'select', section: 'profile', choices_text: "딱총나무|#ffffff\n호랑가시나무" } }

    expect(GameCharacterField.find_by(name: '지팡이').choices.pluck('name')).to eq %w(딱총나무 호랑가시나무)
  end

  it 'redirects the old houses address' do
    get '/admin/games/houses'

    expect(response).to redirect_to('/admin/characters/houses')
  end
end
