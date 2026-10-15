# frozen_string_literal: true

# 소속: 기숙사(category house)와 진영(category faction). 캐릭터는 둘 다 가질 수 있고,
# 공통 설정의 '점수 단위'로 고른 쪽만 점수·토너먼트·모래시계·결산에 쓴다 (다른 쪽 점수는 보관).
class GameHouse < ApplicationRecord
  CATEGORIES = %w(house faction).freeze

  DEFAULTS = {
    'house' => [
      { name: '그리핀도르', color: '#ae0001' },
      { name: '슬리데린', color: '#2a623d' },
      { name: '래번클로', color: '#222f5b' },
      { name: '후플푸프', color: '#ecb939' },
    ],
    'faction' => [
      { name: '불사조 기사단', color: '#b7410e' },
      { name: '죽음을 먹는 자들', color: '#4f7a52' },
    ],
  }.freeze

  has_many :characters, class_name: 'GameCharacter', dependent: :nullify
  has_many :faction_characters, class_name: 'GameCharacter', foreign_key: :game_faction_id, dependent: :nullify, inverse_of: :faction
  has_many :points, class_name: 'GameHousePoint', dependent: :destroy

  validates :name, presence: true, length: { maximum: 30 }
  validates :emoji, length: { maximum: 16 }
  validates :color, format: { with: /\A(#[0-9a-fA-F]{6})?\z/ }
  validates :category, inclusion: { in: CATEGORIES }

  default_scope { order(:position, :id) }
  scope :houses, -> { where(category: 'house') }
  scope :factions, -> { where(category: 'faction') }

  class << self
    # 점수 단위 (공통 설정 group_mode)
    def mode
      Game::Config.for('common')['group_mode'] == 'faction' ? 'faction' : 'house'
    end

    def faction_mode?
      mode == 'faction'
    end

    # 지금 점수를 모으는 소속 목록
    def active
      where(category: mode)
    end

    def ensure_defaults!
      CATEGORIES.each do |category|
        next if where(category: category).exists?

        DEFAULTS[category].each_with_index { |attributes, index| create!(attributes.merge(position: index, category: category)) }
      end
    end
  end

  def faction?
    category == 'faction'
  end

  # 이번 시즌 점수 (마지막으로 끝난 시즌 뒤에 쌓인 점수)
  def total
    since = GameSeason.points_since
    (since ? points.where(created_at: since..) : points).sum(:amount)
  end

  # 이름만 보인다 (이모지는 쓰지 않는다)
  def label
    name
  end
end
