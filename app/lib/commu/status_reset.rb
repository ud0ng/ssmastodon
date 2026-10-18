# frozen_string_literal: true

module Commu
  # 테스트 데이터 정리용: 모든 툿(DM 포함)과 거기에 딸린 것만 지운다. 계정·설정·재화·인벤토리·소속 점수·게임 전적(판 기록)은 그대로 둔다.
  # (rake commu:reset_statuses CONFIRM=yes)
  module StatusReset
    extend Redisable

    # 툿에 매달린 알림 (팔로우 알림 등은 남긴다)
    STATUS_NOTIFICATIONS = %w(Status Mention Favourite Poll Quote).freeze

    module_function

    def call
      # 툿에 붙은 이미지·파일은 툿과 함께 지운다 (툿이 지워지면 파일만 남는다)
      MediaAttachment.where.not(status_id: nil).find_each(&:destroy)

      ActiveRecord::Base.transaction do
        # 판의 스레드가 사라지므로 진행 중인 컨텐츠는 취소하고, 툿에 매달린 카드·스레드 표시를 비운다
        GameSession.open.update_all(status: 'cancelled', finished_at: Time.now.utc, deadline_at: nil)
        GameEvent.delete_all
        GameSession.update_all(root_status_id: nil, last_status_id: nil)
        GamePlayer.update_all("state = state - 'dm_status_id'")

        Notification.where(activity_type: STATUS_NOTIFICATIONS).delete_all
        AccountConversation.delete_all
        Conversation.delete_all
        Status.unscoped.in_batches(of: 1000).delete_all # 나머지(멘션·즐겨찾기·북마크·고정·통계…)는 DB 가 같이 지운다

        AccountStat.update_all(statuses_count: 0, last_status_at: nil)
      end

      clear_feeds
    end

    # 홈·리스트·공개 타임라인 캐시 (Redis)
    def clear_feeds
      keys = redis.scan_each(match: 'feed:*').to_a
      redis.del(*keys) if keys.any?
    rescue StandardError => e
      Rails.logger.warn { "Commu::StatusReset feeds: #{e.class} #{e.message}" }
    end
  end
end
