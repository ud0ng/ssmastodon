# frozen_string_literal: true

module Game
  module ItemUse
    # 아이템 [사용] 한 번 (웹 인벤토리와 자동봇 [사용] 이 같은 규칙으로 쓴다).
    #   stat       스탯을 바꾼다 (스탯 유형 '스탯'은 일시, '상태 수치'는 영구). 스탯을 정하지 않았으면 소모만
    #   character  고른 캐릭터(본인도 가능, 랜덤 1인 가능한 아이템도 있다)에게 쓴다: 스탯·착용이 적용되고 본인이 아니면 알린다
    #   special    특수: 시스템 계정에 DM (staff) / 캐릭터 신고 (report) / 기숙사 점수 차감 (bomb) / 소문 내기 (howler)
    #
    #   Game::ItemUse::Runner.new(account, '아이템', target: '@계정', house_id: 1, text: '소문', via: :web).call → 안내 문장
    #   모자라거나 규칙에 어긋나면 Game::ItemUse::Error (문구는 사용자에게 그대로 보여 준다)
    #
    # via: :bot 이면 쓴 사람이 이미 상점 봇에게 명령어를 보낸 것이라, 봇만 받는 알림 툿은 올리지 않는다 (봇이 직접 답한다).
    class Runner
      attr_reader :howler_sent

      def initialize(account, name, target: nil, house_id: nil, text: nil, via: :web)
        @account = account
        @name = name
        @target = target.to_s
        @house_id = house_id.to_s
        @text = text
        @via = via
      end

      def call
        shop_item = shop_item_for(@name)
        raise Error, "#{@name}#{particle(@name, '은는')} 사용할 수 없는 아이템입니다." if shop_item && !shop_item.usable

        field = shop_item&.stat_field
        raise Error, "'#{shop_item.stat_name}' 스탯이 없습니다. 운영진에게 문의해 주세요." if shop_item&.stat_name.present? && field.nil?

        use_item!(shop_item, field)
      rescue Game::Dice::Error
        raise Error, '아이템 수치가 잘못되었습니다. 운영진에게 문의해 주세요.'
      end

      # 사용 대상이 캐릭터인 아이템인가 (자동봇이 대상 태그를 요구할지 정할 때)
      def self.needs_target?(shop_item)
        shop_item&.use_target == 'character' || (shop_item&.use_target == 'special' && shop_item.special_kind == 'report')
      end

      private

      def shop_item_for(name)
        GameShopItem.all.find { |item| Game::Wallet.key(item.name) == Game::Wallet.key(name) }
      end

      # 아이템 소모 + 효과를 한 번에 (실패하면 아무것도 바뀌지 않는다)
      def use_item!(shop_item, field)
        kind = shop_item&.use_target || 'stat'
        special = kind == 'special' ? shop_item.special_kind : nil
        target = nil
        target = pick_character!(shop_item, allow_self: special != 'report') if kind == 'character' || special == 'report'
        target ||= @account

        raise Error, '호울러는 시스템 계정에 DM 으로 [사용/호울러/소문 내용] 을 보내 주세요. (보낸 사람이 드러나지 않게)' if special == 'howler' && bot?

        house = pick_house! if special == 'bomb'
        rumor = pick_rumor! if special == 'howler'

        delta = field && shop_item.stat_value.present? ? Game::Dice.amount(shop_item.stat_value) : nil
        temporary = field&.stat?
        target_character = GameCharacter.for(target)
        before = field && delta ? (temporary ? target_character.stat_value(field) : target_character.status_value(field)) : nil

        changes = [{ account: @account, items: { @name => -1 } }]
        if delta && !temporary
          # 상태 수치는 영구 변동: 본인이면 한 번에 합친다
          if target.id == @account.id
            changes.first[:stats] = { field.name => delta }
          else
            changes << { account: target, stats: { field.name => delta } }
          end
        end

        result = nil
        GameCharacter.transaction do
          Game::Wallet.apply!(changes, kind: 'use', detail: use_detail(kind, special, target, house), actor: @via.to_s)
          target_character.reload
          target_character.add_effect!(stat: field.name, delta: delta, minutes: shop_item.stat_minutes, item: @name) if delta && temporary
          target_character.add_wear!(label: shop_item.wear_label, minutes: shop_item.stat_minutes, item: @name) if shop_item&.wearable? && kind == 'character'
          result = use_special!(shop_item, special, target, house) if special
        end

        target_character.reload
        effect = effect_text(field, delta, temporary, shop_item, before, target_character)
        announce_use!(shop_item, kind, special, target, house, rumor, effect)
        use_message(kind, target, effect, result)
      end

      # 캐릭터를 태그해서 쓰는 아이템의 대상 (random 이고 랜덤을 허용하는 아이템이면 다른 서버원 중 한 명)
      def pick_character!(shop_item, allow_self:)
        if @target == 'random'
          raise Error, '이 아이템은 랜덤으로 쓸 수 없습니다.' unless shop_item&.allow_random

          target = GameCharacter.eligible_accounts.where.not(id: @account.id).order(Arel.sql('RANDOM()')).first
          raise Error, '랜덤으로 고를 사람이 없습니다.' if target.nil?

          return target
        end

        username = @target.delete_prefix('@').split('@').first.to_s
        target = GameCharacter.eligible_accounts.find_by(username: username)
        raise Error, '아이템을 쓸 캐릭터를 골라 주세요.' if target.nil?
        raise Error, '자신에게는 쓸 수 없습니다.' if !allow_self && target.id == @account.id

        target
      end

      def pick_house!
        house = GameHouse.active.find { |item| item.id.to_s == @house_id || item.name == @house_id }
        raise Error, '점수를 깎을 기숙사를 골라 주세요.' if house.nil?

        house
      end

      def pick_rumor!
        text = Game::ItemUse.clean_rumor(@text)
        raise Error, '소문 내용을 적어 주세요.' if text.blank?

        text
      end

      def use_detail(kind, special, target, house)
        case special
        when 'report' then "#{@name} → #{GameCharacter.for(target).display_name} (신고)"
        when 'bomb' then "#{@name} → #{house.name}"
        when 'howler' then "#{@name} (소문)"
        when 'staff' then "#{@name} (특수)"
        else kind == 'character' ? "#{@name} → #{GameCharacter.for(target).display_name}" : @name
        end
      end

      def duration_text(minutes)
        (minutes % 60).zero? && minutes >= 60 ? "#{minutes / 60}시간" : "#{minutes}분"
      end

      # ' ➭ 힘 +1 (60분 동안)' / ' ➭ 체력 +30 (영구) (25 → 55)' / ' ➭ 동물 귀 착용 (24시간 동안)'
      def effect_text(field, delta, temporary, shop_item, before, character)
        parts = []
        if field && delta
          value = temporary ? character.stat_value(field) : character.status_value(field)
          duration = temporary ? "#{duration_text(shop_item.stat_minutes)} 동안" : '영구'
          parts << "#{field.name} #{format('%+d', delta)} (#{duration})#{before && value ? " (#{before} → #{value})" : ''}"
        end
        parts << "#{shop_item.wear_label} 착용 (#{duration_text(shop_item.stat_minutes)} 동안)" if shop_item&.wearable?
        parts.empty? ? '' : " ➭ #{parts.join(', ')}"
      end

      def use_message(kind, target, effect, result)
        case kind
        when 'character'
          name = target.id == @account.id ? '자신' : GameCharacter.for(target).display_name
          "#{name}에게 #{@name}#{particle(@name, '을를')} 사용했습니다.#{effect}"
        when 'special'
          "#{@name}#{particle(@name, '을를')} 사용했습니다. #{result}#{@howler_sent ? " (#{@howler_sent}명에게 전달)" : ''}"
        else
          "#{@name}#{particle(@name, '을를')} 사용했습니다.#{effect}"
        end
      end

      # 특수 아이템: 종류에 따라 점수·소문을 처리한다. 결과 안내 문장을 돌려준다.
      def use_special!(shop_item, special, target, house)
        case special
        when 'report' then use_report!(shop_item, target)
        when 'bomb' then use_bomb!(shop_item, house)
        when 'howler' then '호울러가 호그와트 전체에 울려 퍼졌습니다.' # 실제 DM 은 트랜잭션이 끝난 뒤 announce_use! 에서 보낸다
        else
          '시스템 계정에 DM 으로 알렸습니다.'
        end
      end

      def use_report!(shop_item, target)
        character = GameCharacter.for(target)
        name = character.display_name
        deduct!(character.group, shop_item.score_delta, "교내 신고: #{name}")
        count = character.reports_count + 1
        volunteer = count >= [shop_item.special_limit, 1].max
        character.update!(reports_count: volunteer ? 0 : count)
        @report_notice = "교내 신고가 접수되었습니다. (누적 #{count}회)"
        @report_notice += ' 누적 한도를 넘어 교수님께서 봉사활동을 시키실 거예요.' if volunteer
        "#{name}#{particle(name, '을를')} 신고했습니다. (누적 #{count}회)#{volunteer ? ' 한도를 넘어 봉사활동 대상이 되었습니다.' : ''}"
      end

      def use_bomb!(shop_item, house)
        deduct!(house, shop_item.score_delta, "#{@name} → #{house.name}")
        "#{house.name}에 똥폭탄을 던졌습니다. (소속 점수 #{shop_item.score_delta})"
      end

      def deduct!(house, amount, reason)
        return if house.nil? || amount.zero?

        GameHousePoint.create!(house: house, account: @account, amount: amount, reason: reason.to_s.truncate(200))
      end

      # 쓴 사람이 직접 보내는 툿 (받는 사람·상점 봇 멘션 + 명령어 모양). Game::Gift.announce
      def announce!(command, text, receivers: [], system: false, visibility: 'direct')
        Game::Gift.announce(@account, command: command, text: text, receivers: receivers, system: system, visibility: visibility)
      end

      # 사용했을 때 알리기:
      #   캐릭터 아이템  받는 사람(본인이면 봇만) + 상점 봇에게 DM
      #   스탯 아이템    상점 봇에게 DM
      #   신고           신고받은 캐릭터 + 봇 + 시스템 계정에 DM
      #   기숙사 점수    상점 봇을 멘션한 툿 (팔로워에게 보인다)
      #   호울러·운영진 처리  시스템 계정과 상점 봇에게만 DM (아무도 모르게)
      # 봇에게 명령어를 보내 쓴 경우(via: :bot)는 봇만 받는 알림은 건너뛴다.
      def announce_use!(shop_item, kind, special, target, house, rumor, effect)
        name = GameCharacter.for(target).display_name
        note = shop_item&.effect.presence
        case special
        when 'report' then announce!(['사용', @name, name], @report_notice, receivers: [target], system: true)
        when 'bomb' then (announce!(['사용', @name, house.name], "#{house.name}에 #{@name}#{particle(@name, '이가')} 떨어졌습니다. (소속 점수 #{shop_item.score_delta})", visibility: 'private') unless bot?)
        when 'howler' then announce_howler!(rumor)
        when 'staff' then announce!(['사용', @name], nil, system: true)
        else
          if kind == 'character'
            return if bot? && target.id == @account.id

            text = Game::Text.render(Game::Config.for('common')['msg_item_use'], player: @account, target: target, item: @name, effect: [effect, note].compact_blank.join("\n"))
            announce!(['사용', @name, name], text, receivers: target.id == @account.id ? [] : [target])
          elsif !bot?
            me = GameCharacter.for(@account).display_name
            announce!(['사용', @name], "#{me}#{particle(me, '이가')} #{@name}#{particle(@name, '을를')} 사용했습니다.#{effect}")
          end
        end
      end

      # 호울러: 모든 캐릭터에게 한 사람씩 DM 소문, 시스템 계정·상점 봇에게는 명령어 기록 DM (보낸 사람은 아무도 모르게)
      def announce_howler!(rumor)
        @howler_sent = Game::ItemUse.broadcast_rumor!(rumor)
        announce!(['사용', @name, rumor], nil, system: true)
      end

      def bot?
        @via == :bot
      end

      def particle(word, key)
        Game::Text.particle(word.to_s.strip[-1], key)
      end
    end
  end
end
