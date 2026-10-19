# frozen_string_literal: true

module Game
  # 아이템 한 개의 사용 효과 여러 개 (game_shop_items.item_effects). 관리 화면 아이템 모달의 '효과' 상자 하나가 하나.
  #   stat      { stat, value(정수·주사위), minutes }        사용할 때 고른 캐릭터의 스탯 (스탯은 minutes 동안, 상태 수치는 영구)
  #   currency  { currency: house_points|money|item, value, item }  고른 캐릭터(소속 점수는 고른 소속)에 더하거나(+) 뺀다(-)
  #   character { kind: rp }                                  고른 캐릭터에게 쓴다 (RP용, 따로 바뀌는 것 없음)
  #   special   { kind: rumor|staff, text }                   소문내기(text 는 시스템 계정이 팔로워 공개 툿으로 알리고, 사용자가 쓴 소문은 모든 캐릭터에게 DM) / DM 처리(운영진·봇 계정에 DM)
  #   fx        { target: character|house, effect_id, minutes } 효과 목록의 효과를 고른 캐릭터·소속에 붙인다
  #   counter   { counter_id, value }                         누적 수치(신고 등, 상점 설정 > 누적 수치 목록)를 고른 캐릭터에 더한다. 누적 횟수에 닿으면 정해 둔 효과가 붙는다
  module ItemEffects
    TYPES = %w(stat currency character special fx counter).freeze
    CURRENCIES = %w(house_points money item).freeze
    SPECIALS = %w(rumor staff).freeze
    MAX_RUMOR = 200
    DEFAULT_RUMOR = '연회장 내에 호울러가 울려퍼집니다!'
    MAX_MINUTES = 60 * 24 * 30
    VALUE_FORMAT = GameShopItem::VALUE_FORMAT

    module_function

    # 관리 화면에서 받은 상자들 → 저장할 배열 (빈 상자·모르는 종류는 버린다)
    def normalize(list)
      rows = list.is_a?(Hash) ? list.sort_by { |key, _| key.to_i }.map(&:last) : Array(list)
      rows.filter_map do |row|
        row = row.to_h.stringify_keys
        case row['type']
        when 'stat'
          next if row['stat'].blank? || row['value'].blank?

          { 'type' => 'stat', 'stat' => row['stat'].to_s.strip, 'value' => row['value'].to_s.strip, 'minutes' => minutes(row['minutes'], row['unit']) }
        when 'currency'
          currency = CURRENCIES.include?(row['currency']) ? row['currency'] : 'money'
          next if row['value'].blank? || (currency == 'item' && row['item'].blank?)

          { 'type' => 'currency', 'currency' => currency, 'value' => row['value'].to_s.strip, 'item' => currency == 'item' ? row['item'].to_s.strip : '' }
        when 'counter'
          next if row['counter_id'].blank? || row['value'].blank?

          { 'type' => 'counter', 'counter_id' => row['counter_id'].to_i, 'value' => row['value'].to_s.strip }
        when 'character' then { 'type' => 'character', 'kind' => 'rp' }
        when 'special'
          kind = SPECIALS.include?(row['kind']) ? row['kind'] : 'staff'
          kind == 'rumor' ? { 'type' => 'special', 'kind' => 'rumor', 'text' => clean_rumor(row['text']).presence || DEFAULT_RUMOR } : { 'type' => 'special', 'kind' => kind }
        when 'fx'
          next if row['effect_id'].blank?

          { 'type' => 'fx', 'target' => row['target'] == 'house' ? 'house' : 'character', 'effect_id' => row['effect_id'].to_i, 'minutes' => minutes(row['minutes'], row['unit']) }
        end
      end
    end

    # 지속시간: 관리 화면은 숫자 + 단위(minute/hour/day)
    def minutes(value, unit = 'minute')
      return 60 if value.blank?

      (value.to_i * { 'hour' => 60, 'day' => 1440 }.fetch(unit.to_s, 1)).clamp(1, MAX_MINUTES)
    end

    # 저장 전 검사: 문구 목록 (비면 통과)
    def errors(effects)
      effects.flat_map do |effect|
        case effect['type']
        when 'stat'
          list = []
          list << "'#{effect['stat']}' 스탯이 없습니다." unless GameCharacterField.stats.exists?(name: effect['stat'])
          list << "스탯 수치 '#{effect['value']}'#{Game::Text.particle(effect['value'][-1], '이가')} 맞지 않습니다. (예: 5, -20, 1d10)" unless effect['value'].match?(VALUE_FORMAT)
          list
        when 'currency', 'counter'
          list = effect['value'].match?(VALUE_FORMAT) ? [] : ["수치 '#{effect['value']}'#{Game::Text.particle(effect['value'][-1], '이가')} 맞지 않습니다. (예: 10, -5, 1d6)"]
          list << '누적 수치 목록에 없는 수치입니다.' if effect['type'] == 'counter' && !GameCounter.exists?(id: effect['counter_id'])
          list
        when 'fx'
          effect_record = GameEffect.find_by(id: effect['effect_id'])
          if effect_record.nil? then ['효과 목록에 없는 효과입니다.']
          elsif (effect_record.kind == 'house') != (effect['target'] == 'house') then ["'#{effect_record.name}'#{Game::Text.particle(effect_record.name[-1], '은는')} #{effect['target'] == 'house' ? '소속' : '캐릭터'} 효과가 아닙니다."]
          else []
          end
        else []
        end
      end
    end

    # 사용할 때 무엇을 골라야 하나
    def needs_character?(effects)
      effects.any? { |effect| %w(stat character counter).include?(effect['type']) || (effect['type'] == 'currency' && effect['currency'] != 'house_points') || (effect['type'] == 'fx' && effect['target'] == 'character') }
    end

    def needs_house?(effects)
      effects.any? { |effect| (effect['type'] == 'currency' && effect['currency'] == 'house_points') || (effect['type'] == 'fx' && effect['target'] == 'house') }
    end

    # 소문내기는 사용할 때 소문 내용을 쓴다 (모든 캐릭터에게 DM)
    def needs_text?(effects)
      effects.any? { |effect| effect['type'] == 'special' && effect['kind'] == 'rumor' }
    end

    # 소문내기 효과에 정해 둔 문구 = 시스템 계정이 팔로워 공개 툿으로 알린다 (없으면 nil)
    def rumor_text(effects)
      effect = effects.find { |each| each['type'] == 'special' && each['kind'] == 'rumor' }
      effect && (clean_rumor(effect['text']).presence || DEFAULT_RUMOR)
    end

    def clean_rumor(text)
      text.to_s.strip.delete('@＠')[0, MAX_RUMOR]
    end

    def duration(minutes)
      minutes = minutes.to_i
      return "#{minutes / (60 * 24)}일" if minutes >= 60 * 24 && (minutes % (60 * 24)).zero?
      return "#{minutes / 60}시간" if minutes >= 60 && (minutes % 60).zero?

      "#{minutes}분"
    end

    def signed(value)
      value.to_s.start_with?('-', '+') ? value.to_s : "+#{value}"
    end

    # 관리 화면 표·사용자 화면에 보일 한 줄씩: '힘 +2 (1시간)', '상대 갈레온 -5', '소속 점수 -10', '칭호: 황금 칭호 (1일)'
    def summary(effects, currency_name: Game::Config.for('common')['currency_name'], effects_by_id: nil)
      effects_by_id ||= GameEffect.where(id: effects.filter_map { |effect| effect['effect_id'] if effect['type'] == 'fx' }).index_by(&:id)
      effects.map do |effect|
        case effect['type']
        when 'stat' then "#{effect['stat']} #{signed(effect['value'])} (#{duration(effect['minutes'])})"
        when 'currency'
          case effect['currency']
          when 'house_points' then "소속 점수 #{signed(effect['value'])}"
          when 'item' then "#{effect['item']} #{signed(effect['value'])}개"
          else "#{currency_name} #{signed(effect['value'])}"
          end
        when 'character' then 'RP용'
        when 'counter' then "#{GameCounter.find_by(id: effect['counter_id'])&.name || '누적 수치'} #{signed(effect['value'])}"
        when 'special' then effect['kind'] == 'rumor' ? '소문내기' : 'DM 처리'
        when 'fx'
          record = effects_by_id[effect['effect_id'].to_i]
          "#{record ? "#{I18n.t("admin.games.fx.slots.#{record.slot}")}: #{record.name}" : '효과'} (#{duration(effect['minutes'])})"
        end
      end
    end
  end
end
