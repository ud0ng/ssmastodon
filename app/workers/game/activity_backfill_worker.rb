# frozen_string_literal: true

# 과거 툿 활동을 스냅샷으로 한꺼번에 올린다 (관리 > 캐릭터 관리 > 활동의 [과거 기록 올리기], rake game:activity_backfill 과 같다)
class Game::ActivityBackfillWorker
  include Sidekiq::Worker

  sidekiq_options queue: 'default', retry: 1, lock: :until_executed, lock_ttl: 30.minutes.to_i

  def perform(force = false)
    Game::ActivitySnapshot.catch_up!(force: force)
  end
end
