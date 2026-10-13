# frozen_string_literal: true

# 게임 시간 제한 (수락 대기, 턴 대기). token 이 바뀌었으면(그사이 진행됨) 아무것도 하지 않는다.
class Game::TimeoutWorker
  include Sidekiq::Worker

  sidekiq_options queue: 'default', retry: 2

  def perform(session_id, token)
    session = GameSession.find_by(id: session_id)
    return if session.nil?

    session.with_lock do
      next unless session.open? && session.deadline_token == token && session.deadline_at&.past?

      if session.status == 'pending'
        common = Game::Config.for('common')
        session.update!(status: 'cancelled', finished_at: Time.now.utc, deadline_at: nil)
        Game::Poster.to_session(session, Game::Text.render(common['msg_expired'], game: session.kind_class.display_name, minutes: common['invite_minutes']))
      else
        session.kind_class.new(session).timeout!
      end
    end
  end
end
