# frozen_string_literal: true

# 신고·칭찬 누적 효과 기본값. 신고 1·3·5회(최대치)는 똥 한 덩이 → 똥똥 → 똥덩어리 악취, 칭찬은 번쩍 → 천사 고리 → 엔젤 (칭호·데코).
# 1·3회 누적은 하루, 5회(최대치)는 영구. 효과 목록(game_effects)에 없는 모양은 먼저 채우고(seed_missing!) 있는 효과를 누적 효과(game_counter_rules)에 연결한다.
# 앞서 다른 모양으로 만든 신고/칭찬 누적 효과가 있으면 이 모양으로 바꾼다. 이미 연결돼 있으면 건너뛴다.
class SeedCounterEffects < ActiveRecord::Migration[8.0]
  class Effect < ActiveRecord::Base
    self.table_name = 'game_effects'
  end

  class Counter < ActiveRecord::Base
    self.table_name = 'game_counters'
  end

  class Rule < ActiveRecord::Base
    self.table_name = 'game_counter_rules'
  end

  # 수치 이름 => [횟수(nil 은 최대치), 모양(칭호·데코 같은 이름)]
  LOOKS = {
    '신고' => [[1, 'dung1'], [3, 'dung2'], [nil, 'dung3']],
    '칭찬' => [[1, 'flash'], [3, 'halo'], [nil, 'angel']],
  }.freeze

  SLOTS = { 'title' => '칭호', 'deco' => '데코' }.freeze

  def up
    [Effect, Counter, Rule].each(&:reset_column_information)
    GameEffect.reset_column_information
    GameEffect.seed_missing!

    LOOKS.each do |counter_name, levels|
      counter = Counter.find_by(name: counter_name)
      next if counter.nil?

      # 예전 시드(칭호·데코 이름 '신고 1회 칭호' 등)는 지운다
      old = Effect.where('name LIKE ?', "#{counter_name} % 칭호").or(Effect.where('name LIKE ?', "#{counter_name} % 데코")).pluck(:id)
      Rule.where(game_counter_id: counter.id, game_effect_id: old).delete_all
      Effect.where(id: old).delete_all

      levels.each do |times, preset|
        SLOTS.each_key do |slot|
          effect = Effect.find_by(kind: 'character', slot: slot, preset: preset)
          next if effect.nil?
          next if Rule.exists?(game_counter_id: counter.id, game_effect_id: effect.id)

          Rule.create!(game_counter_id: counter.id, game_effect_id: effect.id, threshold: times || counter.max_count || 5, at_max: times.nil?, permanent: times.nil?, minutes: 1440)
        end
      end
    end
  end

  def down; end
end
