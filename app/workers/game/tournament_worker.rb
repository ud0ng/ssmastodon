# frozen_string_literal: true

# 토너먼트 경기를 예약한 시간에 연다. token 이 바뀌었으면(시간·선수 변경) 아무것도 하지 않는다.
class Game::TournamentWorker
  include Sidekiq::Worker

  sidekiq_options queue: 'default', retry: 2

  def perform(match_id, token)
    match = GameTournamentMatch.find_by(id: match_id)
    return if match.nil?

    match.with_lock do
      next unless match.status == 'ready' && match.schedule_token == token && match.tournament.status == 'running'

      Game::Tournament.open!(match)
    end
  end
end
