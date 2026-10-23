# frozen_string_literal: true

require 'rails_helper'

# 편애·차별 보기: 상대마다의 대우를 그 캐릭터 자신의 평균과 견준다 (1.0 = 평균대로)
RSpec.describe Game::Fairness do
  def totals(**values)
    Game::ActivitySnapshot::PairTotals.new(**Game::ActivitySnapshot::PairTotals.empty.to_h.merge(values))
  end

  let(:favored) { totals(reply_turns: 6, reply_posts: 12, reply_chars: 1200, skipped: 0) }
  let(:ignored) { totals(reply_turns: 0, skipped: 4) }
  let(:usual) { totals(reply_turns: 2, reply_posts: 4, reply_chars: 200, skipped: 1) }
  let(:all) { favored + ignored + usual }

  it 'scores each counterpart against the own average, with the fair share of visits as 1.0' do
    score = described_class.score(favored, all, 4) # 상대 4명, 찾아간 8회 중 6회
    expect(score.interest).to eq 3.0 # 6/8 ÷ 1/4
    expect(score.care).to eq 1.14 # 100자 ÷ 평균 88자 (1400자 / 16툿)
    expect(score.overall).to be > 3
    expect(score.few?).to be false

    expect(described_class.score(ignored, all, 4)).to have_attributes(interest: 0.0, overall: 0.0, basis: 4)
    expect(described_class.score(totals, all, 4)).to have_attributes(interest: 0.0, care: nil, response: nil, overall: 0.0)
    expect(described_class.score(usual, totals, 4).overall).to be_nil # 아무도 찾아가지 않은 캐릭터는 견줄 평균이 없다
  end

  it 'ranks from the most favored to the most ignored, fewer skips first on a tie' do
    entries = { favored: favored, nobody: totals, ignored: ignored, usual: usual }.map { |key, row| [key, row, described_class.score(row, all, 4)] }
    expect(described_class.ranks(entries)).to eq(favored: 1, usual: 2, nobody: 3, ignored: 4)
  end
end
