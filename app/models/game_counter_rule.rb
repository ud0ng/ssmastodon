# frozen_string_literal: true

# 누적 수치의 누적 효과: 결과값이 threshold(누적 횟수)에 닿으면 효과 목록의 effect 를 minutes 동안(permanent 면 영구) 붙인다.
#   at_max 면 누적 횟수 대신 '최대치'(수치의 max_count): 최대치에 닿으면 영구 효과가 붙고, 최대치 밑으로 내려가면 거둬진다.
#   최대치에서 내려와 결과값이 어떤 누적 횟수와 딱 같아지면 그 횟수의 효과가 다시 붙는다.
# 캐릭터 효과(칭호·데코)는 그 캐릭터에게, 소속 효과는 그 캐릭터의 소속 카드에.
class GameCounterRule < ApplicationRecord
  PERMANENT_YEARS = 100

  belongs_to :counter, class_name: 'GameCounter', foreign_key: :game_counter_id, inverse_of: :rules
  belongs_to :effect, class_name: 'GameEffect', foreign_key: :game_effect_id, optional: true

  before_validation :normalize_max
  validates :threshold, numericality: { only_integer: true, greater_than: 0 }
  validates :minutes, numericality: { only_integer: true, greater_than: 0, less_than_or_equal_to: Game::ItemEffects::MAX_MINUTES }
  validates :game_effect_id, presence: true
  validate :max_count_given, if: :at_max

  # 효과를 맞춘다. 새로 붙었으면 안내 한 줄 (붙일 곳이 없거나 바뀐 게 없으면 nil)
  def settle!(character, before, after, item: nil)
    if at_max
      max = counter.max_count
      return if max.nil?

      if before < max && after >= max then apply!(character, item: item)
      elsif before >= max && after < max then remove!(character)
      end
    elsif before < threshold && after >= threshold
      apply!(character, item: item)
    elsif after < before && after == threshold && counter.max_count && before >= counter.max_count
      apply!(character, item: item)
    end
  end

  def apply!(character, item: nil)
    return if effect.nil?

    remove!(character)
    entry = Game::Fx.entry(effect, minutes, permanent: permanent).merge('rule' => id, 'character' => character.account_id)
    duration = permanent ? '영구' : "#{Game::ItemEffects.duration(minutes)} 동안"
    label = at_max ? '최대치' : "#{threshold}회 누적"
    if effect.kind == 'house'
      house = character.group
      return if house.nil?

      house.update!(effects: Game::Fx.active(house.effects) + [entry])
      "#{label}: #{house.name}에 #{effect.name} (#{duration})"
    else
      character.update!(effects: character.active_effects + [entry.merge('kind' => 'fx', 'item' => item.to_s)])
      Game::Fx.expire!(character.account_id)
      "#{label}: #{effect.label} (#{duration})"
    end
  end

  # 이 규칙으로 붙은 효과를 그 캐릭터에게서 거둔다
  def remove!(character)
    mine = ->(entry) { entry['rule'] == id && entry['character'] == character.account_id }
    if character.effects.to_a.any?(&mine)
      character.update!(effects: character.effects.to_a.reject(&mine))
      Game::Fx.expire!(character.account_id)
    end
    GameHouse.all.each { |house| house.update!(effects: house.effects.to_a.reject(&mine)) if house.effects.to_a.any?(&mine) }
    nil
  end

  private

  # 최대치 규칙은 영구, 누적 횟수는 수치의 최대 누적치
  def normalize_max
    return unless at_max

    self.permanent = true
    self.threshold = counter&.max_count || 1
  end

  def max_count_given
    errors.add(:base, I18n.t('admin.games.counters.no_max')) if counter&.max_count.nil?
  end
end
