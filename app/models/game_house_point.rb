# frozen_string_literal: true

# 기숙사 점수 장부 (게임 보상, 운영진 조정)
class GameHousePoint < ApplicationRecord
  belongs_to :house, class_name: 'GameHouse', foreign_key: :game_house_id, inverse_of: :points
  belongs_to :account, optional: true
  belongs_to :session, class_name: 'GameSession', foreign_key: :game_session_id, optional: true, inverse_of: :house_points

  validates :amount, numericality: { only_integer: true }
end
