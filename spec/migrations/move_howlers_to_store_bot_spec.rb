# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('db/migrate/20261027000200_move_howlers_to_store_bot')

# 호울러를 올리는 계정이 시스템에서 상점 봇으로 바뀌었다: 예전에 시스템 계정이 올린 호울러만 봇 계정으로 옮긴다
RSpec.describe MoveHowlersToStoreBot do
  let(:system) { Fabricate(:user, account: Fabricate(:account, username: 'system')).account }
  let!(:store) { Fabricate(:user, account: Fabricate(:account, username: 'store')).account }
  let(:ron) { Fabricate(:user, account: Fabricate(:account, username: 'ron')).account }

  before do
    allow(Game::System).to receive(:account).and_return(system)
    Game::Config.update!('common', 'bot_usernames' => 'store')
    GameShop.create!(name: '가게').items.create!(name: '호울러', price: 1, item_effects: [{ type: 'special', kind: 'rumor', text: '연회장에 호울러가 울린다' }])
  end

  it 'moves the howler toots and DMs the system account sent to the store bot, and leaves everything else alone' do
    hall = Fabricate(:status, account: system, text: '연회장에 호울러가 울린다', visibility: :private)
    rumor = Fabricate(:status, account: system, text: "연회장에 호울러가 울린다\n\n교장실 앞에 용이 나타났다", visibility: :direct)
    Mention.create!(status: rumor, account: ron)
    notification = Notification.create!(account: ron, from_account: system, type: :mention, activity: rumor.mentions.first)
    game_toot = Fabricate(:status, account: system, text: '@ron 1라운드', visibility: :private)
    other_dm = Fabricate(:status, account: system, text: '연회장에 호울러가 울린다 (다른 글)', visibility: :direct)
    human = Fabricate(:status, account: ron, text: '연회장에 호울러가 울린다', visibility: :private)

    described_class.new.up

    expect([hall, rumor].map { |status| status.reload.account_id }).to all(eq(store.id))
    expect(notification.reload.from_account_id).to eq store.id
    expect([game_toot, other_dm].map { |status| status.reload.account_id }).to all(eq(system.id))
    expect(human.reload.account_id).to eq ron.id
  end

  it 'does nothing without a store bot account' do
    Game::Config.update!('common', 'bot_usernames' => '')
    hall = Fabricate(:status, account: system, text: '연회장에 호울러가 울린다', visibility: :private)

    described_class.new.up

    expect(hall.reload.account_id).to eq system.id
  end
end
