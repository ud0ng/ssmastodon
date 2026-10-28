# frozen_string_literal: true

# 시즌 (캐릭터 관리 > 소속). 진행 중인 시즌은 하나만.
#   시작일이 아직 안 된 시즌은 '예정'(upcoming?)이라 시작일(한국 시간) 0시가 되기 전까지는 진행 중으로 치지 않는다 (current 가 아니고, 그동안은 시즌 종료 상태 그대로).
# 소속 점수(GameHouse#total)는 그 시즌의 점수만 센다.
#   시즌 종료(closed?): 진행 중인 시즌이 없고 끝난 시즌이 있을 때. 이때는 소속 점수를 더 얻지 못하고(컨텐츠·마니또·아이템·누적 수치·토너먼트 모두,
#   운영진 직접 조정만 된다), 새 시즌을 시작할 때까지 끝난 시즌의 최종 점수·순위가 보인다. 새 시즌을 만들면 0부터.
class GameSeason < ApplicationRecord
  STATUSES = %w(running finished).freeze

  validates :name, presence: true, length: { maximum: 50 }
  validates :status, inclusion: { in: STATUSES }
  validate :one_running, if: :running?
  validate :period_order

  scope :running, -> { where(status: 'running') }
  # 시작일이 없거나 이미 시작일이 된 진행 중 시즌 (예정인 시즌은 빠진다)
  scope :started, -> { running.where(starts_on: nil).or(running.where(starts_on: ..today)) }
  scope :upcoming, -> { running.where(starts_on: today.next..) }
  scope :finished, -> { where(status: 'finished') }

  # 오늘(한국 시간 날짜)
  def self.today
    Time.current.in_time_zone(Game::ActivitySnapshot::ZONE).to_date
  end

  def self.current
    started.order(:id).last
  end

  # 시즌 종료 상태: 진행 중인 시즌이 없고 끝난 시즌이 있다 (소속 점수를 얻지 못한다)
  def self.closed?
    current.nil? && finished.exists?
  end

  # 소속 점수를 보여 줄 시즌: 진행 중인 시즌, 시즌 종료 상태면 마지막으로 끝난 시즌 (시즌이 없으면 nil)
  def self.points_season
    current || finished.where.not(finished_at: nil).order(:finished_at).last
  end

  # 소속 점수를 세기 시작하는 때: 그 시즌 앞에 끝난 시즌의 종료 시각과 그 시즌을 만든 때 중 늦은 쪽
  # (첫 시즌이면 nil = 처음부터 전부. 시즌 종료 상태에서 새 시즌을 만들면 그때부터 0)
  def self.points_since
    season = points_season
    return if season.nil?

    before = finished.where.not(id: season.id).where(finished_at: ...(season.finished_at || Time.current)).maximum(:finished_at)
    before && [before, season.created_at, season.starts_at].compact.max
  end

  # 시즌마다 활동을 세는 날짜 범위 [[시즌, 시작일, 종료일]] (오래된 시즌부터). 시작·종료 날짜를 안 적은 시즌은 앞 시즌이 끝난 다음 날부터,
  # 끝난 시즌은 끝낸 날까지. 진행 중이고 끝 날짜가 없으면 종료일이 nil (오늘 쓰는 툿까지 실시간으로 쌓인다)
  def self.dated
    seasons = order(:id).to_a
    seasons.each_with_index.map do |season, index|
      from = season.starts_on || end_day(index.positive? ? seasons[index - 1] : nil)&.next
      to = season.ends_on || (season.finished? ? end_day(season) : nil)
      [season, from, to]
    end
  end

  def self.end_day(season)
    return if season.nil?

    season.ends_on || season.finished_at&.in_time_zone(Game::ActivitySnapshot::ZONE)&.to_date
  end

  def running?
    status == 'running'
  end

  def finished?
    status == 'finished'
  end

  # 시작일이 아직 안 된 시즌 (시작일 0시가 되면 저절로 진행 중이 된다)
  def upcoming?
    running? && starts_on.present? && starts_on > self.class.today
  end

  # 시작일 0시 (한국 시간). 시작일을 안 적었으면 nil
  def starts_at
    starts_on&.in_time_zone(Game::ActivitySnapshot::ZONE)&.beginning_of_day
  end

  # 목록에 보일 상태: 예정 / 진행 중 / 끝남
  def display_status
    upcoming? ? 'upcoming' : status
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
