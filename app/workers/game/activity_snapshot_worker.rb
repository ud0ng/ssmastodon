# frozen_string_literal: true

# 툿이 저장되면 오늘의 활동 스냅샷에 쌓는다 (Status after_create_commit, 웹·앱 모두). Game::ActivitySnapshot.record!
class Game::ActivitySnapshotWorker
  include Sidekiq::Worker

  sidekiq_options queue: 'default', retry: 3

  def perform(status_id)
    Game::ActivitySnapshot.record!(status_id)
  end
end
