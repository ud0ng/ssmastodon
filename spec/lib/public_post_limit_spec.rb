# frozen_string_literal: true

require 'rails_helper'

# 퍼블툿 제한: [간격]에 [개수]개. 간격 0 이면 제한 없음, 답 툿·DM·운영 계정은 제외
RSpec.describe PublicPostLimit do
  let(:account) { Fabricate(:user).account }

  def post!(visibility: :public, thread: nil, at: Time.current)
    Fabricate(:status, account: account, visibility: visibility, thread: thread, created_at: at)
  end

  def check
    described_class.check!(account, visibility: :public, in_reply_to: nil)
  end

  after do
    Setting.status_public_limit_interval = 0
    Setting.status_public_limit_unit = 'hour'
    Setting.status_public_limit_count = 3
  end

  it 'does nothing while the interval is 0' do
    Setting.status_public_limit_count = 1
    2.times { post! }
    expect { check }.not_to raise_error
  end

  it 'blocks the post after the limit and tells how long is left, counting down from the oldest toot in the window' do
    Setting.status_public_limit_interval = 3
    Setting.status_public_limit_unit = 'hour'
    Setting.status_public_limit_count = 4
    post!(at: 150.minutes.ago)
    2.times { |index| post!(at: (60 - (index * 10)).minutes.ago) }
    expect { check }.not_to raise_error # 4개째까지는 쓸 수 있다 (지금 3개)

    post!(at: 5.minutes.ago)
    expect { check }.to raise_error(described_class::Error) { |error|
      expect(error.retry_after).to be_within(2).of(30.minutes) # 150분 전 툿이 3시간(180분)을 채울 때까지
      expect(error.limit).to eq 4
      expect(error.message).to include('30:00')
    }
  end

  it 'counts only public toots: replies, direct messages and old toots are not counted' do
    Setting.status_public_limit_interval = 1
    Setting.status_public_limit_unit = 'hour'
    Setting.status_public_limit_count = 1
    parent = Fabricate(:status)
    post!(thread: parent)
    post!(visibility: :direct)
    post!(at: 2.hours.ago)
    expect { check }.not_to raise_error

    post!(visibility: :private)
    expect { check }.to raise_error(described_class::Error)
  end

  it 'does not limit replies, direct messages and staff' do
    Setting.status_public_limit_interval = 1
    Setting.status_public_limit_count = 1
    post!
    expect { described_class.check!(account, visibility: :public, in_reply_to: 123) }.not_to raise_error
    expect { described_class.check!(account, visibility: :direct, in_reply_to: nil) }.not_to raise_error

    admin = Fabricate(:admin_user).account
    2.times { Fabricate(:status, account: admin) }
    expect { described_class.check!(admin, visibility: :public, in_reply_to: nil) }.not_to raise_error
  end

  it 'stops a post in the service and returns the countdown from the API error' do
    Setting.status_public_limit_interval = 1
    Setting.status_public_limit_count = 1
    post!
    expect { PostStatusService.new.call(account, text: '둘째 퍼블툿', visibility: 'public') }.to raise_error(described_class::Error)
    expect { PostStatusService.new.call(account, text: '답', thread: Fabricate(:status)) }.not_to raise_error
  end
end
