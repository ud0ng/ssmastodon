# frozen_string_literal: true

# 게임 한 판. kind: Game::Kinds 의 키 (jellybean 등), status: pending(수락 대기) → active → finished / cancelled
class GameSession < ApplicationRecord
  STATUSES = %w(pending active finished cancelled).freeze

  has_many :players, -> { order(:seat) }, class_name: 'GamePlayer', dependent: :destroy, inverse_of: :session
  has_many :house_points, class_name: 'GameHousePoint', dependent: :nullify

  validates :status, inclusion: { in: STATUSES }
  validates :visibility, inclusion: { in: %w(private direct) }

  scope :open, -> { where(status: %w(pending active)) }

  def open?
    %w(pending active).include?(status)
  end

  def kind_class
    Game::Kinds.fetch(kind)
  end

  def player_for(account)
    players.find { |player| player.account_id == account.id }
  end

  def opponent_of(player)
    players.find { |other| other.id != player.id }
  end

  # 시간 제한 작업이 아직 유효한지 (새 단계로 넘어가면 예전 작업은 무시)
  def deadline_token
    "#{status}:#{turn}:#{deadline_at&.to_i}"
  end
end
