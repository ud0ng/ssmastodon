# frozen_string_literal: true

# 상점 아이템. price 가 없으면 비매품 (보상·조사로만 얻는다).
#   옵션: usable [사용] 가능, giftable [선물]·[양도] 가능, permanent [영구] (사용해도 사라지지 않는다)
#   effect → 효과 설명 (사용자에게 보이는 글), item_effects → 사용할 때 실제로 일어나는 효과 여러 개 (Game::ItemEffects)
#   image → 아이템 이미지 (상점 목록, 인벤토리 카드). 정사각형으로 잘라 쓴다
class GameShopItem < ApplicationRecord
  include Attachmentable

  VALUE_FORMAT = /\A\s*[+-]?\(?\s*(\d+\s*[dD]\s*\d+(\s*[+-]\s*\d+)?|\d+)\s*\)?\s*\z/
  IMAGE_MIME_TYPES = %w(image/png image/jpeg image/gif image/webp).freeze
  IMAGE_LIMIT = 2.megabytes

  # 예전 한 칸짜리 사용 설정 (item_effects 로 옮겼다, 20261019000100_create_game_effects)
  self.ignored_columns += %w(use_target stat_name stat_value stat_minutes special_kind score_delta special_limit allow_random wear_label)

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
  validates :effect, length: { maximum: 1_000 }
  validates :price, numericality: { only_integer: true, greater_than_or_equal_to: 0 }, allow_nil: true
  validate :item_effects_valid

  default_scope { order(:position, :id) }
  scope :for_sale, -> { where.not(price: nil) }

  def for_sale?
    !price.nil?
  end

  # 이름(공백·대소문자 무시)으로 찾은 아이템이 '같은 소속에 사용 불가능' 옵션인가 (켜면 같은 소속에 사용·양도·선물이 안 된다)
  def self.blocks_same_house?(name)
    key = Game::Wallet.key(name)
    all.any? { |item| item.block_same_house && Game::Wallet.key(item.name) == key }
  end

  def item_effects=(value)
    super(Game::ItemEffects.normalize(value))
  end

  def effects_list
    Array(item_effects)
  end

  def needs_character?
    Game::ItemEffects.needs_character?(effects_list)
  end

  def needs_house?
    Game::ItemEffects.needs_house?(effects_list)
  end

  def needs_text?
    Game::ItemEffects.needs_text?(effects_list)
  end

  def summary
    Game::ItemEffects.summary(effects_list)
  end

  private

  def item_effects_valid
    Game::ItemEffects.errors(effects_list).each { |message| errors.add(:base, message) }
  end
end
