# frozen_string_literal: true

# 상점 아이템. price 가 없으면 비매품 (보상·조사로만 얻는다).
#   use_target: stat(스탯 변동, 스탯 유형 '스탯'은 stat_minutes 동안 일시, '상태 수치'는 영구) / character(고른 캐릭터에게, 본인도 가능) / special(시스템 계정에 DM)
#   usable false → [사용] 불가, giftable false → [선물]·[양도] 불가.
#   stat_name/stat_value → [사용] 할 때 그 스탯이 stat_value 만큼 (정수나 주사위 1d10, -(1d6+3))
#   image → 아이템 그림 (상점 목록, 캐릭터 상세의 인벤토리 카드). 정사각형으로 잘라 쓴다
class GameShopItem < ApplicationRecord
  include Attachmentable

  VALUE_FORMAT = /\A\s*[+-]?\(?\s*(\d+\s*[dD]\s*\d+(\s*[+-]\s*\d+)?|\d+)\s*\)?\s*\z/
  IMAGE_MIME_TYPES = %w(image/png image/jpeg image/gif image/webp).freeze
  IMAGE_LIMIT = 2.megabytes
  USE_TARGETS = %w(stat character special).freeze
  SPECIAL_KINDS = %w(staff report bomb howler).freeze

  belongs_to :shop, class_name: 'GameShop', foreign_key: :game_shop_id, inverse_of: :items

  has_attached_file :image, styles: { small: { geometry: '256x256#', format: 'png', file_geometry_parser: FastGeometryParser } },
                            convert_options: { all: '-coalesce +profile "!icc,*" +set date:modify +set date:create +set date:timestamp' },
                            processors: [:lazy_thumbnail] # 서버 이미지에는 ImageMagick 이 없어서 libvips 로
  validates_attachment :image, content_type: { content_type: IMAGE_MIME_TYPES }, size: { less_than: IMAGE_LIMIT }

  # 인벤토리 카드에 쓸 그림: 이름(공백·대소문자 무시) → 상점 아이템
  def self.by_key
    where.not(image_file_name: nil).index_by { |item| Game::Wallet.key(item.name) }
  end

  validates :name, presence: true, length: { maximum: 50 }, uniqueness: true
  validates :description, length: { maximum: 1_000 }
  validates :price, numericality: { only_integer: true, greater_than_or_equal_to: 0 }, allow_nil: true
  validates :use_target, inclusion: { in: USE_TARGETS }
  validates :special_kind, inclusion: { in: SPECIAL_KINDS }
  validates :effect, length: { maximum: 1_000 }
  validates :wear_label, length: { maximum: 30 }
  validates :score_delta, :special_limit, numericality: { only_integer: true }
  validates :stat_minutes, numericality: { only_integer: true, greater_than: 0, less_than_or_equal_to: 60 * 24 * 30 }
  validates :stat_value, format: { with: VALUE_FORMAT }, if: -> { stat_name.present? }
  validate :stat_exists, if: -> { stat_name.present? }

  default_scope { order(:position, :id) }
  scope :for_sale, -> { where.not(price: nil) }

  def for_sale?
    !price.nil?
  end

  # [사용] 으로 바뀌는 스탯 (스탯·상태 수치 모두). 스탯(능력치)은 일시, 상태 수치는 영구 변동
  def stat_field
    return if stat_name.blank?

    GameCharacterField.stats.find { |field| Game::Wallet.key(field.name) == Game::Wallet.key(stat_name) }
  end

  def special?
    use_target == 'special'
  end

  def wearable?
    wear_label.present?
  end

  def temporary_stat?
    stat_field&.stat? ? true : false
  end

  private

  def stat_exists
    errors.add(:stat_name, I18n.t('admin.games.shop.unknown_stat', name: stat_name)) unless GameCharacterField.stats.exists?(name: stat_name)
  end
end
