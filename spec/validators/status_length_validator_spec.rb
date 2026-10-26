# frozen_string_literal: true

require 'rails_helper'

RSpec.describe StatusLengthValidator do
  describe '.max_chars' do
    it 'uses the admin setting' do
      Setting.status_max_characters = 3000

      expect(described_class.max_chars).to eq 3000
    end

    it 'falls back to the default when the setting is out of range' do
      Setting.status_max_characters = 50

      expect(described_class.max_chars).to eq described_class::DEFAULT_MAX_CHARS
    end
  end

  describe '#validate' do
    before { Setting.status_max_characters = 500 } # Example values below are relative to this baseline

    it 'does not add errors onto remote statuses' do
      status = instance_double(Status, local?: false)
      allow(status).to receive(:errors)

      subject.validate(status)

      expect(status).to_not have_received(:errors)
    end

    it 'does not add errors onto local reblogs' do
      status = instance_double(Status, local?: false, reblog?: true)
      allow(status).to receive(:errors)

      subject.validate(status)

      expect(status).to_not have_received(:errors)
    end

    it 'adds an error when content warning is over character limit' do
      status = status_double(spoiler_text: 'a' * 520)
      subject.validate(status)
      expect(status.errors).to have_received(:add)
    end

    it 'adds an error when text is over character limit' do
      status = status_double(text: 'a' * 520)
      subject.validate(status)
      expect(status.errors).to have_received(:add)
    end

    it 'adds an error when text and content warning are over character limit total' do
      status = status_double(spoiler_text: 'a' * 250, text: 'b' * 251)
      subject.validate(status)
      expect(status.errors).to have_received(:add)
    end

    it 'reduces calculated length of auto-linkable space-separated URLs' do
      text = [starting_string, example_link].join(' ')
      status = status_double(text: text)

      subject.validate(status)
      expect(status.errors).to_not have_received(:add)
    end

    it 'does not reduce calculated length of non-autolinkable URLs' do
      text = [starting_string, example_link].join
      status = status_double(text: text)

      subject.validate(status)
      expect(status.errors).to have_received(:add)
    end

    it 'does not reduce calculated length of count overly long URLs' do
      text = "http://example.com/valid?#{'#foo?' * 1000}"
      status = status_double(text: text)
      subject.validate(status)
      expect(status.errors).to have_received(:add)
    end

    it 'counts only the front part of remote usernames' do
      text   = ('a' * 475) + " @alice@#{'b' * 30}.com"
      status = status_double(text: text)

      subject.validate(status)
      expect(status.errors).to_not have_received(:add)
    end

    it 'does count both parts of remote usernames for overly long domains' do
      text   = "@alice@#{'b' * 500}.com"
      status = status_double(text: text)

      subject.validate(status)
      expect(status.errors).to have_received(:add)
    end

    it 'counts multi byte emoji as single character' do
      text = '✨' * 500
      status = status_double(text: text)

      subject.validate(status)
      expect(status.errors).to_not have_received(:add)
    end

    it 'counts ZWJ sequence emoji as single character' do
      text = '🏳️‍⚧️' * 500
      status = status_double(text: text)

      subject.validate(status)
      expect(status.errors).to_not have_received(:add)
    end
  end

  private

  def starting_string
    'a' * 476
  end

  def example_link
    "http://#{'b' * 30}.com/example"
  end

  def status_double(spoiler_text: '', text: '')
    instance_double(
      Status,
      spoiler_text: spoiler_text,
      text: text,
      errors: activemodel_errors,
      local?: true,
      reblog?: false
    )
  end

  def activemodel_errors
    instance_double(ActiveModel::Errors, add: nil)
  end

  # 최소 글자수 (서버 설정 > 운영): 멘션·띄어쓰기는 세지 않고, 운영 계정과 [명령어]만 쓴 툿은 뺀다
  describe 'minimum length' do
    let(:member) { Fabricate(:account, username: 'harry') }
    let(:friend) { Fabricate(:account, username: 'ron') }

    before { Setting.status_min_characters = 5 }

    def build(account, text, spoiler_text: '')
      Status.new(account: account, text: text, spoiler_text: spoiler_text)
    end

    def short?(status)
      subject.validate(status)
      status.errors[:text].any?
    end

    it 'can leave out toots that are not replies, and direct messages, with the two options' do
      reply = Status.new(account: member, text: '안녕', in_reply_to_id: Fabricate(:status).id)
      plain = build(member, '안녕')
      direct = Status.new(account: member, text: '안녕', visibility: :direct)
      direct_reply = Status.new(account: member, text: '안녕', visibility: :direct, in_reply_to_id: reply.in_reply_to_id)
      expect([plain, reply, direct].map { |status| short?(status) }).to eq [true, true, true]

      Setting.status_min_exclude_public = true
      expect([build(member, '안녕'), Status.new(account: member, text: '안녕', in_reply_to_id: reply.in_reply_to_id), Status.new(account: member, text: '안녕', visibility: :direct)].map { |status| short?(status) }).to eq [false, true, true]

      Setting.status_min_exclude_public = false
      Setting.status_min_exclude_dm = true
      expect([build(member, '안녕'), Status.new(account: member, text: '안녕', in_reply_to_id: reply.in_reply_to_id), Status.new(account: member, text: '안녕', visibility: :direct), direct_reply].map { |status| short?(status) }).to eq [true, true, false, false]
    ensure
      Setting.status_min_exclude_public = false
      Setting.status_min_exclude_dm = false
    end

    it 'blocks posts shorter than the minimum, not counting mentions and spaces' do
      expect(short?(build(member, "@#{friend.username} 안 녕"))).to be true
      expect(short?(build(member, "@#{friend.username} 안녕하세요"))).to be false
      expect(short?(build(member, '가 나 다 라 마'))).to be false
    end

    it 'does not block command-only posts or staff accounts' do
      expect(short?(build(member, "@system @#{friend.username} [고발]"))).to be false
      expect(short?(build(member, '@system [예언/호그와트]'))).to be false
      expect(short?(build(member, '@system 응응'))).to be true # 명령어 없이 짧은 글은 막는다

      admin = Fabricate(:user, role: Fabricate(:user_role, name: 'Boss', permissions: UserRole::FLAGS[:administrator])).account
      expect(short?(build(admin, '네'))).to be false
    end

    it 'does not block posts with media or polls' do
      with_media = build(member, '네')
      with_media.media_attachments = [Fabricate(:media_attachment, account: member)]
      expect(short?(with_media)).to be false

      with_poll = build(member, '골라')
      with_poll.poll = Poll.new(account: member, options: %w(하나 둘), expires_at: 1.day.from_now)
      expect(short?(with_poll)).to be false
    end

    it 'does not block content, event and bot commands even with other words' do
      system = Fabricate(:account, username: 'system')
      allow(Game::System).to receive(:account).and_return(system)
      Fabricate(:account, username: 'shopbot', actor_type: 'Service')

      expect(short?(build(member, "@system [젤리빈] @#{friend.username} 한판"))).to be false
      expect(short?(build(member, '@shopbot [구매/버터맥주] 줘'))).to be false
      # 봇이 아닌 사람에게 쓴 대괄호는 명령어가 아니다
      expect(short?(build(member, "@#{friend.username} [ㅋ] 응"))).to be true
    end

    it 'is off at zero and only checks new or edited text' do
      Setting.status_min_characters = 0
      expect(short?(build(member, '네'))).to be false

      Setting.status_min_characters = 0
      status = Fabricate(:status, account: member, text: '네')
      Setting.status_min_characters = 5
      status.reload.sensitive = true
      expect(short?(status)).to be false
      status.text = '응'
      expect(short?(status)).to be true
    end
  end
end
