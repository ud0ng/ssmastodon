# frozen_string_literal: true

# 대진표의 한 칸(경기). 운영진이 컨텐츠·시간·선수를 정하고, 2라운드부터는 앞 경기 승자가 들어온다.
# status: waiting(준비 중) → ready(시간 예약됨) → playing → done, 응답 없음·무승부면 judging(운영진 판정)
class GameTournamentMatch < ApplicationRecord
  STATUSES = %w(waiting ready playing judging done).freeze

  belongs_to :tournament, class_name: 'GameTournament', foreign_key: :game_tournament_id, inverse_of: :matches
  belongs_to :player_a, class_name: 'Account', optional: true
  belongs_to :player_b, class_name: 'Account', optional: true
  belongs_to :winner, class_name: 'Account', optional: true
  belongs_to :session, class_name: 'GameSession', foreign_key: :game_session_id, optional: true

  validates :status, inclusion: { in: STATUSES }
  validates :kind, inclusion: { in: ->(_) { Game::Kinds.keys } }, allow_blank: true

  def players
    [player_a, player_b].compact
  end

  def ready_to_schedule?
    player_a.present? && player_b.present? && player_a_id != player_b_id && kind.present? && scheduled_at.present?
  end

  def kind_name
    kind.present? ? Game::Kinds.fetch(kind).display_name : nil
  end

  # 이 경기 승자가 들어갈 다음 경기
  def next_match
    tournament.matches.find { |match| match.round == round + 1 && match.position == position / 2 }
  end

  # 예약 작업이 아직 유효한지 (시간이나 선수가 바뀌면 예전 작업은 무시)
  def schedule_token
    "#{id}:#{scheduled_at&.to_i}:#{player_a_id}:#{player_b_id}:#{kind}"
  end
end
