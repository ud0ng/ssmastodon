# frozen_string_literal: true

require 'rails_helper'

# 캐릭터 관리 > 활동: 지급 (화면을 그리는 index/show 는 Vite 빌드가 필요해서 미리보기로 확인)
RSpec.describe 'Admin character activity' do
  before do
    sign_in Fabricate(:admin_user)
    GameCharacterField.ensure_defaults!
    shop = GameShop.create!(name: '허니듀크')
    shop.items.create!(name: '초콜릿 개구리', price: 2)
    shop.items.create!(name: '버티 보트 젤리빈', price: 1)
  end

  let(:harry) { GameCharacter.for(Fabricate(:user).account).tap { |character| character.update!(money: 5) } }
  let(:ron) { GameCharacter.for(Fabricate(:user).account) }

  it 'gives currency to the chosen characters and records it' do
    post give_admin_game_activities_path, params: { give_kind: 'money', character_ids: [harry.id, ron.id], money: '10', reason: '생일' }

    expect([harry.reload.money, ron.reload.money]).to eq [15, 10]
    expect(GameReward.where(kind: 'admin', reason: '생일').count).to eq 2
  end

  it 'tells each receiver by its own DM from the system account what was given' do
    system = Fabricate(:account, username: 'system')
    allow(Game::System).to receive(:account).and_return(system)
    items = [{ name: '초콜릿 개구리', count: '2' }]

    post give_admin_game_activities_path, params: { give_kind: 'money', character_ids: [harry.id, ron.id], money: '10' }
    post give_admin_game_activities_path, params: { give_kind: 'items', character_ids: [ron.id], items: items }

    dms = Status.where(account: system, visibility: :direct).reorder(:id).to_a
    expect(dms.size).to eq 3
    expect(dms.first(2).map { |status| status.mentions.map(&:account_id) }).to match_array([[harry.account_id], [ron.account_id]]) # 한 명씩 따로
    expect(dms[2].mentions.map(&:account_id)).to eq [ron.account_id]
    expect(dms[0].text).to include('10', '지급되었습니다. 인벤토리를 확인해보세요!')
    expect(dms[2].text).to include('초콜릿 개구리 ×2')
  end

  it 'gives several shop items at once, each with its own count' do
    items = [{ name: '초콜릿 개구리', count: '2' }, { name: '버티 보트 젤리빈', count: '5' }, { name: '없는 아이템', count: '1' }, { name: '초콜릿 개구리', count: '1' }]
    post give_admin_game_activities_path, params: { give_kind: 'items', character_ids: [ron.id], items: items, money: '99' }

    expect(ron.reload.inventory.pluck('name', 'count')).to eq [['초콜릿 개구리', 3], ['버티 보트 젤리빈', 5]]
    expect(ron.money).to eq 0
  end

  it 'goes back to the shop tab when given from there, but never to another site' do
    post give_admin_game_activities_path, params: { give_kind: 'money', character_ids: [harry.id], money: '1', return_to: admin_game_shops_path }
    expect(response).to redirect_to(admin_game_shops_path)

    post give_admin_game_activities_path, params: { give_kind: 'money', character_ids: [harry.id], money: '1', return_to: '//evil.example/admin/' }
    expect(response).to redirect_to(admin_game_activities_path)
  end

  it 'gives nothing without a target or anything to give' do
    post give_admin_game_activities_path, params: { give_kind: 'money', character_ids: [harry.id], money: '0' }

    expect(response).to redirect_to(admin_game_activities_path(modal: 'activity-give'))
    expect(harry.reload.money).to eq 5
  end
end

# 캐릭터 관리 > 소속 > 시즌
RSpec.describe 'Admin seasons' do
  before { sign_in Fabricate(:admin_user) }

  let!(:system) { Fabricate(:account, username: 'system') }

  it 'creates one running season at a time, posts results and ends it' do
    post admin_game_seasons_path, params: { game_season: { name: '1학기', starts_on: '2026-10-01', ends_on: '2026-11-30' } }
    post admin_game_seasons_path, params: { game_season: { name: '2학기' } }
    season = GameSeason.sole
    expect(season).to have_attributes(name: '1학기', starts_on: Date.new(2026, 10, 1))

    expect { post interim_admin_game_season_path(season) }.to change { Status.where(account: system).count }.by(1)
    post finish_admin_game_season_path(season)
    expect(season.reload).to have_attributes(status: 'finished')

    post admin_game_seasons_path, params: { game_season: { name: '2학기' } }
    expect(GameSeason.running.pluck(:name)).to eq ['2학기']
  end

  it 'saves the season messages and the scoring mode' do
    patch messages_admin_game_seasons_path, params: { config: { msg_season_interim: '{시즌} 중간!', msg_house_label: 'x' } }
    post scoring_admin_game_houses_path, params: { scoring_mode: 'games' }

    expect(Game::Config.for('common')).to include('msg_season_interim' => '{시즌} 중간!', 'scoring_mode' => 'games')
  end

  it 'refuses an end date before the start date' do
    post admin_game_seasons_path, params: { game_season: { name: '1학기', starts_on: '2026-10-10', ends_on: '2026-10-01' } }

    expect(GameSeason.count).to eq 0
  end
end

# 컨텐츠 설정 > 설정 / 명령어: 같은 공통 설정을 두 화면에서 나눠 저장
RSpec.describe 'Admin content settings pages' do
  before { sign_in Fabricate(:admin_user) }

  it 'saves each page without touching the other' do
    patch admin_game_setting_path('common'), params: { config: { system_username: '@시스템', turn_seconds: '45', toot_reward_basis: 'chars' } }
    patch admin_game_setting_path('commands'), params: { config: { cmd_accept: '좋아' } }

    expect(response).to redirect_to(admin_game_setting_path('commands'))
    expect(Game::Config.for('common')).to include('system_username' => '시스템', 'turn_seconds' => 45, 'toot_reward_basis' => 'chars', 'cmd_accept' => '좋아')
    expect(Game::Config.turn_time).to eq(seconds: 45, minutes: 1)
  end
end
