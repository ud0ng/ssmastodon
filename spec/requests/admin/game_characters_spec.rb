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

  it 'changes the house and faction right from the roster table' do
    house = GameHouse.houses.first

    patch group_admin_game_character_path(character), params: { kind: 'house', value: house.id }
    expect(response).to have_http_status(204)
    expect(character.reload.house).to eq house

    patch group_admin_game_character_path(character), params: { kind: 'faction', value: order.id }
    expect(character.reload.faction).to eq order

    patch group_admin_game_character_path(character), params: { kind: 'house', value: '' }
    expect(character.reload.house).to be_nil

    patch group_admin_game_character_path(character), params: { kind: 'faction', value: '999999' }
    expect(response).to have_http_status(422)
    expect(character.reload.faction).to eq order
  end

  it 'takes staff accounts out of the roster and gives them back when removed from the list' do
    notice = Fabricate(:user, account: Fabricate(:account, username: 'notice')).account
    member = Fabricate(:user, account: Fabricate(:account, username: 'harry')).account
    notice_character = GameCharacter.for(notice).tap { |each| each.update!(money: 50) }
    GameCharacter.for(member)

    patch admin_game_staff_path, params: { usernames: ['', '@notice'] }

    expect(response).to redirect_to(admin_settings_registrations_path)
    expect(Game::Config.for('currency')['admin_usernames']).to eq %w(notice)
    expect(GameCharacter.exists?(notice_character.id)).to be false
    expect(GameCharacter.visible.map(&:account_id)).to include(member.id)
    expect(GameCharacter.eligible_accounts).not_to include(notice)

    patch admin_game_staff_path, params: { usernames: [''] }
    expect(GameCharacter.eligible_accounts).to include(notice)
    expect(GameCharacter.visible.map(&:account_id)).to include(notice.id)
  end

  it 'drops the character of a withdrawn (anonymized) member from the roster' do
    user = Fabricate(:user)
    kept = GameCharacter.for(user.account)
    gone_user = Fabricate(:user)
    gone = GameCharacter.for(gone_user.account)
    gone_user.account.update!(anonymized_at: Time.now.utc, display_name: '탈퇴한 사용자')

    GameCharacter.sync!

    expect(GameCharacter.exists?(kept.id)).to be true
    expect(GameCharacter.exists?(gone.id)).to be false
    expect(GameCharacter.visible).not_to include(gone)
  end

  it 'saves name, faction and stats from the detail page without touching money or the inventory' do
    character.update!(inventory: [{ 'name' => '사과', 'count' => 1, 'note' => '' }])

    patch admin_game_character_path(character), params: {
      game_character: {
        name: '해리',
        money: 120, # 상세 화면에서는 재화를 고치지 않는다 (활동 탭의 지급)
        game_faction_id: order.id,
        stat_values: { '힘' => '150', '민첩' => '', '체력' => '9', '없는 스탯' => '4' },
      },
    }

    expect(response).to redirect_to(edit_admin_game_character_path(character))
    expect(character.reload).to have_attributes(
      name: '해리', money: 0, faction: order, stats: { '힘' => '100' },
      inventory: [{ 'name' => '사과', 'count' => 1, 'note' => '' }]
    )
  end

  describe 'inventory cards' do
    before { character.update!(inventory: [{ 'name' => '투명 망토', 'count' => 1, 'note' => '' }]) }

    it 'adds an item, merging one with the same name' do
      post items_admin_game_character_path(character), params: { item: { name: '초콜릿 개구리', count: '3', note: '' } }
      post items_admin_game_character_path(character), params: { item: { name: '초콜릿개구리', count: '0', note: '반쯤 먹음' } }

      expect(character.reload.inventory).to eq [
        { 'name' => '투명 망토', 'count' => 1, 'note' => '' },
        { 'name' => '초콜릿 개구리', 'count' => 4, 'note' => '반쯤 먹음' },
      ]
    end

    it 'changes the count and note, keeping the name' do
      patch item_admin_game_character_path(character, index: 0), params: { original_name: '투명 망토', item: { name: '딴 이름', count: '2', note: '아버지 유품' } }

      expect(character.reload.inventory).to eq [{ 'name' => '투명 망토', 'count' => 2, 'note' => '아버지 유품' }]
    end

    it 'removes an item, but not one that moved meanwhile' do
      delete item_admin_game_character_path(character, index: 0), params: { original_name: '다른 아이템' }
      expect(character.reload.inventory.size).to eq 1
      expect(flash[:alert]).to be_present

      delete item_admin_game_character_path(character, index: 0), params: { original_name: '투명 망토' }
      expect(character.reload.inventory).to eq []
    end
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

  it 'renames houses and factions from the groups tab' do
    patch labels_admin_game_houses_path, params: { labels: { house: '반', faction: '' } }

    expect(Game::Config.for('common')).to include('house_label' => '반', 'faction_label' => '진영')
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

  it 'edits and removes the title and deco effects of a character and the card effects of a house' do
    title = GameEffect.create!(kind: 'character', slot: 'title', preset: 'angel', name: '엔젤 칭호')
    card = GameEffect.create!(kind: 'house', slot: 'card', preset: 'gold', name: '블링블링')
    character.update!(effects: [Game::Fx.entry(title, 60).merge('kind' => 'fx')])
    house = GameHouse.houses.first
    house.update!(effects: [Game::Fx.entry(card, 60)])

    patch effect_admin_game_character_path(character, 0), params: { effect_id: title.id, until: 2.days.from_now.utc.strftime('%Y-%m-%dT%H:%M') }
    expect(Time.zone.parse(character.reload.effects.first['until'])).to be_within(2.minutes).of(2.days.from_now)

    patch effect_admin_game_character_path(character, 0), params: { effect_id: title.id, permanent: '1' }
    expect(Game::Fx.permanent?(character.reload.effects.first)).to be true

    patch effect_admin_game_character_path(character, 0), params: { effect_id: title.id, until: 'abc' }
    expect(response).to redirect_to(edit_admin_game_character_path(character))
    expect(Game::Fx.permanent?(character.reload.effects.first)).to be true

    delete effect_admin_game_character_path(character, 0), params: { effect_id: title.id }
    expect(character.reload.effects).to eq []

    patch effect_admin_game_house_path(house, 0), params: { effect_id: card.id, permanent: '1' }
    expect(Game::Fx.permanent?(house.reload.effects.first)).to be true
    delete effect_admin_game_house_path(house, 0), params: { effect_id: card.id }
    expect(house.reload.effects).to eq []
  end

  it 'adds title, deco and skin effects to a character and a card effect to a house' do
    title = GameEffect.create!(kind: 'character', slot: 'title', preset: 'angel', name: '엔젤 칭호')
    skin = GameEffect.create!(kind: 'character', slot: 'skin', preset: 'debut', name: '데뷔탕트 스킨')
    card = GameEffect.create!(kind: 'house', slot: 'card', preset: 'gold', name: '블링블링')
    house = GameHouse.houses.first

    post add_effect_admin_game_character_path(character), params: { effect_id: title.id, minutes: 2, unit: 'hour' }
    post add_effect_admin_game_character_path(character), params: { effect_id: skin.id, unit: 'forever' }
    effects = character.reload.fx_entries.map(&:last)
    expect(effects.pluck('slot')).to eq %w(title skin)
    expect(Game::Fx.permanent?(effects.first)).to be false
    expect(Game::Fx.permanent?(effects.last)).to be true

    post add_effect_admin_game_character_path(character), params: { effect_id: card.id, minutes: 1, unit: 'day' }
    expect(character.reload.fx_entries.size).to eq 2

    post add_effect_admin_game_house_path(house), params: { effect_id: card.id, minutes: 1, unit: 'day' }
    post add_effect_admin_game_house_path(house), params: { effect_id: title.id, minutes: 1, unit: 'day' }
    expect(house.reload.fx_entries.size).to eq 1
  end

  it 'redirects the old houses address' do
    get '/admin/games/houses'

    expect(response).to redirect_to('/admin/characters/houses')
  end
end
