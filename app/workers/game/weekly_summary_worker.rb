# frozen_string_literal: true

# 매시 정각에 확인해서, 컨텐츠 공통 설정의 요일·시각이면 주간 결산 툿을 올린다 (주마다 한 번)
class Game::WeeklySummaryWorker
  include Sidekiq::Worker

  sidekiq_options queue: 'scheduler', retry: 0

  def perform
    Game::Summary.weekly! if Game::Summary.weekly_due?
  end
end
