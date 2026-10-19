# frozen_string_literal: true

# 효과 목록 (상점 설정 > 상점 목록 > 효과 목록) 과 아이템마다 여러 개의 사용 효과.
#   game_effects: 소속 점수 카드 효과 / 캐릭터 효과(칭호·데코·스킨). preset 은 Game::Fx::PRESETS 의 애니메이션
#   game_shop_items.item_effects: [{ type: stat|currency|character|special|fx, ... }] (Game::ItemEffects)
#   game_houses.effects: 소속에 붙은 효과 [{ effect_id, until }]
#   game_counters / game_counter_rules: 누적 수치(신고 등)와 누적 횟수별 효과 (상점 설정 > 누적 수치 설정), game_characters.counters: { 수치 번호 => 횟수 }
# 예전 한 칸짜리 사용 설정(use_target·stat_*·special_kind·score_delta)은 item_effects 로 옮긴다. 옛 칸은 지우지 않고 무시한다.
class CreateGameEffects < ActiveRecord::Migration[8.0]
  class Item < ActiveRecord::Base
    self.table_name = 'game_shop_items'
  end

  class Counter < ActiveRecord::Base
    self.table_name = 'game_counters'
  end

  class Character < ActiveRecord::Base
    self.table_name = 'game_characters'
  end

  def up
    create_table :game_effects, if_not_exists: true do |t|
      t.string :kind, null: false, default: 'house'
      t.string :slot, null: false, default: 'card'
      t.string :preset, null: false, default: 'gold'
      t.string :name, null: false, default: ''
      t.text :description, null: false, default: ''
      t.integer :position, null: false, default: 0
      t.timestamps
    end

    create_table :game_counters, if_not_exists: true do |t|
      t.string :name, null: false, default: ''
      t.integer :position, null: false, default: 0
      t.timestamps
    end

    create_table :game_counter_rules, if_not_exists: true do |t|
      t.references :game_counter, null: false, foreign_key: { on_delete: :cascade }
      t.integer :threshold, null: false, default: 1
      t.references :game_effect, null: true, foreign_key: { on_delete: :cascade }
      t.integer :minutes, null: false, default: 1440
      t.timestamps
    end

    add_column :game_shop_items, :item_effects, :jsonb, null: false, default: [], if_not_exists: true
    add_column :game_houses, :effects, :jsonb, null: false, default: [], if_not_exists: true
    add_column :game_characters, :counters, :jsonb, null: false, default: {}, if_not_exists: true

    Item.reset_column_information
    Character.reset_column_information
    Item.find_each { |item| item.update_columns(item_effects: convert(item)) }
    # 쌓여 있던 신고 횟수 → 누적 수치 '신고'
    Character.where('reports_count > 0').find_each { |character| character.update_columns(counters: { report_counter_id.to_s => character.reports_count }) }
  end

  def down
    remove_column :game_characters, :counters, if_exists: true
    drop_table :game_counter_rules, if_exists: true
    drop_table :game_counters, if_exists: true
    remove_column :game_houses, :effects, if_exists: true
    remove_column :game_shop_items, :item_effects, if_exists: true
    drop_table :game_effects, if_exists: true
  end

  private

  def report_counter_id
    @report_counter_id ||= (Counter.find_by(name: '신고') || Counter.create!(name: '신고', position: 0)).id
  end

  # 스탯 → 스탯 효과, 폭탄 → 소속 점수, 호울러 → 소문내기, 운영진 DM → DM 처리, 신고 → 신고, 캐릭터 → RP. 착용·랜덤은 없앤다
  def convert(item)
    effects = []
    effects << { 'type' => 'character', 'kind' => 'rp' } if item.use_target == 'character'
    if item.stat_name.present? && item.stat_value.present? && item.use_target != 'special'
      effects << { 'type' => 'stat', 'stat' => item.stat_name, 'value' => item.stat_value, 'minutes' => item.stat_minutes.to_i }
    end
    if item.use_target == 'special'
      case item.special_kind
      when 'bomb' then effects << { 'type' => 'currency', 'currency' => 'house_points', 'value' => item.score_delta.to_s }
      when 'howler' then effects << { 'type' => 'special', 'kind' => 'rumor' }
      when 'staff' then effects << { 'type' => 'special', 'kind' => 'staff' }
      when 'report' then effects << { 'type' => 'counter', 'counter_id' => report_counter_id, 'value' => '1' }
      end
    end
    effects
  end
end
