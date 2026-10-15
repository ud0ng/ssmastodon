# frozen_string_literal: true

# 시즌 (캐릭터 관리 > 소속). 진행 중인 시즌은 하나만.
# 소속 점수(GameHouse#total)는 마지막으로 끝난 시즌 뒤에 쌓인 점수만 센다 → 시즌을 끝내면 점수가 0부터 다시.
class GameSeason < ApplicationRecord
  STATUSES = %w(running finished).freeze

  validates :name, presence: true, length: { maximum: 50 }
  validates :status, inclusion: { in: STATUSES }
  validate :one_running, if: :running?
  validate :period_order

  scope :running, -> { where(status: 'running') }
  scope :finished, -> { where(status: 'finished') }

  def self.current
    running.order(:id).last
  end

  # 소속 점수를 세기 시작하는 때 (마지막으로 끝난 시즌의 종료 시각)
  def self.points_since
    finished.maximum(:finished_at)
  end

  def running?
    status == 'running'
  end

  def period
    [starts_on, ends_on].compact.map { |date| I18n.l(date, format: :short) }.join(' ~ ')
  end

  private

  def one_running
    errors.add(:base, I18n.t('admin.games.seasons.already_running')) if self.class.running.where.not(id: id).exists?
  end

  def period_order
    errors.add(:ends_on, I18n.t('admin.games.seasons.bad_period')) if starts_on && ends_on && ends_on < starts_on
  end
end
