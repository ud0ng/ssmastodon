# frozen_string_literal: true

require 'rails_helper'

# 웹 알림창: 컨텐츠 명령어 알림만 숨기고, 기본 명령어(도움말·점수·내전적·사용)와 그 답장, 단순 멘션은 보인다
RSpec.describe Notification, '.without_game' do
  let(:system) { Fabricate(:user, account: Fabricate(:account, username: 'system')).account }
  let(:luna) { Fabricate(:user, account: Fabricate(:account, username: 'luna')).account }
  let(:harry) { Fabricate(:user, account: Fabricate(:account, username: 'harry')).account }

  before { Game::Config.update!('common', 'system_username' => 'system') }

  def mention(text, from:, to:, thread: nil)
    status = Fabricate(:status, account: from, text: text, thread: thread, visibility: :private)
    mention = Mention.create!(status: status, account: to)
    [status, mention]
  end

  def notice_for(mention)
    Notification.create!(account: mention.account, from_account: mention.status.account, type: :mention, activity: mention)
  end

  def shown?(notification)
    described_class.where(id: notification.id).without_game.exists?
  end

  it 'hides game commands but shows basic commands, their replies and plain mentions' do
    game_status, = mention('@system @luna [젤리빈]', from: harry, to: luna)
    Mention.create!(status: game_status, account: system)
    game_notice = notice_for(game_status.mentions.find_by(account: luna))

    basic_status, = mention('@system [점수]', from: harry, to: system)
    basic_reply_status, basic_reply_mention = mention('@harry 점수판', from: system, to: harry, thread: basic_status)
    plain_status, plain_mention = mention('@system 안녕', from: harry, to: system)
    game_reply_status, game_reply_mention = mention('@harry 시작합니다', from: system, to: harry, thread: game_status)

    expect(shown?(game_notice)).to be false
    expect(shown?(notice_for(basic_reply_mention))).to be true
    expect(shown?(notice_for(plain_mention))).to be true
    expect(shown?(notice_for(game_reply_mention))).to be false
    expect([basic_reply_status, plain_status, game_reply_status]).to all(be_present)

    expect(Game::System.hidden_notification?(notice_for(plain_mention))).to be false
    expect(Game::System.hidden_notification?(notice_for(basic_reply_mention))).to be false
    expect(Game::System.hidden_notification?(notice_for(game_reply_mention))).to be true
    expect(Game::System.hidden_notification?(game_notice)).to be true
  end

  it 'also hides what characters answer right under a game toot, but not the rest of the thread or a basic-command or plain conversation' do
    game_status, = mention('@system @luna [젤리빈]', from: harry, to: luna)
    Mention.create!(status: game_status, account: system)
    GameSession.create!(kind: 'jellybean', status: 'pending', visibility: 'private', root_status_id: game_status.id, state: {})
    chat_status, chat_mention = mention('@harry 좋아', from: luna, to: harry, thread: game_status)
    later_status, later_mention = mention('@luna 그래', from: harry, to: luna, thread: chat_status)
    plain_status, = mention('@system 안녕', from: harry, to: system)
    _plain_chat_status, plain_chat_mention = mention('@harry 안녕', from: luna, to: harry, thread: plain_status)

    expect([chat_status, later_status]).to all(be_present)
    expect(shown?(notice_for(chat_mention))).to be false
    expect(shown?(notice_for(later_mention))).to be true # 컨텐츠 툿에 바로 단 답만 숨긴다, 그 뒤 이야기는 보인다
    expect(Game::System.hidden_notification?(notice_for(chat_mention))).to be true
    expect(shown?(notice_for(plain_chat_mention))).to be true
    expect(Game::System.hidden_notification?(notice_for(plain_chat_mention))).to be false
  end

  it 'hides only the answer right under a command toot, not the talk that follows' do
    bracket_status, = mention('@system [그냥 괄호로 쓴 동작]', from: harry, to: system)
    reply_status, = mention('@harry 응', from: luna, to: harry, thread: bracket_status)
    _deeper_status, deeper_mention = mention('@luna 그래', from: harry, to: luna, thread: reply_status)

    expect(shown?(notice_for(deeper_mention))).to be true
    expect(Game::System.hidden_notification?(notice_for(deeper_mention))).to be false
  end

  it 'keeps showing the other replies of a big thread even if a game was played somewhere in it' do
    root_status, = mention('@luna 좋은 아침', from: harry, to: luna)
    game_status, = mention('@system @luna [젤리빈]', from: harry, to: luna, thread: root_status)
    Mention.create!(status: game_status, account: system)
    GameSession.create!(kind: 'jellybean', status: 'pending', visibility: 'private', root_status_id: game_status.id, state: {})
    other_status, other_mention = mention('@harry 나도 아침', from: luna, to: harry, thread: root_status)
    _bot_status, bot_mention = mention('@harry @luna 단어 1회 사용', from: Fabricate(:user, account: Fabricate(:account, username: 'bot')).account, to: harry, thread: other_status)

    expect(shown?(notice_for(other_mention))).to be true
    expect(shown?(notice_for(bot_mention))).to be true
    expect(Game::System.hidden_notification?(notice_for(other_mention))).to be false
  end
end
