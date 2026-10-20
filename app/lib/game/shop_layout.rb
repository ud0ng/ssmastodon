# frozen_string_literal: true

module Game
  # 기본 상점 나누기 (상점 설정 > 상점 목록): 허니듀크 하나에 있던 아이템을 RP / 컨텐츠 / 특수 상점으로 나누고,
  # 효과 목록의 소속 효과·칭호+데코 세트를 '데코' 상점에 아이템으로 더한다.
  #   이미 있는 아이템은 상점만 옮기고, 없는 아이템만 새로 만든다 (여러 번 돌려도 같은 결과).
  module ShopLayout
    SHOPS = {
      'RP' => ['동물 귀 머리띠', '동물 꼬리 키링', '그리핀도르 깃펜세트', '후플푸프 깃펜세트', '래번클로 깃펜세트', '슬리데린 깃펜세트', '꽃 한 송이', '꽃다발', '우정 악세사리'],
      '컨텐츠' => ['장소 협의권', '선배들의 노하우 수첩', '교내 칭찬권', '교내 신고권', '똥폭탄'],
      '특수' => ['호울러', '일회용 반장뱃지', '가짜 허가서', '불량 리벨리오 주문서', '정식 리벨리오 주문서'],
    }.freeze

    # 예전 이름 → 새 이름 (이미 새 이름이 있으면 그대로 둔다)
    RENAMES = {
      '그리핀도르 색잉크' => '그리핀도르 깃펜세트', '후플푸프 색잉크' => '후플푸프 깃펜세트',
      '래번클로 색잉크' => '래번클로 깃펜세트', '슬리데린 색잉크' => '슬리데린 깃펜세트',
    }.freeze

    # 목록에 없어서 새로 만드는 아이템 (가격은 임시값이니 상점 설정에서 고친다)
    NEW_ITEMS = {
      '장소 협의권' => { price: 30, description: '컨텐츠 진행 장소를 협의할 수 있는 권리입니다.', effect: '컨텐츠용 아이템' },
      '선배들의 노하우 수첩' => { price: 30, description: '선배들이 남긴 노하우가 빼곡히 적힌 수첩입니다.', effect: '컨텐츠용 아이템' },
    }.freeze

    DECO_SHOP = '데코'
    PRICE = 20
    MINUTES = 60
    SLOT_NAMES = { 'title' => '칭호', 'deco' => '데코' }.freeze

    module_function

    def apply!
      shops = SHOPS.keys.index_with { |name| GameShop.find_by(name: name) || GameShop.create!(name: name, description: '', position: GameShop.unscoped.maximum(:position).to_i + 1) }
      RENAMES.each do |from, to|
        item = GameShopItem.unscoped.find_by(name: from)
        item.update!(name: to) if item && !GameShopItem.unscoped.exists?(name: to)
      end

      SHOPS.each do |shop_name, names|
        names.each do |name|
          item = GameShopItem.unscoped.find_by(name: name)
          if item
            item.update!(shop: shops[shop_name]) unless item.game_shop_id == shops[shop_name].id
          elsif NEW_ITEMS.key?(name)
            shops[shop_name].items.create!(NEW_ITEMS[name].merge(name: name, usable: false, position: shops[shop_name].items.count))
          end
        end
      end

      add_effect_items!
    end

    # 소속(card) 효과 하나마다 아이템 하나, 칭호+데코가 짝인 모양마다 세트 아이템 하나 (벌점·상점 같은 누적 수치에 쓰는 효과와 데뷔탕트는 뺀다)
    def add_effect_items!
      shop = GameShop.find_by(name: DECO_SHOP) || GameShop.create!(name: DECO_SHOP, description: '', position: GameShop.unscoped.maximum(:position).to_i + 1)
      counter_ids = GameCounterRule.pluck(:game_effect_id)
      allowed = GameEffect.all.reject { |effect| counter_ids.include?(effect.id) || effect.preset.start_with?('debut') }

      allowed.select { |effect| effect.slot == 'card' }.each do |effect|
        create_item!(shop, "#{effect.name} 소속 데코", "소속 점수 카드에 #{effect.name} 효과를 #{MINUTES}분 동안 붙입니다.",
                     [{ 'type' => 'fx', 'target' => 'house', 'effect_id' => effect.id, 'minutes' => MINUTES }])
      end

      allowed.select { |effect| SLOT_NAMES.key?(effect.slot) }.group_by(&:preset).each do |preset, effects|
        title = effects.find { |effect| effect.slot == 'title' }
        deco = effects.find { |effect| effect.slot == 'deco' }
        next if title.nil? || deco.nil?

        label = Game::Fx::PRESETS.dig('title', preset)
        create_item!(shop, "#{label} 세트", "#{label} 칭호와 데코를 함께 #{MINUTES}분 동안 붙입니다.",
                     [title, deco].map { |effect| { 'type' => 'fx', 'target' => 'character', 'effect_id' => effect.id, 'minutes' => MINUTES } })
      end
    end

    def create_item!(shop, name, description, effects)
      return if GameShopItem.unscoped.exists?(name: name)

      shop.items.create!(name: name, price: PRICE, usable: true, giftable: true, description: description, effect: "#{MINUTES}분 동안 지속", item_effects: effects, position: shop.items.count)
    end
  end
end
