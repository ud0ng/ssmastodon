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
end
