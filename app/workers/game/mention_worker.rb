# frozen_string_literal: true

# 시스템 계정을 멘션한 툿의 게임 명령어 처리 (PostStatusService 가 넣는다)
class Game::MentionWorker
  include Sidekiq::Worker

  sidekiq_options queue: 'default', retry: 2

  # 같은 툿을 두 번 처리하지 않게 먼저 잡은 쪽만 처리한다 (웹 버튼은 요청 안에서 바로 처리하고, 워커는 건너뛴다)
  def self.claim?(status_id)
    Rails.cache.write("game:handled:#{status_id}", 1, unless_exist: true, expires_in: 1.hour) ? true : false
  end

  def perform(status_id)
    status = Status.find_by(id: status_id)
    return if status.nil? || !Game::System.command_toot?(status)
    return unless self.class.claim?(status_id)
    return if status.spoiler_text.start_with?(DmRoom::MEMBER_EVENT_PREFIX, DmRoom::TITLE_EVENT_PREFIX)

    Game::Engine.new(status).call
  end
end
