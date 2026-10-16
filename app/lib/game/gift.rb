# frozen_string_literal: true

module Game
  # 웹 선물(아이템·재화) 알림: 받는 사람에게 시스템 계정 DM 으로 멘션 (앱에서도 알림이 가게).
  # 문구는 컨텐츠 설정 > 명령어 > 일반 문구 · 선물 알림 (msg_gift_item / msg_gift_money). 알림이 실패해도 선물은 그대로.
  module Gift
    module_function

    def notify(template, receiver, **values)
      Game::Poster.post(Game::Text.render(template, **values), mentions: [receiver], thread: nil, visibility: 'direct')
    rescue => e
      Rails.logger.warn { "gift notification failed: #{e.class} #{e.message}" }
      nil
    end
  end
end
