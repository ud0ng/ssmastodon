# frozen_string_literal: true

# 툿이 저장되면 마니또 단어를 썼는지 보고(Status after_create_commit, 웹·앱 모두, Game::Manito.record!),
# 지우면 그 툿으로 센 사용·보상을 되돌린다 (Status#discard_with_reblogs, Game::Manito.revert!)
class Game::ManitoWorker
  include Sidekiq::Worker

  sidekiq_options queue: 'default', retry: 3

  def perform(status_id, action = 'record')
    return Game::Manito.revert!(status_id) if action == 'revert'

    Game::Manito.record!(Status.find_by(id: status_id))
  end
end
