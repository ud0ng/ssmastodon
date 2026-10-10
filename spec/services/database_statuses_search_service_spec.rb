# frozen_string_literal: true

require 'rails_helper'

RSpec.describe DatabaseStatusesSearchService do
  subject { described_class.new.call(query, account, limit: 20) }

  let(:account) { Fabricate(:account) }
  let(:followed) { Fabricate(:account) }
  let(:stranger) { Fabricate(:account) }

  before { account.follow!(followed) }

  context 'with the default following scope' do
    let(:query) { '사과' }

    it 'finds own and followed statuses only' do
      own = Fabricate(:status, account: account, text: '오늘 사과를 먹었다')
      by_followed = Fabricate(:status, account: followed, text: '사과 맛있다', visibility: :private)
      Fabricate(:status, account: stranger, text: '사과 좋아')
      Fabricate(:status, account: account, text: '바나나')

      expect(subject).to contain_exactly(own, by_followed)
    end

    it 'searches content warnings too' do
      status = Fabricate(:status, account: followed, text: '본문', spoiler_text: '사과 이야기')

      expect(subject).to contain_exactly(status)
    end
  end

  context 'when the scope is the whole server' do
    let(:query) { 'apple' }

    before { Setting.status_search_scope = 'all' }

    it 'finds public statuses from anyone, case-insensitively, but not private or direct ones' do
      public_status = Fabricate(:status, account: stranger, text: 'Apple pie')
      Fabricate(:status, account: stranger, text: 'apple private', visibility: :private)
      Fabricate(:status, account: stranger, text: 'apple dm', visibility: :direct)

      expect(subject).to contain_exactly(public_status)
    end
  end

  context 'with a direct message that mentions the account' do
    let(:query) { 'secret' }

    it 'finds it' do
      dm = Fabricate(:status, account: stranger, text: 'the secret plan', visibility: :direct)
      Fabricate(:mention, account: account, status: dm)

      expect(subject).to contain_exactly(dm)
    end
  end

  context 'with search syntax' do
    let!(:cats_and_dogs) { Fabricate(:status, account: followed, text: 'cats and dogs') }
    let!(:cats_only) { Fabricate(:status, account: followed, text: 'cats only') }
    let!(:my_cats) { Fabricate(:status, account: account, text: 'my cats') }

    it 'excludes negated terms' do
      expect(described_class.new.call('cats -dogs', account, limit: 20)).to contain_exactly(cats_only, my_cats)
    end

    it 'matches quoted phrases' do
      expect(described_class.new.call('"cats and"', account, limit: 20)).to contain_exactly(cats_and_dogs)
    end

    it 'filters by author' do
      expect(described_class.new.call('cats from:me', account, limit: 20)).to contain_exactly(my_cats)
    end

    it 'escapes LIKE wildcards' do
      expect(described_class.new.call('%', account, limit: 20)).to be_empty
    end
  end

  context 'with a blank query' do
    let(:query) { '  ' }

    it { is_expected.to be_empty }
  end
end
