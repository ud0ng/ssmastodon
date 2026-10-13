# frozen_string_literal: true

# 캐릭터 명단 항목 (관리 > 캐릭터 명단 > 항목 설정). 기숙사·학년 말고 운영진이 더하는 값.
#   kind:  select(고르기, 예: 진영) / text(글) / number(숫자)
#   section: profile(정보) / stat(전투 스탯 — 값은 캐릭터 stats 에 이름으로 저장)
class GameCharacterField < ApplicationRecord
  KINDS = %w(select text number).freeze
  SECTIONS = %w(profile stat).freeze

  # 처음 만들 때 넣는 항목
  DEFAULTS = [
    { name: '진영', kind: 'select', section: 'profile', choices: [{ 'name' => '불사조 기사단', 'color' => '#b7410e' }, { 'name' => '죽음을 먹는 자들', 'color' => '#4f7a52' }] },
    { name: '체력', kind: 'number', section: 'stat' },
    { name: '공격', kind: 'number', section: 'stat' },
    { name: '방어', kind: 'number', section: 'stat' },
  ].freeze

  validates :name, presence: true, length: { maximum: 30 }, uniqueness: true
  validates :kind, inclusion: { in: KINDS }
  validates :section, inclusion: { in: SECTIONS }

  default_scope { order(:position, :id) }
  scope :profile, -> { where(section: 'profile') }
  scope :stats, -> { where(section: 'stat') }

  def self.ensure_defaults!
    return if exists?

    DEFAULTS.each_with_index { |attributes, index| create!(attributes.merge(position: index)) }
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

  def select?
    kind == 'select'
  end
end
