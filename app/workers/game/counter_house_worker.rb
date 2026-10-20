# frozen_string_literal: true

# 소속 점수에 영향을 주는 누적 수치(벌점·상점 등)를 정한 시간 간격마다 소속 점수에 반영한다 (매분 확인)
class Game::CounterHouseWorker
  include Sidekiq::Worker

  sidekiq_options queue: 'scheduler', retry: 0

  def perform
    GameCounter.where(affects_house: true).each(&:apply_house_points!)
  end
end
