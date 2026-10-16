# frozen_string_literal: true

# 재화 기록: 컨텐츠 보상(Game::Rewards)과 자동봇·운영진의 돈·아이템·스탯 변경(Game::Wallet).
#   money: 바뀐 돈 (음수면 쓴 돈), items: [{ name, count }] (음수면 잃은 개수), stats: { 이름 => 바뀐 값 }
#   kind: content(컨텐츠 보상) purchase use consume transfer attendance toot randombox investigation admin
# 기록이 생기면 그 사람 웹 화면(글쓰기창 아래 재화·인벤토리, 재화·상점 화면)에 스트리밍으로 알려 바로 다시 읽게 한다.
class GameReward < ApplicationRecord
  include Redisable

  KINDS = %w(content purchase use consume transfer attendance toot randombox investigation admin).freeze

  belongs_to :account
  belongs_to :session, class_name: 'GameSession', foreign_key: :game_session_id, optional: true, inverse_of: :rewards

  validates :kind, inclusion: { in: KINDS }

  scope :today, -> { where(created_at: Time.now.in_time_zone('Asia/Seoul').beginning_of_day..) }
  scope :gained, -> { where(money: 1..) }
  scope :spent, -> { where(money: ...0) }
  scope :with_items, -> { where('jsonb_array_length(game_rewards.items) > 0') }

  after_create_commit :broadcast_wallet_change

  private

  def broadcast_wallet_change
    redis.publish("timeline:#{account_id}", Oj.dump(event: :'wallet.changed', payload: '1'))
  rescue Redis::BaseError => e
    Rails.logger.warn { "wallet.changed broadcast failed: #{e.message}" }
  end
end
