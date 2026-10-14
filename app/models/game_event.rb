# frozen_string_literal: true

# 시스템 계정의 컨텐츠 툿 하나와 그때의 컨텐츠 상태 (Game::Card 가 만든 payload). PC 웹이 카드로 그린다.
class GameEvent < ApplicationRecord
  belongs_to :session, class_name: 'GameSession', foreign_key: :game_session_id, inverse_of: :events, optional: true
  belongs_to :status, inverse_of: :game_event

  # 웹에 보낼 카드: 진행 중인 판의 가장 최근 툿이면 지금 상태로 다시 만든다
  # (비밀의방 고발처럼 툿 없이 바뀌는 것, 수업 참가자 등을 바로 보이게)
  def current_payload
    return payload.merge('live' => false) unless live?

    Game::Card.build(session).merge('live' => true)
  rescue => e
    Rails.logger.warn { "GameEvent##{id} rebuild failed: #{e.class} #{e.message}" }
    payload.merge('live' => true)
  end

  # 이 툿이 아직 진행 중인 판의 가장 최근 툿인가 (그때만 웹에 행동 버튼을 보여 준다)
  def live?
    session.present? && session.open? && session.events.maximum(:id) == id
  end
end
