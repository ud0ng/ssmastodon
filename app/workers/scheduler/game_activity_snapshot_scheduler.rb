# frozen_string_literal: true

# 한국 시간 00시 5분: 어제 하루치 활동 스냅샷을 툿에서 다시 계산해 맞추고 빠진 날을 채운다 (Game::ActivitySnapshot.catch_up!)
class Scheduler::GameActivitySnapshotScheduler
  include Sidekiq::Worker

  sidekiq_options retry: 0, lock: :until_executed, lock_ttl: 1.hour.to_i

  def perform
    Game::ActivitySnapshot.catch_up!
  end
end
