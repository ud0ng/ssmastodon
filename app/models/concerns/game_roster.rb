# frozen_string_literal: true

# 회원이 늘거나 줄 때마다 캐릭터 명단을 맞춘다 (새 회원 추가, 탈퇴 회원 삭제, 정지는 명단에서 숨김)
module GameRoster
  extend ActiveSupport::Concern

  included do
    # 같은 메서드로 after_commit 을 두 번 걸면 Rails 가 마지막 것만 남기므로 하나로 건다
    after_commit :sync_game_roster, if: :game_roster_changed?
  end

  private

  # 회원(User)은 생기거나 지워지거나 승인·메일 확인될 때, 계정은 정지·정지 해제될 때
  def game_roster_changed?
    watched = is_a?(User) ? %w(approved confirmed_at) : %w(suspended_at anonymized_at)
    return is_a?(User) if destroyed? || previously_new_record?

    previous_changes.keys.intersect?(watched)
  end

  def sync_game_roster
    Game::RosterSyncWorker.perform_async
  rescue StandardError => e
    Rails.logger.warn { "Game::RosterSyncWorker enqueue failed: #{e.class} #{e.message}" }
  end
end
