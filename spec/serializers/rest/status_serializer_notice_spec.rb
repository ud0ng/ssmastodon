# frozen_string_literal: true

require 'rails_helper'

# 시스템 계정이 올린 툿 중 웹에서도 숨기지 않는 것 (game_notice): 태그 없이 올린 안내, 표시해 둔 호울러 DM. 컨텐츠 카드와 태그된 컨텐츠 툿은 숨긴다
RSpec.describe REST::StatusSerializer, 'game_notice' do
  let(:system) { Fabricate(:user, account: Fabricate(:account, username: 'system')).account }
  let(:harry) { Fabricate(:user, account: Fabricate(:account, username: 'harry')).account }

  before { allow(Game::System).to receive(:cached_account_id).and_return(system.id) }

  def notice?(status)
    serialized_record_json(status, described_class, options: { scope: Fabricate(:user), scope_name: :current_user })['game_notice']
  end

  it 'marks untagged system toots and marked notices, but not tagged game toots, cards or other people' do
    untagged = Fabricate(:status, account: system, text: '호울러가 울려 퍼진다', visibility: :private)
    tagged = Fabricate(:status, account: system, text: '@harry 1라운드', visibility: :private)
    Mention.create!(status: tagged, account: harry)
    marked = Fabricate(:status, account: system, text: '@harry 소문', visibility: :direct)
    Mention.create!(status: marked, account: harry)
    GameNotice.create!(status: marked)
    card = Fabricate(:status, account: system, text: '모집', visibility: :private)
    GameEvent.create!(status: card, payload: {})
    human = Fabricate(:status, account: harry, text: '그냥 툿')

    expect(notice?(untagged)).to be true
    expect(notice?(marked)).to be true
    expect(notice?(tagged)).to be_nil
    expect(notice?(card)).to be_nil
    expect(notice?(human)).to be_nil
  end

  it 'also marks what the system answers to a basic command, but not the answer to a content command' do
    score = Fabricate(:status, account: harry, text: '@system [점수]', visibility: :private)
    answer = Fabricate(:status, account: system, text: '@harry 점수판', visibility: :private, thread: score)
    Mention.create!(status: answer, account: harry)
    play = Fabricate(:status, account: harry, text: '@system [젤리빈]', visibility: :private)
    play_answer = Fabricate(:status, account: system, text: '@harry 신청', visibility: :private, thread: play)
    Mention.create!(status: play_answer, account: harry)

    expect(notice?(answer)).to be true
    expect(notice?(play_answer)).to be_nil
  end
end
