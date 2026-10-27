# frozen_string_literal: true

# 누적 수치 (상점 설정 > 누적 수치 목록). 기본은 '벌점'(최대 5) ↔ '상점'(최대 5).
# 아이템 효과(특수 > 누적 수치)로 고른 캐릭터에게 더하고(+)·빼며(-), 누적 횟수에 닿으면 규칙(GameCounterRule)의 효과가 붙는다.
# 캐릭터마다 횟수는 game_characters.counters { 수치 번호 => 누적치 }. 누적치는 최대 누적치를 넘어도 계속 올라간다.
#   상성 수치(opposite)는 서로 상쇄한다: 결과값 = 내 누적치 - 상성 누적치 (0 아래로는 안 내려감)
#   예) 벌점 5회·상점 2회 → 벌점 3회, 상점 0회
# 소속 점수에 영향(affects_house)을 켜면 house_interval_minutes 마다 소속 캐릭터의 결과값 × house_amount 만큼 소속 점수가 바뀐다 (예: 1시간, -2 → 벌점 4회면 시간마다 -8).
#   수치마다 따로 켜고 끈다 (상성 수치와 상관없이, 간격·점수도 수치마다 따로).
class GameCounter < ApplicationRecord
  DEFAULTS = [%w(벌점 상점), %w(상점 벌점)].freeze
  DEFAULT_MAX = 5
  MAX_CATCH_UP = 24 # 서버가 멈췄다 돌아와도 한 번에 반영하는 최대 간격 수

  has_many :rules, -> { order(:at_max, :threshold, :id) }, class_name: 'GameCounterRule', dependent: :destroy, inverse_of: :counter
  has_many :logs, class_name: 'GameCounterLog', dependent: :delete_all, inverse_of: :counter
  belongs_to :opposite, class_name: 'GameCounter', optional: true

  validates :name, presence: true, length: { maximum: 20 }, uniqueness: true
  validates :max_count, numericality: { only_integer: true, greater_than: 0, allow_nil: true }
  validates :house_interval_minutes, numericality: { only_integer: true, greater_than: 0, less_than_or_equal_to: 60 * 24 * 30 }
  validates :house_amount, numericality: { only_integer: true }
  validate :opposite_is_another

  default_scope { order(:position, :id) }

  after_save :pair_opposite
  after_destroy { GameCounter.unscoped.where(opposite_id: id).update_all(opposite_id: nil) } # rubocop:disable Rails/SkipsModelValidations

  def self.ensure_defaults!
    return if unscoped.exists?

    DEFAULTS.each_with_index { |(name, _), index| create!(name: name, max_count: DEFAULT_MAX, position: index) }
    DEFAULTS.each { |name, opposite| find_by!(name: name).update!(opposite: find_by!(name: opposite)) }
  end

  # 누적치 (상성으로 깎기 전)
  def raw_for(character)
    character.counters.to_h[id.to_s].to_i
  end

  # 결과값: 누적치에서 상성 누적치를 상쇄한 최종값
  def net_for(character)
    [raw_for(character) - (opposite&.raw_for(character) || 0), 0].max
  end

  alias count_for net_for

  # 캐릭터의 누적치를 바꾸고(0 아래로는 안 내려감), 이 수치와 상성 수치의 누적 효과를 맞춘다.
  # [전, 후(결과값), 붙은 효과 안내] 를 돌려주고 기록(GameCounterLog)을 남긴다
  def add!(character, delta, item: nil, reason: nil, actor: nil, source: nil)
    character.reload
    related = [self, opposite].compact
    before = related.to_h { |counter| [counter.id, counter.net_for(character)] }
    raw_before = raw_for(character)
    raw_after = [raw_before + delta.to_i, 0].max
    character.update!(counters: character.counters.to_h.merge(id.to_s => raw_after))

    notes = related.flat_map { |counter| counter.sync_rules!(character, before[counter.id], counter.net_for(character), item: item) }
    after = net_for(character)
    logs.create!(account_id: character.account_id, delta: raw_after - raw_before, raw: raw_after, net: after, reason: (reason || item).to_s.truncate(200), actor: actor.to_s, source_account_id: source&.id)
    [before[id], after, notes]
  end

  # 정한 간격이 지났으면 소속 캐릭터마다 결과값 × 점수를 소속 점수에 넣는다 (결과값 0 이면 건너뜀). 처음 켠 때부터 센다
  def apply_house_points!(now = Time.current)
    return unless affects_house

    return update_columns(house_applied_at: now) if house_applied_at.nil? # rubocop:disable Rails/SkipsModelValidations

    interval = house_interval_minutes.minutes
    ticks = ((now - house_applied_at) / interval).floor.clamp(0, MAX_CATCH_UP)
    return if ticks.zero?
    # 시즌 종료 상태: 점수는 넣지 않고 반영 시각만 넘긴다 (새 시즌에 밀린 만큼 한꺼번에 들어가지 않게)
    return update_columns(house_applied_at: house_applied_at + (interval * ticks)) if GameSeason.closed? # rubocop:disable Rails/SkipsModelValidations

    GameCharacter.visible.includes(:account).each do |character|
      value = net_for(character)
      house = character.group
      next if value.zero? || house.nil? || house_amount.zero?

      GameHousePoint.create!(house: house, account: character.account, counter: self, amount: value * house_amount * ticks,
                             reason: "#{name} #{value}회#{ticks > 1 ? " × #{ticks}" : ''}")
    end
    update_columns(house_applied_at: house_applied_at + (interval * ticks)) # rubocop:disable Rails/SkipsModelValidations
  end

  # 결과값이 before → after 로 바뀐 것에 맞춰 누적 효과를 붙이거나 거둔다. 안내 문구 목록을 돌려준다
  def sync_rules!(character, before, after, item: nil)
    rules.includes(:effect).filter_map { |rule| rule.settle!(character, before, after, item: item) }
  end

  private

  def opposite_is_another
    errors.add(:opposite_id, :invalid) if opposite_id.present? && opposite_id == id
  end

  # 상성은 서로 짝: A 의 상성을 B 로 하면 B 의 상성도 A. 짝이 바뀌면 옛 짝은 풀린다
  def pair_opposite
    return unless saved_change_to_opposite_id?

    old_id = opposite_id_before_last_save
    GameCounter.unscoped.where(id: old_id, opposite_id: id).update_all(opposite_id: nil) if old_id # rubocop:disable Rails/SkipsModelValidations
    return if opposite_id.nil?

    GameCounter.unscoped.where(opposite_id: opposite_id).where.not(id: id).update_all(opposite_id: nil) # rubocop:disable Rails/SkipsModelValidations
    GameCounter.unscoped.where(id: opposite_id).where('opposite_id IS DISTINCT FROM ?', id).update_all(opposite_id: id) # rubocop:disable Rails/SkipsModelValidations
  end
end
