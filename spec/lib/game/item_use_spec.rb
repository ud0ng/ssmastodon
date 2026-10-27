# frozen_string_literal: true

require 'rails_helper'

# 소문내기 아이템(호울러): 아이템에 정한 문구는 시스템 계정 팔로워 공개 툿으로, 사용자가 쓴 소문은 모든 캐릭터에게 DM 으로
RSpec.describe Game::ItemUse do
  let!(:system) { Fabricate(:account, username: 'system') }
  let!(:harry) { Fabricate(:account, username: 'harry') }
  let!(:ron) { Fabricate(:account, username: 'ron') }
  let!(:store) { Fabricate(:account, username: 'store') }
  let!(:howler) { GameShop.create!(name: '가게').items.create!(name: '호울러', price: 1, item_effects: [{ type: 'special', kind: 'rumor', text: '연회장에 호울러가 울린다' }]) }

  before do
    allow(Game::System).to receive(:account).and_return(system)
    GameCharacter.for(ron)
    Game::Config.update!('common', 'bot_usernames' => 'store')
    Game::Wallet.apply!([{ account: harry, items: { '호울러' => 1 } }], kind: 'admin')
  end

  def dm(text)
    status = PostStatusService.new.call(harry, text: "@system #{text}", visibility: 'direct')
    Game::Engine.new(status).call
  end

  it 'posts the hall text as a followers-only toot, spreads the rumor to everyone by DM and uses up one item' do
    dm('[사용/호울러/교장실 앞에 용이 나타났다]')

    expect(GameCharacter.for(harry).reload.inventory).to eq []
    hall = store.statuses.reorder(:id).to_a.find { |status| status.text.include?('연회장에 호울러가 울린다') }
    expect(hall).to have_attributes(visibility: 'private')
    expect(hall.mentions).to be_empty
    rumor = store.statuses.reorder(:id).to_a.find { |status| status.text.include?('용이 나타났다') && status.mentions.any? { |mention| mention.account_id == ron.id } }
    expect(rumor).to be_present
    expect(rumor).to have_attributes(visibility: 'direct')
    expect(rumor.text).to include("연회장에 호울러가 울린다\n\n교장실 앞에 용이 나타났다")
    expect(system.statuses.where(id: [hall.id, rumor.id])).to be_empty # 시스템 계정이 아니라 상점 봇 계정이 올린다
  end

  it 'asks for the text and for an item that is owned' do
    dm('[사용/호울러]')
    expect(system.statuses.reorder(:id).last.text).to include('소문 내용')
    expect(GameCharacter.for(harry).reload.inventory.pluck('count')).to eq [1]

    dm('[사용/호울러/첫 소문]')
    dm('[사용/호울러/또 소문]')
    expect(system.statuses.reorder(:id).last.text).to include('가지고 있지 않습니다')
  end

  it 'leaves other items to the shop bot' do
    dm('[사용/사과]')

    expect(system.statuses.count).to eq 0
  end
end
