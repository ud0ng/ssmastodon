# frozen_string_literal: true

require 'rails_helper'

# 일일 활동 스냅샷: 하루(한국 시간 00시 기준)마다 캐릭터의 툿 수·글자 수와 상대 캐릭터와의 수를 저장한다
RSpec.describe Game::ActivitySnapshot do
  let(:account) { Fabricate(:user).account }
  let(:other) { Fabricate(:user).account }
  let(:day) { Date.new(2026, 10, 20) }
  let(:noon) { Time.find_zone!('Asia/Seoul').local(2026, 10, 20, 12, 0) }

  def toot(text, at: noon, from: account, reply_to: nil, visibility: :public, media: false)
    status = Fabricate(:status, account: from, text: text, thread: reply_to, visibility: visibility, created_at: at)
    Fabricate(:media_attachment, status: status, account: from) if media
    status
  end

  # 한 날의 모든 모양의 툿
  def seed!
    parent = toot('상대 툿', from: other)
    nested = toot('상대 답', from: other, reply_to: parent)
    mine = toot('내 툿')
    toot('첫 답', reply_to: parent)
    toot('또 답', reply_to: parent, media: true) # 같은 툿에는 1회
    toot('다른 툿', reply_to: toot('상대 둘째', from: other))
    toot('답에 단 답', reply_to: nested)
    toot('내 툿에 단 답', reply_to: mine)
    toot('DM 하나', visibility: :direct).tap { |status| status.mentions.create!(account: other) }
    toot('사진 툿', media: true)
    Fabricate(:status, account: account, reblog: parent, created_at: noon)
    toot('지운 툿').discard
    toot('어제 11시 59분', at: Time.find_zone!('Asia/Seoul').local(2026, 10, 19, 23, 59))
    toot('내일 0시', at: Time.find_zone!('Asia/Seoul').local(2026, 10, 21, 0, 0))
  end

  it 'rebuilds one day exactly from the toots: totals, DMs, public, replies, reply turns and media' do
    seed!
    described_class.rebuild!(day)

    row = GameActivityDay.find_by!(day: day, account_id: account.id)
    # DM 제외 전체: 내 툿, 첫 답, 또 답, 다른 툿, 답에 단 답, 내 툿에 단 답, 사진 툿 = 7
    expect(row).to have_attributes(posts: 7, dms: 1, dm_chars: 'DM 하나'.size, public_posts: 2, reply_posts: 5, media: 2)
    expect(row.post_chars).to eq ['내 툿', '첫 답', '또 답', '다른 툿', '답에 단 답', '내 툿에 단 답', '사진 툿'].sum(&:size)
    expect(row.reply_chars).to eq ['첫 답', '또 답', '다른 툿', '답에 단 답', '내 툿에 단 답'].sum(&:size)
    # 답 횟수: 상대의 두 퍼블 툿에 단 답 (같은 툿은 1회). 답 툿에 단 답·자기 툿에 단 답은 뺀다
    expect(row.reply_turns).to eq 2

    pair = GameActivityPair.find_by!(day: day, account_id: account.id, other_account_id: other.id)
    expect(pair).to have_attributes(reply_posts: 4, reply_media: 1, reply_turns: 2, dms: 1, dm_chars: 'DM 하나'.size)
    expect(described_class.pairs_to(account.id)).to eq({}) # 상대가 이 캐릭터에게 쓴 것은 이 날 없다
    expect(described_class.pairs_to(other.id)[account.id]).to have_attributes(reply_posts: 4, reply_turns: 2) # 이 캐릭터 → 상대
    expect(GameActivityDay.where(day: day - 1, account_id: account.id)).to be_empty # 이 날만 다시 계산했다
    described_class.rebuild!(day - 1)
    expect(GameActivityDay.find_by!(day: day - 1, account_id: account.id).posts).to eq 1 # 한국 시간으로 어제 23:59
  end

  it 'counts a visit once per conversation, also when answering a follow-up toot, and not again on another day' do
    root = toot('상대 툿', from: other, at: noon - 1.day)
    follow = toot('상대 이어쓰기', from: other, reply_to: root, at: noon - 1.day)
    toot('첫 답', reply_to: follow)
    toot('다음날 또 답', reply_to: root, at: noon + 1.day)
    other_reply = toot('내 툿', at: noon)
    toot('상대가 내 툿에 답', from: other, reply_to: other_reply, at: noon + 2.days)
    toot('내가 상대 답에 다시 답', reply_to: toot('상대의 답의 답', from: other, reply_to: other_reply), at: noon + 2.days)
    (-1..3).each { |offset| described_class.rebuild!(day + offset) }

    mine = GameActivityPair.where(account_id: account.id, other_account_id: other.id)
    expect(mine.sum(:reply_turns)).to eq 1 # 한 대화에 한 번 (이어쓴 툿에 달아도 1, 다음 날 또 달아도 그대로)
    expect(GameActivityPair.where(account_id: other.id, other_account_id: account.id).sum(:reply_turns)).to eq 1 # 상대가 내 툿에 찾아온 것
    expect(GameActivityDay.where(account_id: account.id).sum(:reply_turns)).to eq 1
  end

  it 'does not count visits to or from the system and shop bots' do
    bot = Fabricate(:user).account
    allow(Game::System).to receive(:account).and_return(bot)
    toot('시스템 툿', from: bot).then { |status| toot('시스템에 답', reply_to: status) }
    described_class.rebuild!(day)
    expect(GameActivityDay.find_by!(day: day, account_id: account.id).reply_turns).to eq 0
  end

  it 'gives the per-turn, per-toot and skip ratios of a counterpart, nil when there is nothing to divide' do
    totals = described_class::PairTotals.new(reply_posts: 10, reply_chars: 500, reply_turns: 3, skipped: 1)
    expect(totals.avg_chars).to eq 50
    expect(totals.posts_per_turn).to eq 3.3 # 10 toots over 3 turns
    expect(totals.skip_rate).to eq 25.0 # 1 / (3 + 1)
    expect(described_class::PairTotals.empty).to have_attributes(posts_per_turn: nil, avg_chars: nil, skip_rate: nil)
  end

  it 'rebuilding replaces what was there, so deleted toots drop out' do
    status = toot('곧 지울 툿')
    described_class.rebuild!(day)
    expect(GameActivityDay.find_by!(day: day, account_id: account.id).posts).to eq 1

    status.discard
    described_class.rebuild!(day)
    expect(GameActivityDay.find_by(day: day, account_id: account.id)).to be_nil
  end

  it 'adds a toot to its day as it is written, matching what a rebuild would give' do
    seed!
    Status.where(account_id: [account.id, other.id]).order(:id).each { |status| described_class.record!(status.id) }

    live = GameActivityDay.find_by!(day: day, account_id: account.id).slice(*GameActivityDay::COLUMNS)
    pair_live = GameActivityPair.find_by!(day: day, account_id: account.id, other_account_id: other.id).slice(*GameActivityPair::COLUMNS)
    described_class.rebuild!(day)

    expect(GameActivityDay.find_by!(day: day, account_id: account.id).slice(*GameActivityDay::COLUMNS)).to eq live
    expect(GameActivityPair.find_by!(day: day, account_id: account.id, other_account_id: other.id).slice(*GameActivityPair::COLUMNS)).to eq pair_live
  end

  it 'fills the missing days and remembers how far it has built' do
    toot('이틀 전', at: Time.find_zone!('Asia/Seoul').local(2026, 10, 20, 9))
    toot('어제', at: Time.find_zone!('Asia/Seoul').local(2026, 10, 21, 9))
    travel_to(Time.find_zone!('Asia/Seoul').local(2026, 10, 22, 0, 5)) do
      described_class.catch_up!

      expect(GameActivityDay.where(account_id: account.id).order(:day).pluck(:day, :posts)).to eq [[Date.new(2026, 10, 20), 1], [Date.new(2026, 10, 21), 1]]
      expect(described_class.built_through).to eq Date.new(2026, 10, 21)

      toot('어제 늦게', at: Time.find_zone!('Asia/Seoul').local(2026, 10, 21, 23))
      described_class.catch_up!
      expect(GameActivityDay.find_by!(day: Date.new(2026, 10, 21), account_id: account.id).posts).to eq 2
    end
  end

  it 'reads totals, daily rows and counterpart rows' do
    seed!
    described_class.rebuild!(day)
    described_class.rebuild!(day - 1)

    expect(described_class.totals([account.id])[account.id].posts).to eq 8
    expect(described_class.totals([account.id], from: day, to: day)[account.id].posts).to eq 7
    expect(described_class.daily([account.id]).map(&:first)).to eq [day, day - 1]
    expect(described_class.pairs(account.id)[other.id].reply_posts).to eq 4
    expect(described_class.pair_daily(account.id, other.id).map(&:first)).to eq [day]
  end
  describe "skipped (스루)" do
    let(:third) { Fabricate(:user).account }
    let(:system_account) { Fabricate(:user, account: Fabricate(:account, username: "system")).account }

    before { allow(Game::System).to receive(:account).and_return(system_account) }

    def tag(text, from:, to:, visibility: :private, thread: nil)
      status = Fabricate(:status, account: from, text: text, visibility: visibility, thread: thread, created_at: noon + ((@tick = (@tick || 0) + 1).seconds))
      Array(to).each { |target| Mention.create!(status: status, account: target) }
      status
    end

    it "counts followers-only and unlisted one-to-one tags that were not answered, even if hearted, and leaves out the rest" do
      tag("안 답함", from: other, to: account)
      tag("조용한 공개", from: other, to: account, visibility: :unlisted)
      answered = tag("답함", from: other, to: account)
      Fabricate(:status, account: account, thread: answered, created_at: noon)
      tag("DM", from: other, to: account, visibility: :direct)
      tag("공개", from: other, to: account, visibility: :public)
      tag("셋이서", from: other, to: [account, third])
      tag("시스템에게", from: other, to: [account, system_account])
      tag("시스템이 보냄", from: system_account, to: account)
      Favourite.create!(account: account, status: tag("하트만 누름", from: other, to: account))

      described_class.rebuild!(day)

      expect(GameActivityDay.find_by!(day: day, account_id: account.id).skipped).to eq 3
      expect(GameActivityPair.find_by!(day: day, account_id: account.id, other_account_id: other.id).skipped).to eq 3
    end

    it 'counts the unanswered replies B strings together after A started the thread as one skip' do
      opener = tag('A가 B를 태그', from: account, to: other)
      first = tag('B의 답멘', from: other, to: account, thread: opener)
      second = tag('B의 또 답멘', from: other, to: account, thread: first)

      described_class.rebuild!(day)
      expect(GameActivityDay.find_by!(day: day, account_id: account.id).skipped).to eq 1
      expect(GameActivityPair.find_by!(day: day, account_id: account.id, other_account_id: other.id).skipped).to eq 1

      # 실시간으로 쌓아도 같다
      GameActivityDay.delete_all
      GameActivityPair.delete_all
      [opener, first, second].each { |status| described_class.record!(status.id) }
      expect(GameActivityDay.find_by!(day: day, account_id: account.id).skipped).to eq 1

    end

    it "adds a tag as it is written and takes it back when the tagged character answers, matching a rebuild" do
      tagged = tag("태그", from: other, to: account)
      described_class.record!(tagged.id)
      expect(GameActivityDay.find_by!(day: day, account_id: account.id).skipped).to eq 1

      reply = Fabricate(:status, account: account, thread: tagged, created_at: noon + 1.minute)
      described_class.record!(reply.id)
      expect(GameActivityDay.find_by!(day: day, account_id: account.id).skipped).to eq 0

      described_class.rebuild!(day)
      expect(GameActivityDay.find_by(day: day, account_id: account.id)&.skipped.to_i).to eq 0
    end
  end
end
