# frozen_string_literal: true

class GamePlayer < ApplicationRecord
  RESULTS = %w(win lose draw).freeze

  belongs_to :session, class_name: 'GameSession', foreign_key: :game_session_id, inverse_of: :players
  belongs_to :account

  validates :result, inclusion: { in: RESULTS }, allow_nil: true

  # 팀이 있는 이벤트(도둑 지도)는 대기실에 들어온 사람을 정원에 맞춰 무작위로 팀에 넣는다 (대기실에서 [팀 변경]으로 바꿀 수 있다)
  after_create :assign_lobby_team

  def character
    @character ||= GameCharacter.for(account)
  end

  def name
    character.display_name
  end

  private

  def assign_lobby_team
    kind = session.kind_class
    return unless kind.respond_to?(:lobby_teams?) && kind.lobby_teams? && %w(pending lobby).include?(session.status)

    session.players.reset
    kind.new(session).assign_team!(self)
  end
end
