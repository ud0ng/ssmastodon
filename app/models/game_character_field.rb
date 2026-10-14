# frozen_string_literal: true

# 캐릭터 관리의 항목과 스탯
#   section profile → '항목' 탭: 이름, 종류(select 고르기 / text 글), 항목(고르기 목록), 설명
#   section stat    → '스탯' 탭: 이름, 유형
#       stat_type stat   → 스탯: 캐릭터마다 입력하는 값 (min_value ~ max_value)
#       stat_type status → 상태 수치: 스탯으로 자동 계산하는 값 (formula, 예: {{힘}}*5)
#     값은 캐릭터 stats 에 이름으로 저장 (상태 수치는 저장하지 않고 그때그때 계산)
class GameCharacterField < ApplicationRecord
  KINDS = %w(select text number).freeze
  EDITABLE_KINDS = %w(text select).freeze
  SECTIONS = %w(profile stat).freeze
  STAT_TYPES = %w(stat status).freeze

  DEFAULT_MIN = 0
  DEFAULT_MAX = 100

  # 처음 만들 때 넣는 스탯
  DEFAULTS = [
    { name: '힘', kind: 'number', section: 'stat', stat_type: 'stat', min_value: DEFAULT_MIN, max_value: DEFAULT_MAX },
    { name: '민첩', kind: 'number', section: 'stat', stat_type: 'stat', min_value: DEFAULT_MIN, max_value: DEFAULT_MAX },
    { name: '체력', kind: 'number', section: 'stat', stat_type: 'status', formula: '{{힘}}*5' },
  ].freeze

  validates :name, presence: true, length: { maximum: 30 }, uniqueness: true
  validates :kind, inclusion: { in: KINDS }
  validates :section, inclusion: { in: SECTIONS }
  validates :stat_type, inclusion: { in: STAT_TYPES }
  validates :description, length: { maximum: 500 }
  validates :min_value, :max_value, numericality: { only_integer: true }, allow_nil: true
  validate :stat_details, if: -> { section == 'stat' }

  default_scope { order(:position, :id) }
  scope :profile, -> { where(section: 'profile') }
  scope :stats, -> { where(section: 'stat') }
  scope :base_stats, -> { stats.where(stat_type: 'stat') }
  scope :statuses, -> { stats.where(stat_type: 'status') }

  def self.ensure_defaults!
    return if exists?

    DEFAULTS.each_with_index { |attributes, index| create!(attributes.merge(position: index)) }
  end

  def stat?
    section == 'stat' && stat_type == 'stat'
  end

  def status?
    section == 'stat' && stat_type == 'status'
  end

  def select?
    kind == 'select'
  end

  def min
    min_value || DEFAULT_MIN
  end

  def max
    max_value || DEFAULT_MAX
  end

  # 스탯 값을 최소~최대 안으로
  def clamp(value)
    value.to_i.clamp(min, [max, min].max)
  end

  # 고르기 항목 목록을 '이름|#색' 줄로
  def choices_text
    Array(choices).map { |choice| [choice['name'], choice['color'].presence].compact.join('|') }.join("\n")
  end

  def choices_text=(text)
    self.choices = text.to_s.lines.filter_map do |line|
      name, color = line.split('|', 2).map(&:strip)
      next if name.blank?

      { 'name' => name, 'color' => color.to_s.match?(/\A#\h{6}\z/) ? color : '' }
    end
  end

  def choice(name)
    Array(choices).find { |item| item['name'] == name }
  end

  private

  def stat_details
    if status?
      if formula.blank?
        errors.add(:formula, :blank)
      elsif !Game::Formula.valid?(formula)
        errors.add(:formula, I18n.t('admin.games.stats.formula_invalid'))
      else
        known = self.class.base_stats.where.not(id: id).pluck(:name)
        unknown = Game::Formula.names(formula) - known
        errors.add(:formula, I18n.t('admin.games.stats.formula_unknown', names: unknown.join(', '))) if unknown.any?
      end
    elsif min_value && max_value && min_value > max_value
      errors.add(:max_value, I18n.t('admin.games.stats.range_invalid'))
    end
  end
end
