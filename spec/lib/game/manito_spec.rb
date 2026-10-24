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

  # 상점봇이 이 사람을 태그해 올린 툿 (단어 툿에 단 팔로워 공개 답멘)
  def notes_to(account)
    Status.where(account: shop).reorder(:id).select { |status| status.mentions.any? { |mention| mention.account_id == account.id } }
  end

  it 'counts a toot tagging the target with the word once, rewards it and replies to that toot tagging both, with what was earned so far' do
    described_class.record!(toot('@draco 하지마, 정말 하 지 마'))
    described_class.record!(toot('@draco 그냥 인사')) # 단어 없음
    described_class.record!(toot('하지마', to: [])) # 태그 없음
    described_class.record!(toot('@draco 하지마', visibility: :direct)) # DM 은 빼는 설정

    pair = GameManitoWord.find_by!(account: a, target_account: b)
    expect(pair.uses).to eq 1
    expect(GameCharacter.for(a).money).to eq 3
    notes = notes_to(a)
    expect(notes.size).to eq 1
    expect(notes.first).to have_attributes(visibility: 'private', in_reply_to_id: GameManitoLog.uses.first.status_id)
    expect(notes.first.text).to include('하지마', '1회', '쌓인 보상 : 3')
    expect(notes_to(b)).to eq notes # 상대도 태그한다 (힌트)
  end

  it 'keeps counting past the daily reward limit without rewarding' do
    3.times { described_class.record!(toot('@draco 하지마')) }

    expect(GameManitoWord.find_by!(account: a, target_account: b).uses).to eq 3
    expect(GameCharacter.for(a).money).to eq 6 # 하루 2번까지만
    expect(notes_to(a).last.text).to include('모두 받았습니다', '쌓인 보상 : 6')
  end

  it 'lets the target steal the rewards earned from them with a right guess, and stops only that pair' do
    described_class.record!(toot('@draco 하지마'))
    described_class.record!(toot('@luna 달빛', to: [c]))

    message = described_class.guess!(b, '하 지마', a)
    expect(message).to include('정답', '3')
    expect(GameCharacter.for(a).money).to eq 3 # 루나에게서 받은 것은 그대로
    expect(GameCharacter.for(b).money).to eq 3
    expect(GameManitoWord.find_by!(account: a, target_account: b)).to be_caught
    expect(notes_to(a).last.text).to include('들켰습니다')
    expect(notes_to(a).last.in_reply_to_id).to eq GameManitoWord.find_by!(account: a, target_account: b).last_status_id

    described_class.record!(toot('@draco 하지마'))
    expect(GameManitoWord.find_by!(account: a, target_account: b).uses).to eq 1 # 들킨 뒤로는 세지 않는다
    described_class.record!(toot('@luna 달빛', to: [c]))
    expect(GameManitoWord.find_by!(account: a, target_account: c).uses).to eq 2
  end

  it 'moves everything earned from the guesser even if spent: money goes below zero, items are given anew, and names the guessed word' do
    GameManitoWord.find_by!(account: a, target_account: b).update!(words: %w(하지마 그만))
    Game::Config.merge!('manito', 'reward_items_manito' => "초콜릿 개구리|1")
    described_class.record!(toot('@draco 그만'))
    described_class.record!(toot('@draco 그만 좀'))
    harry = GameCharacter.for(a)
    harry.update!(money: 1, inventory: [{ 'name' => '초콜릿 개구리', 'count' => 1, 'note' => '' }]) # 6 중 5 를 쓰고 개구리 하나를 먹었다

    described_class.guess!(b, '그만', a)

    expect(GameCharacter.for(a)).to have_attributes(money: -5, inventory: [])
    expect(GameCharacter.for(b).money).to eq 6
    expect(GameCharacter.for(b).inventory.pluck('name', 'count')).to eq [['초콜릿 개구리', 2]]
    expect(notes_to(a).last.text).to include('단어(그만)')
  end

  it 'charges a penalty for a wrong guess, refuses without the money, and limits guesses a day' do
    GameCharacter.for(b).update!(money: 1)
    house = GameHouse.create!(name: '슬리데린', category: 'house')
    GameCharacter.for(b).update!(house: house)
    Game::Config.merge!('manito', 'manito_wrong_points' => '2')

    expect(described_class.guess!(b, '아무말', a)).to include('오답', '벌금 1', '점수 2점')
    expect(GameHousePoint.where(house: house).sum(:amount)).to eq(-2)
    expect(GameCharacter.for(b).money).to eq 0
    expect(described_class.guess!(b, '아무말', a)).to include('필요합니다')

    GameCharacter.for(b).update!(money: 5)
    described_class.guess!(b, '아무말', a)
    expect(described_class.guess!(b, '하지마', a)).to include('더 추측할 수 없습니다') # 하루 2번
    expect(GameManitoLog.guesses.where(account: b).pluck(:kind)).to eq %w(wrong wrong)
  end

  it 'takes back the use and its reward when the toot is deleted' do
    status = toot('@draco 하지마')
    described_class.record!(status)
    expect(GameCharacter.for(a).money).to eq 3

    expect(described_class.word_toot?(status.id)).to be true
    status.discard_with_reblogs
    described_class.revert!(status.id)
    expect(described_class.word_toot?(status.id)).to be false

    expect(GameManitoWord.find_by!(account: a, target_account: b).uses).to eq 0
    expect(GameCharacter.for(a).money).to eq 0
    expect(GameManitoLog.uses).to be_empty
  end

  it 'gives every character words for every other character at random, keeping existing pairs unless asked' do
    GameCharacter.for(a)
    GameCharacter.for(b)
    GameCharacter.for(c)
    GameCharacter.for(shop) # 상점봇은 빠진다

    changed = described_class.assign_random!(%w(사과 배 귤), random: Random.new(1))
    expect(changed).to eq 4 # 6짝 중 이미 단어가 있는 harry→draco, harry→luna 는 그대로
    expect(GameManitoWord.find_by!(account: a, target_account: b).words).to eq %w(하지마)
    expect(GameManitoWord.where(account: [shop]).or(GameManitoWord.where(target_account: shop))).to be_empty

    described_class.assign_random!(%w(사과 배 귤), count: 2, replace: true, random: Random.new(2))
    words = GameManitoWord.where(account: a).map(&:words)
    expect(words).to all(have_attributes(size: 2))
    expect(words.flatten - %w(사과 배 귤)).to be_empty
  end

  it 'sends every character with words a start notice by a DM from the shop bot, listing the words per counterpart' do
    GameCharacter.for(a)
    GameCharacter.for(b)
    GameCharacter.for(c)
    GameCharacter.for(a).update!(name: '해리')
    GameCharacter.for(b).update!(name: '드레이코')

    expect(described_class.announce_start!).to eq 1 # 단어가 정해진 사람은 해리뿐
    dm = Status.where(account: shop, visibility: :direct).sole
    expect(dm.mentions.map(&:account_id)).to eq [a.id]
    expect(dm.text).to include('마니또가 시작되었습니다', '해리님은', '드레이코 : 하지마', 'luna : 달빛')
  end

  it 'does nothing while switched off' do
    Game::Config.merge!('manito', 'manito_enabled' => '0')
    described_class.record!(toot('@draco 하지마'))

    expect(GameManitoWord.find_by!(account: a, target_account: b).uses).to eq 0
    expect { described_class.guess!(b, '하지마', a) }.to raise_error(described_class::Error)
  end
end
