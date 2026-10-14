# frozen_string_literal: true

# 재화 기록: 컨텐츠 보상(Game::Rewards)과 자동봇·운영진의 돈·아이템·스탯 변경(Game::Wallet).
#   money: 바뀐 돈 (음수면 쓴 돈), items: [{ name, count }] (음수면 잃은 개수), stats: { 이름 => 바뀐 값 }
#   kind: content(컨텐츠 보상) purchase use consume transfer attendance toot randombox investigation admin
class GameReward < ApplicationRecord
  KINDS = %w(content purchase use consume transfer attendance toot randombox investigation admin).freeze

  belongs_to :account
  belongs_to :session, class_name: 'GameSession', foreign_key: :game_session_id, optional: true, inverse_of: :rewards

  validates :kind, inclusion: { in: KINDS }

  scope :today, -> { where(created_at: Time.now.in_time_zone('Asia/Seoul').beginning_of_day..) }
end
