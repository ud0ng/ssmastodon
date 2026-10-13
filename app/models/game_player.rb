# frozen_string_literal: true

class GamePlayer < ApplicationRecord
  RESULTS = %w(win lose draw).freeze

  belongs_to :session, class_name: 'GameSession', foreign_key: :game_session_id, inverse_of: :players
  belongs_to :account

  validates :result, inclusion: { in: RESULTS }, allow_nil: true

  def character
    @character ||= GameCharacter.for(account)
  end

  def name
    character.display_name
  end
end
