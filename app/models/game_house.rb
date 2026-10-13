# frozen_string_literal: true

# 기숙사 (관리 > 게임 > 기숙사). 게임에서 이기면 기숙사 점수를 받는다.
class GameHouse < ApplicationRecord
  DEFAULTS = [
    { name: '그리핀도르', emoji: '🦁', color: '#ae0001' },
    { name: '슬리데린', emoji: '🐍', color: '#2a623d' },
    { name: '래번클로', emoji: '🦅', color: '#222f5b' },
    { name: '후플푸프', emoji: '🦡', color: '#ecb939' },
  ].freeze

  has_many :characters, class_name: 'GameCharacter', dependent: :nullify
  has_many :points, class_name: 'GameHousePoint', dependent: :destroy

  validates :name, presence: true, length: { maximum: 30 }
  validates :emoji, length: { maximum: 16 }
  validates :color, format: { with: /\A(#[0-9a-fA-F]{6})?\z/ }

  default_scope { order(:position, :id) }

  def self.ensure_defaults!
    return if exists?

    DEFAULTS.each_with_index { |attributes, index| create!(attributes.merge(position: index)) }
  end

  def total
    points.sum(:amount)
  end

  def label
    [emoji.presence, name].compact.join(' ')
  end
end
