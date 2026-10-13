# frozen_string_literal: true

# 컨텐츠 보상 기록 (Game::Rewards). items: [{ name, count }]
class GameReward < ApplicationRecord
  belongs_to :account
  belongs_to :session, class_name: 'GameSession', foreign_key: :game_session_id, optional: true, inverse_of: :rewards
end
