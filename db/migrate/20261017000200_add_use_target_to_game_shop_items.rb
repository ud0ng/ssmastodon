# frozen_string_literal: true

# 아이템 [사용] 대상: stat(스탯을 바꿈, 비우면 소모만) / character(고른 캐릭터에게, 본인도 가능) / special(특수)
#   stat_minutes: 능력치(스탯 유형 '스탯')를 바꿀 때 일시 효과가 이어지는 시간 (상태 수치는 영구 변동)
# 캐릭터의 일시 효과: game_characters.effects [{ stat, delta, until, item }]
class AddUseTargetToGameShopItems < ActiveRecord::Migration[8.0]
  def change
    add_column :game_shop_items, :use_target, :string, null: false, default: 'stat', if_not_exists: true
    add_column :game_shop_items, :stat_minutes, :integer, null: false, default: 60, if_not_exists: true
    add_column :game_characters, :effects, :jsonb, null: false, default: [], if_not_exists: true
  end
end
