# frozen_string_literal: true

# 시스템 계정의 컨텐츠 툿 하나와 그때의 컨텐츠 상태 (Game::Card 가 만든 payload). PC 웹이 카드로 그린다.
class GameEvent < ApplicationRecord
  belongs_to :session, class_name: 'GameSession', foreign_key: :game_session_id, inverse_of: :events
  belongs_to :status, inverse_of: :game_event

  # 이 툿이 아직 진행 중인 판의 가장 최근 툿인가 (그때만 웹에 행동 버튼을 보여 준다)
  def live?
    session.open? && session.events.maximum(:id) == id
  end
end
