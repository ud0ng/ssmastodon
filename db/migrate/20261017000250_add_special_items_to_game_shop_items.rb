# frozen_string_literal: true

# 특수·착용 아이템
#   effect: 효과 설명 (사용했을 때 상대에게 알리는 글, RP용 아이템 안내)
#   special_kind: staff(시스템 계정에 DM) / report(캐릭터 신고: 소속 점수 차감·누적) / bomb(기숙사 점수 차감) / howler(내용 입력 → 전체 DM)
#   score_delta: 특수 아이템이 소속 점수를 바꾸는 값 (예: -5), special_limit: 신고 누적 한도
#   allow_random: 사용할 때 '랜덤 1인'을 고를 수 있음, wear_label: 착용 표시 이름 (동물 귀 등, stat_minutes 동안)
# 캐릭터: effects 에 착용(kind wear)도 담고, reports_count 는 신고 누적
class AddSpecialItemsToGameShopItems < ActiveRecord::Migration[8.0]
  def change
    add_column :game_shop_items, :effect, :text, null: false, default: '', if_not_exists: true
    add_column :game_shop_items, :special_kind, :string, null: false, default: 'staff', if_not_exists: true
    add_column :game_shop_items, :score_delta, :integer, null: false, default: 0, if_not_exists: true
    add_column :game_shop_items, :special_limit, :integer, null: false, default: 5, if_not_exists: true
    add_column :game_shop_items, :allow_random, :boolean, null: false, default: false, if_not_exists: true
    add_column :game_shop_items, :wear_label, :string, null: false, default: '', if_not_exists: true
    add_column :game_characters, :reports_count, :integer, null: false, default: 0, if_not_exists: true
  end
end
