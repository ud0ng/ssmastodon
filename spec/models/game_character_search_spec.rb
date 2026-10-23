# frozen_string_literal: true

require 'rails_helper'

# [사용/아이템/@상대] 의 상대: 계정 아이디 또는 캐릭터 이름 (이름은 앞부분만 써도 된다, 여럿이면 다시 물어본다)
RSpec.describe GameCharacter, '.search' do
  def character(username, name)
    described_class.for(Fabricate(:user, account: Fabricate(:account, username: username)).account).tap { |each| each.update!(name: name) }
  end

  let!(:abcd) { character('abcd_user', '에이비 시디') }
  let!(:other) { character('other', '엘레나') }
  let!(:twin_a) { character('twin_a', '쌍둥이 가') }
  let!(:twin_b) { character('twin_b', '쌍둥이 나') }

  it 'finds by account name or by the first part of the character name, ignoring spaces and a leading @' do
    expect(described_class.search('@abcd_user')).to eq [abcd]
    expect(described_class.search('에이비')).to eq [abcd]
    expect(described_class.search('@에이비시디')).to eq [abcd]
    expect(described_class.search('비 시')).to eq [abcd] # 이름 안에 들어 있는 말
    expect(described_class.search('없는사람')).to be_empty
  end

  it 'returns every match when more than one fits, and prefers an exact one' do
    expect(described_class.search('쌍둥이')).to contain_exactly(twin_a, twin_b)
    expect(described_class.search('쌍둥이 가')).to eq [twin_a]
  end

  it 'asks again from the item use when the name is not enough' do
    GameCharacterField.ensure_defaults!
    account = Fabricate(:user, account: Fabricate(:account, username: 'me_user')).account
    shop_item = GameShop.create!(name: '가게').items.create!(name: '부적', price: 1, item_effects: [{ type: 'stat', stat: GameCharacterField.base_stats.first.name, value: '1', target: 'character' }])
    Game::Wallet.apply!([{ account: account, items: { '부적' => 2 } }], kind: 'admin')

    expect { Game::ItemUse::Runner.from_args(account, shop_item.name, ['쌍둥이'], via: :bot).call }.to raise_error(Game::ItemUse::Error, /여럿/)
    expect(Game::ItemUse::Runner.from_args(account, shop_item.name, ['에이비'], via: :bot).instance_variable_get(:@target_query)).to eq '에이비'
  end
end
