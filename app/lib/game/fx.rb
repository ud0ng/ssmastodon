# frozen_string_literal: true

module Game
  # 효과(애니메이션). 효과 목록(GameEffect)은 운영진이 만들고, 아이템 [사용]으로 소속·캐릭터에 지속시간 동안 붙는다.
  #   소속 card   글쓰기 패널 아래 소속 점수 카드의 그 소속 칸
  #   캐릭터 title 이름 (칭호) / deco 원형 아바타 둘레 (데코) / skin 그 캐릭터 툿·멘션 알림의 배경 (스킨)
  # 모양(preset)은 CSS 애니메이션 (styles/mastodon/_game_fx.scss, 웹 components/game_fx.tsx). 상점 설정의 효과 on/off 가 꺼지면 아무 데도 안 보인다.
  module Fx
    SLOTS = { 'house' => %w(card), 'character' => %w(title deco skin) }.freeze

    PRESETS = {
      'card' => { 'gold' => '블링블링', 'poop' => '똥', 'fire' => '불꽃', 'snow' => '눈송이', 'hearts' => '하트', 'rainbow' => '무지개', 'sparkle' => '반짝이' },
      'title' => {
        'gold' => '금빛 반짝', 'rainbow' => '무지개 글자', 'fire' => '불타는 글자', 'poop' => '똥파리', 'glitch' => '지지직', 'hearts' => '하트', 'sparkle' => '반짝이',
        'dung1' => '똥 한 덩이', 'dung2' => '똥똥', 'dung3' => '똥덩어리 악취', 'flash' => '번쩍', 'halo' => '천사 고리', 'angel' => '엔젤', 'debut' => '데뷔탕트'
      },
      'deco' => {
        'gold' => '금빛 고리', 'rainbow' => '무지개 고리', 'fire' => '불꽃 고리', 'poop' => '똥 공전', 'hearts' => '하트 공전', 'snow' => '눈 결정', 'sparkle' => '반짝이',
        'dung1' => '똥 한 덩이', 'dung2' => '똥똥', 'dung3' => '똥덩어리 악취', 'flash' => '번쩍', 'halo' => '천사 고리', 'angel' => '엔젤', 'debut' => '데뷔탕트'
      },
      'skin' => { 'debut' => '데뷔탕트' },
    }.freeze

    # 효과 목록 기본: 모든 모양 하나씩 (GameEffect.ensure_defaults!, 20261019000200_seed_all_game_effects)
    DESCRIPTIONS = {
      'card' => {
        'gold' => '금빛 바탕이 흐르고 왕관·별빛·빛줄기가 반짝입니다.', 'poop' => '똥과 파리가 꼬이고 냄새가 나며 글자가 덜덜 떨립니다.',
        'fire' => '칸 아래에서 불꽃이 피어오릅니다.', 'snow' => '눈송이가 내립니다.', 'hearts' => '하트가 피어오릅니다.', 'rainbow' => '무지개 물결이 흐릅니다.',
        'sparkle' => '알록달록한 별이 여기저기서 반짝입니다.'
      },
      'title' => {
        'gold' => '이름이 금빛으로 반짝입니다.', 'rainbow' => '이름이 무지개색으로 흐릅니다.', 'fire' => '이름이 불타오릅니다.',
        'poop' => '이름이 갈색이 되고 똥파리가 꼬입니다.', 'glitch' => '이름이 가끔 지지직 깨집니다.', 'hearts' => '이름이 분홍색이 되고 하트가 피어납니다.',
        'sparkle' => '이름 둘레에서 알록달록한 별이 반짝입니다.', 'dung1' => '이름이 갈색이 되고 똥 한 덩이와 파리 한 마리가 따라다닙니다.',
        'dung2' => '이름이 더러운 갈색으로 떨리고 똥 두 덩이와 파리가 꼬이며 냄새가 납니다.',
        'dung3' => '이름이 썩은 색으로 덜덜 떨리고 똥덩어리와 파리떼가 꼬이며 지독한 악취가 피어오릅니다.',
        'flash' => '이름이 번쩍번쩍 눈부시게 빛납니다.', 'halo' => '이름 위에 천사 고리가 뜨고 빛이 반짝입니다.',
        'angel' => '이름 위에 천사 고리가 뜨고 날개 깃털과 빛이 흩날립니다.',
        'debut' => '이름이 금빛으로 번쩍이며 짜잔 하고 커졌다 작아지고, 금빛 광이 납니다. 신규 회원용 가장 화려한 이름.'
      },
      'deco' => {
        'gold' => '아바타 둘레에 금빛 고리가 돕니다.', 'rainbow' => '아바타 둘레에 무지개 고리가 돕니다.', 'fire' => '아바타 둘레에 불꽃 고리가 돕니다.',
        'poop' => '아바타 둘레를 똥이 돕니다.', 'hearts' => '아바타 둘레를 하트가 돕니다.', 'snow' => '아바타 둘레를 눈 결정이 돕니다.',
        'sparkle' => '아바타 둘레 여기저기서 별이 반짝입니다.', 'dung1' => '아바타 둘레에 똥 한 덩이와 파리가 돕니다.',
        'dung2' => '아바타 둘레를 똥 두 덩이와 파리가 돌고 냄새가 납니다.',
        'dung3' => '아바타 둘레를 똥덩어리와 파리떼가 돌며 지독한 악취가 피어오릅니다.',
        'flash' => '아바타 둘레가 번쩍번쩍 눈부시게 빛납니다.', 'halo' => '아바타 위에 천사 고리가 뜨고 빛이 돕니다.',
        'angel' => '아바타 위에 천사 고리가 뜨고 깃털이 360도로 둘레를 돕니다.',
        'debut' => '아바타 둘레에 금빛 광이 나며 짜잔 하고 커졌다 작아지고, 금빛 반짝이가 샤르르르 정신없이 반짝입니다. 신규 회원용 가장 화려한 아바타.'
      },
      'skin' => { 'debut' => '툿과 멘션 알림 배경 전체가 짜잔 하고 빛나며 금빛 테두리가 빛나고, 금빛 물결 위에서 빛줄기가 커졌다 작아지며 별빛이 번쩍입니다. 신규 회원용 가장 화려한 배경.' },
    }.freeze

    def self.defaults
      PRESETS.flat_map do |slot, presets|
        kind = SLOTS.find { |_, slots| slots.include?(slot) }.first
        presets.map do |preset, label|
          name = slot == 'card' ? label : "#{label} #{{ 'title' => '칭호', 'deco' => '데코', 'skin' => '스킨' }[slot]}"
          { kind: kind, slot: slot, preset: preset, name: name, description: DESCRIPTIONS.dig(slot, preset).to_s }
        end
      end
    end

    # 소속 카드 블링블링·똥 미리보기 (웹 compose/components/house_fx.tsx 와 같은 그림·위치)
    HOUSE_PARTICLES = {
      sparks: [
        ['✦', '8%', '18%', '10px', '1.5s', '0s'], ['✧', '24%', '70%', '12px', '1.9s', '0.4s'], ['✨', '40%', '12%', '11px', '2.1s', '0.9s'],
        ['✦', '58%', '62%', '9px', '1.4s', '0.2s'], ['✧', '72%', '20%', '13px', '1.8s', '0.7s'], ['✨', '86%', '66%', '10px', '2.3s', '1.2s'],
        ['✦', '92%', '14%', '8px', '1.6s', '0.5s'], ['⭐', '14%', '46%', '7px', '2s', '1.5s'], ['✧', '66%', '42%', '8px', '1.7s', '1s']
      ],
      poops: [['💩', '10%', nil, '12px', '3.4s', '0s'], ['💩', '30%', nil, '9px', '2.8s', '0.9s'], ['💩', '52%', nil, '14px', '3.8s', '0.3s'], ['💩', '70%', nil, '10px', '3s', '1.6s'], ['💩', '88%', nil, '12px', '3.6s', '1.1s']],
      flies: [['🪰', '0', nil, '10px', '2.2s', '0s'], ['🪰', '0', nil, '8px', '1.6s', '0.6s'], ['🪰', '0', nil, '9px', '2.8s', '1.1s']],
      stinks: [['〰', '20%', nil, '12px', '2.4s', '0.2s'], ['〰', '46%', nil, '10px', '2s', '1s'], ['〰', '78%', nil, '12px', '2.6s', '0.6s']],
    }.freeze

    CACHE_TTL = 1.minute

    module_function

    def enabled?
      Game::Config.for('currency')['effects_enabled'] != false
    end

    def preset_label(slot, preset)
      PRESETS.dig(slot, preset) || preset
    end

    # 관리 화면 모양 고르기: [[묶음 이름, [[이름, 'slot:preset'], ...]], ...]
    def preset_options
      PRESETS.map do |slot, presets|
        slot_label = I18n.t("admin.games.fx.slots.#{slot}")
        [slot_label, presets.map { |preset, label| ["#{slot_label} · #{label}", "#{slot}:#{preset}"] }]
      end
    end

    # 지금 붙어 있는 효과 [{ 'effect_id', 'until' }] 중 끝나지 않은 것
    def active(list)
      Array(list).select { |entry| Time.zone.parse(entry['until'].to_s)&.future? }
    end

    # permanent 면 영구 (끝나는 때를 아주 먼 날로)
    def entry(effect, minutes, permanent: false)
      until_time = permanent ? GameCounterRule::PERMANENT_YEARS.years.from_now : minutes.to_i.minutes.from_now
      { 'effect_id' => effect.id, 'slot' => effect.slot, 'preset' => effect.preset, 'until' => until_time.iso8601 }
    end

    # 영구인가 (끝나는 때가 아주 먼 날)
    def permanent?(entry)
      Time.zone.parse(entry['until'].to_s).to_i > GameCounterRule::PERMANENT_YEARS.div(2).years.from_now.to_i
    end

    # 목록의 index 번째 효과(effect_id 가 맞을 때만)의 끝나는 때를 바꾸거나 (time) 지운다 (time 이 nil). 새 목록을 돌려준다
    def change_entry(list, index, effect_id, time)
      list = Array(list).map(&:dup)
      index = index.to_i
      entry = list[index]
      return list if index.negative? || entry.nil? || entry['effect_id'].to_s != effect_id.to_s

      time ? entry['until'] = time.iso8601 : list.delete_at(index)
      list
    end

    # 소속 카드에 보일 모양 (마지막에 붙은 것 하나)
    def house_preset(house)
      return unless enabled?

      active(house.effects).last&.dig('preset')
    end

    # 소속 카드에 붙은 효과의 끝나는 때 (house_preset 과 같은 것, 없으면 nil)
    def house_until(house)
      return unless enabled?

      active(house.effects).last&.dig('until')
    end

    # 그 캐릭터가 지금 입고 있는 칭호·데코·스킨 [{ slot, preset, name, until, permanent }] (자리마다 마지막에 붙은 것, 효과가 꺼져 있으면 [])
    def wearing(character)
      return [] unless enabled?

      entries = active(Array(character.effects).select { |item| item['kind'] == 'fx' }).select { |item| SLOTS['character'].include?(item['slot']) }
      names = GameEffect.unscoped.where(id: entries.pluck('effect_id')).pluck(:id, :name).to_h
      SLOTS['character'].filter_map do |slot|
        entry = entries.reverse.find { |item| item['slot'] == slot }
        next if entry.nil?

        { slot: slot, preset: entry['preset'], name: names[entry['effect_id'].to_i].presence || preset_label(slot, entry['preset']), until: entry['until'], permanent: permanent?(entry) }
      end
    end

    # 계정에 보일 캐릭터 효과 { 'title' => preset, 'deco' => preset } (자리마다 마지막에 붙은 것)
    def for_account_id(account_id)
      return {} unless enabled?

      Rails.cache.fetch(cache_key(account_id), expires_in: CACHE_TTL) do
        effects = GameCharacter.where(account_id: account_id).pick(:effects)
        active(Array(effects).select { |item| item['kind'] == 'fx' }).each_with_object({}) { |item, result| result[item['slot']] = item['preset'] if SLOTS['character'].include?(item['slot']) }
      end
    end

    # 지금 효과가 붙은 모든 캐릭터 { '계정 번호' => { 'title' => preset, 'deco' => preset } } (웹 /api/v1/system/fx)
    def all_accounts
      return {} unless enabled?

      GameCharacter.where("effects::text LIKE '%\"fx\"%'").pluck(:account_id, :effects).each_with_object({}) do |(account_id, effects), result|
        fx = active(Array(effects).select { |item| item['kind'] == 'fx' }).each_with_object({}) { |item, found| found[item['slot']] = item['preset'] if SLOTS['character'].include?(item['slot']) }
        result[account_id.to_s] = fx if fx.any?
      end
    end

    def expire!(account_id)
      Rails.cache.delete(cache_key(account_id))
    end

    def cache_key(account_id)
      "game/fx/#{account_id}"
    end
  end
end
