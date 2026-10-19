# frozen_string_literal: true

# 효과 목록 하나 (상점 설정 > 효과 목록). kind: house(소속 카드) / character(칭호·데코·스킨), preset: 애니메이션 모양 (Game::Fx)
class GameEffect < ApplicationRecord
  KINDS = Game::Fx::SLOTS.keys.freeze

  validates :name, presence: true, length: { maximum: 30 }
  validates :description, length: { maximum: 300 }
  validates :kind, inclusion: { in: KINDS }
  validate :slot_and_preset_match

  default_scope { order(:position, :id) }

  # 처음에는 모든 모양을 하나씩 넣어 둔다 (지운 효과는 다시 만들지 않는다)
  def self.ensure_defaults!
    return if unscoped.exists?

    seed_missing!
  end

  # 아직 없는 모양만 더한다 (20261019000200_seed_all_game_effects)
  def self.seed_missing!
    existing = unscoped.pluck(:slot, :preset)
    position = unscoped.maximum(:position).to_i
    Game::Fx.defaults.each do |attributes|
      next if existing.include?([attributes[:slot], attributes[:preset]])

      position += 1
      create!(attributes.merge(position: position))
    end
  end

  # 관리 화면의 모양 고르기 값 'slot:preset' → 종류·자리·모양
  def look=(value)
    slot, preset = value.to_s.split(':', 2)
    self.slot = slot
    self.preset = preset
    self.kind = Game::Fx::SLOTS.find { |_, slots| slots.include?(slot) }&.first || kind
  end

  def look
    "#{slot}:#{preset}"
  end

  def character?
    kind == 'character'
  end

  def label
    "#{name} (#{I18n.t("admin.games.fx.slots.#{slot}")})"
  end

  private

  def slot_and_preset_match
    errors.add(:base, I18n.t('admin.games.fx.bad_look')) unless Game::Fx::SLOTS.fetch(kind, []).include?(slot) && Game::Fx::PRESETS.fetch(slot, {}).key?(preset)
  end
end
