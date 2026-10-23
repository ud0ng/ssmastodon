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
    expect(GameActivityDay.where(day: day - 1, account_id: account.id)).to be_empty # 이 날만 다시 계산했다
    described_class.rebuild!(day - 1)
    expect(GameActivityDay.find_by!(day: day - 1, account_id: account.id).posts).to eq 1 # 한국 시간으로 어제 23:59
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

  it 'reads totals, daily rows, counterpart rows and the yesterday + today window' do
    seed!
    described_class.rebuild!(day)
    described_class.rebuild!(day - 1)

    expect(described_class.totals([account.id])[account.id].posts).to eq 8
    expect(described_class.totals([account.id], from: day, to: day)[account.id].posts).to eq 7
    expect(described_class.daily([account.id]).map(&:first)).to eq [day, day - 1]
    expect(described_class.pairs(account.id)[other.id].reply_posts).to eq 4
    expect(described_class.pair_daily(account.id, other.id).map(&:first)).to eq [day]

    travel_to(Time.find_zone!('Asia/Seoul').local(2026, 10, 21, 10)) do
      recent = described_class.recent([account.id])[account.id]
      expect(recent[:yesterday].posts).to eq 7
      expect(recent[:today].posts).to eq 0
    end
  end
end
