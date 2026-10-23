# frozen_string_literal: true

# 툿이 저장되면 마니또 단어를 썼는지 본다 (Status after_create_commit, 웹·앱 모두). Game::Manito.record!
class Game::ManitoWorker
  include Sidekiq::Worker

  sidekiq_options queue: 'default', retry: 3

  def perform(status_id)
    Game::Manito.record!(Status.find_by(id: status_id))
  end
end
