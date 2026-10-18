# frozen_string_literal: true

# 지운 판의 툿을 하나씩 지운다 (알림·타임라인·DM 대화에서도 함께 사라진다)
class Game::StatusCleanupWorker
  include Sidekiq::Worker

  sidekiq_options queue: 'default', retry: 2

  def perform(status_ids)
    Status.unscoped.where(id: status_ids).find_each do |status|
      RemoveStatusService.new.call(status, redraft: false)
    rescue => e
      Rails.logger.warn { "Game::StatusCleanupWorker status #{status.id}: #{e.class} #{e.message}" }
    end
  end
end
