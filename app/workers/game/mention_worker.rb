# frozen_string_literal: true

# 시스템 계정을 멘션한 툿의 게임 명령어 처리 (PostStatusService 가 넣는다)
class Game::MentionWorker
  include Sidekiq::Worker

  sidekiq_options queue: 'default', retry: 2

  def perform(status_id)
    status = Status.find_by(id: status_id)
    return if status.nil? || !Game::System.command_toot?(status)
    return if status.spoiler_text.start_with?(DmRoom::MEMBER_EVENT_PREFIX, DmRoom::TITLE_EVENT_PREFIX)

    Game::Engine.new(status).call
  end
end
