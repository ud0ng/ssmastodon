# frozen_string_literal: true

# 누적 수치 이름을 신고→벌점, 칭찬→상점으로 바꾸고, 교내 신고권 설명을 고치고, 교내 칭찬권(60, 상점 +1)을 넣는다.
class RenameCountersAndAddPraiseItem < ActiveRecord::Migration[8.0]
  class Counter < ActiveRecord::Base
    self.table_name = 'game_counters'
  end

  REPORT_DESCRIPTION = '더 이상 참을 수 없어! 다른 학생을 신고할 수 있습니다. 신고 받으면 벌점을 받습니다. 벌점이 늘어나면 벌을 받으니 상점으로 꼭 회복하세요!'
  PRAISE_DESCRIPTION = '고마운 학생을 칭찬해 주세요! 칭찬 받은 학생은 상점을 받습니다. 상점이 쌓이면 벌점을 지워 주니, 마음을 담아 선물해 보세요.'

  def up
    Counter.reset_column_information
    rename('신고', '벌점')
    rename('칭찬', '상점')

    return if Rails.env.test? # 시험 DB 에는 넣지 않는다 (시험이 직접 만든다)

    report = GameShopItem.unscoped.find_by(name: '교내 신고권')
    report&.update_columns(description: REPORT_DESCRIPTION, effect: '벌점 +1')

    merit = Counter.find_by(name: '상점')
    return if merit.nil?

    existing = GameShopItem.unscoped.find_by(name: '교내 칭찬권')
    if existing
      existing.update_columns(item_effects: [{ 'type' => 'counter', 'counter_id' => merit.id, 'value' => '1' }]) if Array(existing.item_effects).empty?
      return
    end

    shop = report&.shop || GameShop.first || GameShop.create!(name: '상점', description: '', position: 0)
    shop.items.create!(name: '교내 칭찬권', price: 60, usable: true, giftable: true, description: PRAISE_DESCRIPTION, effect: '상점 +1',
                       item_effects: [{ 'type' => 'counter', 'counter_id' => merit.id, 'value' => '1' }], position: shop.items.count)
  end

  def down; end

  private

  def rename(from, to)
    counter = Counter.find_by(name: from)
    counter.update_columns(name: to) if counter && !Counter.exists?(name: to)
  end
end
