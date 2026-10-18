# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Game::Activity do
  let(:account) { Fabricate(:user).account }
  let(:other) { Fabricate(:account) }
  let(:character) { GameCharacter.for(account) }

  def toot(text, reply_to: nil, visibility: :public)
    Fabricate(:status, account: account, text: text, thread: reply_to, visibility: visibility)
  end

  it 'counts posts and replies with their length, leaving out DMs, boosts and deleted toots' do
    parent = Fabricate(:status, account: other)
    toot('안녕하세요')
    toot("@#{other.username} 태그만 한 툿")
    toot('답글', reply_to: parent)
    toot('비밀', visibility: :direct)
    Fabricate(:status, account: account, reblog: parent)
    toot('지운 툿').discard

    stats = described_class.stats([account.id])[account.id]
    expect(stats.to_h).to eq(posts: 2, post_chars: 5 + "@#{other.username} 태그만 한 툿".size, replies: 1, reply_chars: 2)
  end

  describe 'toot reward' do
    before do
      character
      Game::Config.merge!('common', 'toot_reward_basis' => 'toots', 'toot_reward_public' => '0', 'toot_reward_every' => '2', 'toot_reward_amount' => '10')
    end

    it 'starts from what is already there, then pays each time a unit is filled' do
      parent = Fabricate(:status, account: other)
      3.times { toot('이미 쓴 답글', reply_to: parent) }
      expect(described_class.reward!(account)).to eq 0 # 처음: 출발점만

      toot('답글', reply_to: parent)
      toot('퍼블은 세지 않음')
      expect(described_class.reward!(account)).to eq 10 # 4개 → 2단위째
      expect(described_class.reward!(account)).to eq 0

      2.times { toot('답글', reply_to: parent) }
      expect(described_class.reward!(account)).to eq 10
      expect(character.reload.money).to eq 20
      expect(GameReward.where(account: account, kind: 'toot').count).to eq 2
    end

    it 'writes the reason in Korean with the unit of the reward basis' do
      parent = Fabricate(:status, account: other)
      described_class.reward!(account)
      2.times { toot('답글', reply_to: parent) }
      described_class.reward!(account)
      expect(GameReward.where(account: account, kind: 'toot').last.reason).to eq '툿 보상 (2툿)'

      Game::Config.merge!('common', 'toot_reward_basis' => 'chars', 'toot_reward_every' => '3')
      described_class.reward!(account)
      toot('여섯글자입니다', reply_to: parent)
      described_class.reward!(account)
      expect(GameReward.where(account: account, kind: 'toot').last.reason).to match(/\A툿 보상 \(\d+자\)\z/)
    end

    it 'is checked by a worker whenever a toot is saved' do
      expect { toot('하나') }.to change(Game::ActivityWorker.jobs, :size).by(1)
      expect { toot('비밀', visibility: :direct) }.to_not change(Game::ActivityWorker.jobs, :size)
    end
  end
end
