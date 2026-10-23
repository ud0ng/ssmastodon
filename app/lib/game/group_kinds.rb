# frozen_string_literal: true

module Game
  # 소속 종류: 기본으로 기숙사(house)와 진영(faction)이 있고, 운영진이 캐릭터 관리 > 소속에서 더 만든 종류(x1, x2 …)가 있다.
  # 종류마다 소속 목록(GameHouse.category)을 따로 두고, 캐릭터는 종류마다 소속 하나를 고른다
  # (기숙사·진영은 game_house_id·game_faction_id, 더 만든 종류는 game_characters.extra_group_ids).
  # 더 만든 종류의 이름은 game_configs 'group_kinds' 에 저장한다. 점수를 모을 종류는 공통 설정 group_mode.
  module GroupKinds
    KEY = 'group_kinds'
    BUILT_IN = %w(house faction).freeze

    module_function

    # 더 만든 종류 [{ 'key' => 'x1', 'label' => '동아리' }]
    def extras
      Array(GameConfig.find_by(key: KEY)&.data&.dig('kinds'))
    end

    def keys
      BUILT_IN + extras.pluck('key')
    end

    def extra?(key)
      extras.any? { |kind| kind['key'] == key.to_s }
    end

    # 기숙사·진영·더 만든 종류의 이름 { 'house' => '기숙사', ... }
    def labels
      common = Game::Config.for('common')
      { 'house' => common['house_label'], 'faction' => common['faction_label'] }.merge(extras.to_h { |kind| [kind['key'], kind['label']] })
    end

    def label(key)
      labels[key.to_s]
    end

    def add!(label)
      record = GameConfig.find_or_initialize_by(key: KEY)
      data = record.data || {}
      number = data['next'].to_i + 1
      kinds = Array(data['kinds']) + [{ 'key' => "x#{number}", 'label' => label.to_s.strip.first(20) }]
      record.update!(data: data.merge('kinds' => kinds, 'next' => number))
      Game::Config.forget_stored
      kinds.last['key']
    end

    def rename!(key, label)
      record = GameConfig.find_by(key: KEY)
      return if record.nil? || label.to_s.strip.blank?

      kinds = Array(record.data['kinds']).map { |kind| kind['key'] == key.to_s ? kind.merge('label' => label.to_s.strip.first(20)) : kind }
      record.update!(data: record.data.merge('kinds' => kinds))
    end

    # 종류를 지운다: 그 종류의 소속과 캐릭터가 속해 있던 기록도 지운다. 점수 기준이었다면 기숙사로 돌린다
    def remove!(key)
      record = GameConfig.find_by(key: KEY)
      return if record.nil? || !extra?(key)

      GameConfig.transaction do
        GameHouse.unscoped.where(category: key.to_s).destroy_all
        GameCharacter.where('jsonb_exists(extra_group_ids, ?)', key.to_s).update_all(['extra_group_ids = extra_group_ids - ?', key.to_s]) # rubocop:disable Rails/SkipsModelValidations
        record.update!(data: record.data.merge('kinds' => Array(record.data['kinds']).reject { |kind| kind['key'] == key.to_s }))
        Game::Config.merge!('common', 'group_mode' => 'house') if Game::Config.for('common')['group_mode'] == key.to_s
      end
    end
  end
end
