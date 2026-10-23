# frozen_string_literal: true

require 'rails_helper'

# 마니또: A가 B를 태그한 툿에 B에게 정해진 단어를 쓰면 보상, B가 맞히면 A의 B 관련 보상을 빼앗는다
RSpec.describe Game::Manito do
  let(:shop) { Fabricate(:user, account: Fabricate(:account, username: 'shop')).account }
  let(:a) { Fabricate(:user, account: Fabricate(:account, username: 'harry')).account }
  let(:b) { Fabricate(:user, account: Fabricate(:account, username: 'draco')).account }
  let(:c) { Fabricate(:user, account: Fabricate(:account, username: 'luna')).account }

  before do
    Game::Config.update!('common', 'bot_usernames' => shop.username)
    Game::Config.update!('manito', 'manito_enabled' => '1', 'manito_reward_money' => '3', 'manito_daily_limit' => '2', 'manito_guess_limit' => '2', 'manito_wrong_penalty' => '1')
    GameManitoWord.create!(account: a, target_account: b, words: %w(하지마))
    GameManitoWord.create!(account: a, target_account: c, words: %w(달빛))
  end

  def toot(text, from: a, to: [b], visibility: :private)
    status = Fabricate(:status, account: from, text: text, visibility: visibility)
    Array(to).each { |account| Mention.create!(status: status, account: account) }
    status.reload
  end

  def dms_to(account)
    Status.where(account: shop, visibility: :direct).reorder(:id).select { |status| status.mentions.any? { |mention| mention.account_id == account.id } }
  end

  it 'counts a toot tagging the target with the word once, rewards it and tells only the speaker by a DM from the shop bot' do
    described_class.record!(toot('@draco 하지마, 정말 하 지 마'))
    described_class.record!(toot('@draco 그냥 인사')) # 단어 없음
    described_class.record!(toot('하지마', to: [])) # 태그 없음
    described_class.record!(toot('@draco 하지마', visibility: :direct)) # DM 은 빼는 설정

    pair = GameManitoWord.find_by!(account: a, target_account: b)
    expect(pair.uses).to eq 1
    expect(GameCharacter.for(a).money).to eq 3
    dm = dms_to(a)
    expect(dm.size).to eq 1
    expect(dm.first.text).to include('하지마', '1회', '3')
    expect(dms_to(b)).to be_empty
  end

  it 'keeps counting past the daily reward limit without rewarding' do
    3.times { described_class.record!(toot('@draco 하지마')) }

    expect(GameManitoWord.find_by!(account: a, target_account: b).uses).to eq 3
    expect(GameCharacter.for(a).money).to eq 6 # 하루 2번까지만
    expect(dms_to(a).last.text).to include('모두 받았습니다')
  end

  it 'lets the target steal the rewards earned from them with a right guess, and stops only that pair' do
    described_class.record!(toot('@draco 하지마'))
    described_class.record!(toot('@luna 달빛', to: [c]))

    message = described_class.guess!(b, '하 지마', a)
    expect(message).to include('정답', '3')
    expect(GameCharacter.for(a).money).to eq 3 # 루나에게서 받은 것은 그대로
    expect(GameCharacter.for(b).money).to eq 3
    expect(GameManitoWord.find_by!(account: a, target_account: b)).to be_caught
    expect(dms_to(a).last.text).to include('들켰습니다')

    described_class.record!(toot('@draco 하지마'))
    expect(GameManitoWord.find_by!(account: a, target_account: b).uses).to eq 1 # 들킨 뒤로는 세지 않는다
    described_class.record!(toot('@luna 달빛', to: [c]))
    expect(GameManitoWord.find_by!(account: a, target_account: c).uses).to eq 2
  end

  it 'charges a penalty for a wrong guess, refuses without the money, and limits guesses a day' do
    GameCharacter.for(b).update!(money: 1)

    expect(described_class.guess!(b, '아무말', a)).to include('오답', '벌금 1')
    expect(GameCharacter.for(b).money).to eq 0
    expect(described_class.guess!(b, '아무말', a)).to include('필요합니다')

    GameCharacter.for(b).update!(money: 5)
    described_class.guess!(b, '아무말', a)
    expect(described_class.guess!(b, '하지마', a)).to include('더 추측할 수 없습니다') # 하루 2번
    expect(GameManitoLog.guesses.where(account: b).pluck(:kind)).to eq %w(wrong wrong)
  end

  it 'does nothing while switched off' do
    Game::Config.merge!('manito', 'manito_enabled' => '0')
    described_class.record!(toot('@draco 하지마'))

    expect(GameManitoWord.find_by!(account: a, target_account: b).uses).to eq 0
    expect { described_class.guess!(b, '하지마', a) }.to raise_error(described_class::Error)
  end
end
