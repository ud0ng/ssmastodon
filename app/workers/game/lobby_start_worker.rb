# frozen_string_literal: true

# 대기방 카운트다운이 끝났을 때 시작한다. 그사이 누가 취소했거나 준비를 풀었으면 아무것도 하지 않는다 (start_at 이 달라졌으면 묵은 작업).
class Game::LobbyStartWorker
  include Sidekiq::Worker

  sidekiq_options queue: 'default', retry: 2

  def perform(session_id, start_at)
    session = GameSession.find_by(id: session_id)
    return if session.nil? || session.kind_class.nil?

    session.with_lock do
      next unless session.lobby? && session.state.dig('lobby', 'start_at') == start_at && Game::Lobby.all_ready?(session)

      Game::Lobby.start!(session)
    end
  end
end
