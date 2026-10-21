# frozen_string_literal: true

# 웹 전용 컨텐츠의 진행 메시지 (툿이 아니라서 앱에는 나가지 않는다). account 가 있으면 그 사람에게만 보이는 비밀 안내.
class GameMessage < ApplicationRecord
  belongs_to :session, class_name: 'GameSession', foreign_key: :game_session_id, inverse_of: :messages
  belongs_to :account, optional: true

  belongs_to :author, class_name: 'Account', optional: true

  scope :visible_to, ->(account) { where(account_id: [nil, account.id]) }

  def chat?
    kind == 'chat'
  end

  def secret?
    account_id.present?
  end

  # 웹에 보낼 카드: 진행 중인 판의 가장 최근 공개 메시지면 지금 상태로 다시 만든다 (GameEvent#current_payload 와 같은 규칙)
  def current_payload
    return payload.merge('live' => false) if secret? || payload.blank? || !live?

    Game::Card.build(session).merge('live' => true)
  rescue => e
    Rails.logger.warn { "GameMessage##{id} rebuild failed: #{e.class} #{e.message}" }
    payload.merge('live' => true)
  end

  def live?
    session.open? && session.messages.where(account_id: nil).maximum(:id) == id
  end
end
