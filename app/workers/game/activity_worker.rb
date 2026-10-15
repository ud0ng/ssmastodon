# frozen_string_literal: true

# 툿이 저장되면 툿 보상을 확인한다 (Status after_create_commit, 웹·앱 모두)
class Game::ActivityWorker
  include Sidekiq::Worker

  sidekiq_options queue: 'default', retry: 2, lock: :until_executed, lock_ttl: 1.minute.to_i

  def perform(account_id)
    account = Account.find_by(id: account_id)
    Game::Activity.reward!(account) if account&.local?
  end
end
