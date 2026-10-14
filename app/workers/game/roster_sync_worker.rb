# frozen_string_literal: true

# 캐릭터 명단을 회원 목록과 맞춘다 (GameRoster 가 회원 변동 때 넣는다)
class Game::RosterSyncWorker
  include Sidekiq::Worker

  sidekiq_options queue: 'default', retry: 1

  def perform
    GameCharacter.sync!
  end
end
