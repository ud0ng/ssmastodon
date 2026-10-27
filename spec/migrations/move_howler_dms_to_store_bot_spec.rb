# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('db/migrate/20261027000300_move_howler_dms_to_store_bot')

# 시스템이 올린 DM 은 맨 앞에 받는 사람 태그 줄이 붙는다: 그 줄을 빼고 호울러 문구로 시작하는 DM 만 봇 계정으로 옮긴다
RSpec.describe MoveHowlerDmsToStoreBot do
  let!(:system) { Fabricate(:user, account: Fabricate(:account, username: 'system')).account }
  let!(:store) { Fabricate(:user, account: Fabricate(:account, username: 'store')).account }
  let!(:ron) { Fabricate(:user, account: Fabricate(:account, username: 'ron')).account }
  let!(:harry) { Fabricate(:user, account: Fabricate(:account, username: 'harry')).account }

  before do
    allow(Game::System).to receive(:account).and_return(system)
    Game::Config.update!('common', 'bot_usernames' => 'store')
    GameShop.create!(name: '가게').items.create!(name: '호울러', price: 1, item_effects: [{ type: 'special', kind: 'rumor', text: '연회장에 호울러가 울린다' }])
  end

  def dm(text, to:, from: system)
    status = Fabricate(:status, account: from, text: text, visibility: :direct)
    Mention.create!(status: status, account: to)
    status
  end

  it 'moves the howler DMs that start with the tag line and keeps game DMs and look-alikes on the system account' do
    rumor = dm("@ron\n연회장에 호울러가 울린다\n\n교장실 앞에 용이 나타났다", to: ron)
    plain = dm("@harry\n연회장에 호울러가 울린다", to: harry)
    game = dm("@ron\n1라운드 선택 안내", to: ron)
    lookalike = dm("@ron\n연회장에 호울러가 울린다고 합니다", to: ron)
    mentioned_notification = Notification.create!(account: ron, from_account: system, type: :mention, activity: rumor.mentions.first)

    described_class.new.up

    expect([rumor, plain].map { |status| status.reload.account_id }).to all(eq(store.id))
    expect([game, lookalike].map { |status| status.reload.account_id }).to all(eq(system.id))
    expect(mentioned_notification.reload.from_account_id).to eq store.id
    expect(DmRoom.find_by(participant_key: DmRoom.participant_key_for([store.id, ron.id]))).to be_present
  end

  it 'does nothing without a store bot account' do
    Game::Config.update!('common', 'bot_usernames' => '')
    rumor = dm("@ron\n연회장에 호울러가 울린다\n\n소문", to: ron)

    described_class.new.up

    expect(rumor.reload.account_id).to eq system.id
  end
end
