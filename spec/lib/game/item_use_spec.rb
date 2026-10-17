# frozen_string_literal: true

require 'rails_helper'

# 호울러: 모바일에서는 시스템 계정에 DM 으로 [사용/호울러/내용]
RSpec.describe Game::ItemUse do
  let!(:system) { Fabricate(:account, username: 'system') }
  let!(:harry) { Fabricate(:account, username: 'harry') }
  let!(:ron) { Fabricate(:account, username: 'ron') }
  let!(:howler) { GameShop.create!(name: '가게').items.create!(name: '호울러', price: 1, use_target: 'special', special_kind: 'howler') }

  before do
    allow(Game::System).to receive(:account).and_return(system)
    GameCharacter.for(ron)
    Game::Wallet.apply!([{ account: harry, items: { '호울러' => 1 } }], kind: 'admin')
  end

  def dm(text)
    status = PostStatusService.new.call(harry, text: "@system #{text}", visibility: 'direct')
    Game::Engine.new(status).call
  end

  it 'spreads the rumor to everyone and uses up one item' do
    dm('[사용/호울러/교장실 앞에 용이 나타났다]')

    expect(GameCharacter.for(harry).reload.inventory).to eq []
    rumor = system.statuses.reorder(:id).to_a.find { |status| status.text.include?('용이 나타났다') && status.mentions.any? { |mention| mention.account_id == ron.id } }
    expect(rumor).to be_present
    expect(rumor).to have_attributes(visibility: 'direct')
  end

  it 'asks for the text and for an item that is owned' do
    dm('[사용/호울러]')
    expect(system.statuses.reorder(:id).last.text).to include('소문 내용')
    expect(GameCharacter.for(harry).reload.inventory.pluck('count')).to eq [1]

    dm('[사용/호울러/첫 소문]')
    dm('[사용/호울러/또 소문]')
    expect(system.statuses.reorder(:id).last.text).to include('부족')
  end

  it 'leaves other items to the shop bot' do
    dm('[사용/사과]')

    expect(system.statuses.count).to eq 0
  end
end
