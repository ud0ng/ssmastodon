# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Admin character roster' do
  before do
    sign_in Fabricate(:admin_user)
    GameCharacterField.ensure_defaults!
    GameHouse.ensure_defaults!
  end

  let(:order) { GameHouse.factions.find_by(name: '불사조 기사단') }
  let(:eaters) { GameHouse.factions.find_by(name: '죽음을 먹는 자들') }
  let(:character) { GameCharacter.for(Fabricate(:account)) }

  it 'saves faction, stats, money and inventory rows from the detail page' do
    patch admin_game_character_path(character), params: {
      game_character: {
        name: '해리',
        money: 120,
        game_faction_id: order.id,
        stat_values: { '힘' => '150', '민첩' => '', '체력' => '9', '없는 스탯' => '4' },
        inventory: [{ name: '투명 망토', count: '1', note: '아버지 유품' }, { name: '', count: '3', note: '' }, { name: '초콜릿 개구리', count: '0', note: '' }],
      },
    }

    expect(response).to redirect_to(edit_admin_game_character_path(character))
    expect(character.reload).to have_attributes(
      name: '해리',
      money: 120,
      faction: order,
      stats: { '힘' => '100' },
      inventory: [{ 'name' => '투명 망토', 'count' => 1, 'note' => '아버지 유품' }, { 'name' => '초콜릿 개구리', 'count' => 1, 'note' => '' }]
    )
  end

  it 'empties the inventory when every row is removed' do
    character.update!(inventory: [{ 'name' => '사과', 'count' => 1, 'note' => '' }])

    patch admin_game_character_path(character), params: { game_character: { name: '' } }

    expect(character.reload.inventory).to eq []
  end

  it 'sets a faction for several characters at once and clears it again' do
    other = GameCharacter.for(Fabricate(:account))

    patch bulk_admin_game_characters_path, params: { ids: [character.id, other.id], target: "faction:#{eaters.id}" }
    expect([character, other].map { |item| item.reload.faction }).to eq [eaters] * 2

    patch bulk_admin_game_characters_path, params: { ids: [character.id], target: 'faction:none' }
    expect(character.reload.faction).to be_nil
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
    post admin_game_houses_path, params: { game_house: { name: '중립', color: '#888888', category: 'faction' } }

    expect(GameHouse.factions.pluck(:name)).to include('중립')
  end

  it 'moves stat values and formulas when a stat is renamed' do
    character.update!(stats: { '힘' => '7' })
    field = GameCharacterField.find_by(name: '힘')

    patch admin_game_character_stat_path(field), params: { game_character_field: { name: '근력', stat_type: 'stat', min_value: 0, max_value: 100 } }

    expect(character.reload.stats).to eq('근력' => '7')
    expect(GameCharacterField.find_by(name: '체력').formula).to eq '{{근력}}*5'
  end

  it 'adds a status value with a formula and refuses a bad one' do
    post admin_game_character_stats_path, params: { game_character_field: { name: '마력', stat_type: 'status', formula: '{{힘}}5+{{민첩}}' } }
    expect(GameCharacterField.find_by(name: '마력')).to have_attributes(stat_type: 'status', formula: '{{힘}}5+{{민첩}}', min_value: nil)

    post admin_game_character_stats_path, params: { game_character_field: { name: '운', stat_type: 'status', formula: '{{없음}}*2' } }
    expect(GameCharacterField.find_by(name: '운')).to be_nil
  end

  it 'does not delete a stat that a formula uses' do
    field = GameCharacterField.find_by(name: '힘')

    delete admin_game_character_stat_path(field)

    expect(GameCharacterField.find_by(name: '힘')).to be_present
    expect(flash[:alert]).to include('체력')
  end

  it 'keeps the roster in step with the member list (suspended members are hidden, not deleted)' do
    suspended = Fabricate(:user).account
    GameCharacter.for(suspended).update!(money: 30)
    suspended.update!(suspended_at: Time.now.utc)
    gone = Fabricate(:user)
    GameCharacter.for(gone.account)
    gone.destroy!
    newcomer = Fabricate(:user).account

    GameCharacter.sync!

    expect(GameCharacter.find_by(account: suspended)).to have_attributes(money: 30)
    expect(GameCharacter.visible.find_by(account: suspended)).to be_nil
    expect(GameCharacter.find_by(account: gone.account)).to be_nil
    expect(GameCharacter.visible.find_by(account: newcomer)).to be_present
  end

  it 'queues a roster sync when members join, leave or get suspended' do
    expect { Fabricate(:user) }.to change(Game::RosterSyncWorker.jobs, :size)
    account = Fabricate(:user).account
    expect { account.update!(suspended_at: Time.now.utc) }.to change(Game::RosterSyncWorker.jobs, :size).by(1)
    expect { account.update!(note: 'hello') }.to_not change(Game::RosterSyncWorker.jobs, :size)
    expect { account.user.destroy! }.to change(Game::RosterSyncWorker.jobs, :size)
  end

  it 'redirects the old houses address' do
    get '/admin/games/houses'

    expect(response).to redirect_to('/admin/characters/houses')
  end
end
