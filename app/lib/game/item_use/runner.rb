# frozen_string_literal: true

module Game
  module ItemUse
    # 아이템 [사용] 한 번 (웹 인벤토리·자동봇 [사용]·시스템 DM 이 같은 규칙으로 쓴다). 효과는 아이템의 item_effects 여러 개 (Game::ItemEffects).
    #   캐릭터를 고르는 효과(스탯·재화·RP·캐릭터 효과)는 target(@아이디 또는 캐릭터 이름, 본인도 가능),
    #   소속을 고르는 효과(소속 점수·소속 효과)는 house(이름 또는 번호), 소문내기는 text.
    #
    #   Game::ItemUse::Runner.new(account, '아이템', target: '@계정', house_id: '후플푸프', text: '소문', via: :web).call → 안내 문장
    #   모자라거나 규칙에 어긋나면 Game::ItemUse::Error (문구는 사용자에게 그대로 보여 준다)
    #
    # via: :bot(상점 봇에게 명령어) / :system(시스템 계정에 DM) 이면 쓴 사람이 이미 명령어 툿을 올렸으니 알림 툿은 올리지 않는다.
    class Runner
      attr_reader :howler_sent, :target

      def initialize(account, name, target: nil, house_id: nil, text: nil, via: :web)
        @account = account
        @name = name
        @target_query = target.to_s
        @house_query = house_id.to_s
        @text = text
        @via = via
      end

      # [사용/아이템/@상대/후플푸프/소문 내용] 처럼 뒤에 붙은 말들 → target / house / text 로 나눈다
      def self.from_args(account, name, args, via:)
        args = Array(args).map { |arg| arg.to_s.strip }.compact_blank
        target = args.find { |arg| arg.start_with?('@', '＠') }&.delete_prefix('＠')
        house = args.find { |arg| GameHouse.active.any? { |item| item.name == arg || item.id.to_s == arg } }
        target ||= args.find { |arg| arg != house && (GameCharacter.where(name: arg).exists? || GameCharacter.eligible_accounts.exists?(username: arg)) }
        text = (args - [target, house].compact).join('/')
        new(account, name, target: target, house_id: house, text: text, via: via)
      end

      def call
        shop_item = shop_item_for(@name)
        raise Error, "'#{@name}'#{particle(@name, '을를')} 가지고 있지 않습니다." unless owns?
        raise Error, "#{@name}#{particle(@name, '은는')} 사용할 수 없는 아이템입니다." if shop_item && !shop_item.usable

        effects = shop_item&.effects_list || []
        @target = effects_need_character?(effects) ? pick_character! : nil
        @house = Game::ItemEffects.needs_house?(effects) ? pick_house! : nil
        raise Error, '소문내기는 시스템 계정에 DM 으로 [사용/아이템/소문 내용] 을 보내 주세요. (보낸 사람이 드러나지 않게)' if Game::ItemEffects.needs_text?(effects) && @via == :bot

        @howler = Game::ItemEffects.rumor_text(effects)
        @rumor = Game::ItemEffects.needs_text?(effects) ? pick_rumor! : nil

        results = apply!(shop_item, effects)
        announce!(shop_item, effects, results)
        message(results)
      rescue Game::Dice::Error
        raise Error, '아이템 수치가 잘못되었습니다. 운영진에게 문의해 주세요.'
      end

      # 사용할 때 무엇을 고르나 (웹 모달·자동봇 안내)
      def self.needs(shop_item)
        effects = shop_item&.effects_list || []
        { character: Game::ItemEffects.needs_character?(effects), house: Game::ItemEffects.needs_house?(effects), text: Game::ItemEffects.needs_text?(effects) }
      end

      def self.needs_target?(shop_item)
        needs(shop_item)[:character]
      end

      private

      def effects_need_character?(effects)
        Game::ItemEffects.needs_character?(effects)
      end

      # 영구 아이템은 소모되지 않아 지갑이 부족을 막아 주지 못하니 직접 확인한다
      def owns?
        entry = Array(GameCharacter.for(@account).inventory).find { |item| Game::Wallet.key(item['name']) == Game::Wallet.key(@name) }
        entry.present? && entry['count'].to_i.positive?
      end

      def shop_item_for(name)
        GameShopItem.all.find { |item| Game::Wallet.key(item.name) == Game::Wallet.key(name) }
      end

      def pick_character!
        query = @target_query.delete_prefix('@').delete_prefix('＠').strip
        raise Error, '아이템을 쓸 캐릭터를 골라 주세요. 예: [사용/아이템/@상대]' if query.blank?
        return @account if query == 'me' # 웹 [나에게 쓰기]

        username = query.split('@').first.to_s
        target = GameCharacter.eligible_accounts.find_by(username: username)
        target ||= GameCharacter.where(name: query).first&.account
        raise Error, "'#{query}' 캐릭터를 찾을 수 없습니다." if target.nil?

        target
      end

      def pick_rumor!
        text = Game::ItemUse.clean_rumor(@text)
        raise Error, '소문 내용을 적어 주세요.' if text.blank?

        text
      end

      def pick_house!
        house = GameHouse.active.find { |item| item.id.to_s == @house_query || item.name == @house_query }
        raise Error, "#{Game::Config.for('common')['house_term']}#{particle(Game::Config.for('common')['house_term'].to_s, '을를')} 골라 주세요." if house.nil?

        house
      end

      # 아이템 소모 + 효과를 한 번에 (실패하면 아무것도 바뀌지 않는다). 효과마다 결과 한 줄
      def apply!(shop_item, effects)
        results = []
        GameCharacter.transaction do
          Game::Wallet.apply!([{ account: @account, items: shop_item&.permanent ? {} : { @name => -1 }, other: other_target, other_dir: 'to' }], kind: 'use', detail: detail, actor: @via.to_s)
          effects.each { |effect| results << apply_effect!(effect) }
        end
        Game::Fx.expire!(@target.id) if @target
        results.compact
      end

      def apply_effect!(effect)
        case effect['type']
        when 'stat' then apply_stat!(effect)
        when 'currency' then apply_currency!(effect)
        when 'fx' then apply_fx!(effect)
        when 'counter' then apply_counter!(effect)
        when 'special' then effect['kind'] == 'rumor' ? '호울러가 울려 퍼집니다.' : '운영진에게 알렸습니다.'
        end
      end

      def apply_stat!(effect)
        field = GameCharacterField.stats.find { |each| Game::Wallet.key(each.name) == Game::Wallet.key(effect['stat']) }
        raise Error, "'#{effect['stat']}' 스탯이 없습니다. 운영진에게 문의해 주세요." if field.nil?

        delta = Game::Dice.amount(effect['value'])
        character = GameCharacter.for(@target).reload
        if field.stat?
          before = character.stat_value(field)
          character.add_effect!(stat: field.name, delta: delta, minutes: effect['minutes'], item: @name)
          "#{field.name} #{format('%+d', delta)} (#{Game::ItemEffects.duration(effect['minutes'])} 동안) (#{before} → #{character.reload.stat_value(field)})"
        else
          before = character.status_value(field)
          Game::Wallet.apply!([{ account: @target, stats: { field.name => delta }, other: other_user, other_dir: 'from' }], kind: 'use', detail: "#{@name} → #{name_of(@target)}", actor: @via.to_s)
          "#{field.name} #{format('%+d', delta)} (#{before} → #{GameCharacter.for(@target).reload.status_value(field)})"
        end
      end

      # 더하기(+)·빼기(-). 빼는 만큼 없으면 가진 만큼만 뺀다
      def apply_currency!(effect)
        delta = Game::Dice.amount(effect['value'])
        case effect['currency']
        when 'house_points'
          raise Error, '같은 소속에는 소속 점수를 올리는 아이템을 쓸 수 없습니다.' if delta.positive? && GameCharacter.for(@account).group_id.to_i == @house.id

          GameHousePoint.create!(house: @house, account: @account, amount: delta, reason: "#{@name} → #{@house.name}".truncate(200)) unless delta.zero?
          "#{@house.name} 소속 점수 #{format('%+d', delta)}"
        when 'item'
          have = Array(GameCharacter.for(@target).reload.inventory).find { |item| Game::Wallet.key(item['name']) == Game::Wallet.key(effect['item']) }.to_h['count'].to_i
          delta = [delta, -have].max
          Game::Wallet.apply!([{ account: @target, items: { effect['item'] => delta }, other: other_user, other_dir: 'from' }], kind: 'use', detail: "#{@name} → #{name_of(@target)}", actor: @via.to_s) unless delta.zero?
          "#{name_of(@target)}: #{effect['item']} #{format('%+d', delta)}개"
        else
          delta = [delta, -GameCharacter.for(@target).reload.money].max
          Game::Wallet.apply!([{ account: @target, money: delta, other: other_user, other_dir: 'from' }], kind: 'use', detail: "#{@name} → #{name_of(@target)}", actor: @via.to_s) unless delta.zero?
          "#{name_of(@target)}: #{Game::Config.for('common')['currency_name']} #{format('%+d', delta)}"
        end
      end

      # 누적 수치(신고 등): 고른 캐릭터에 더하고, 새로 닿은 누적 횟수의 효과를 붙인다
      def apply_counter!(effect)
        counter = GameCounter.find_by(id: effect['counter_id'])
        raise Error, '누적 수치 목록에 없는 수치입니다. 운영진에게 문의해 주세요.' if counter.nil?

        before, after, notes = counter.add!(GameCharacter.for(@target), Game::Dice.amount(effect['value']), item: @name, reason: detail, actor: @via.to_s, source: @account)
        "#{name_of(@target)}: #{counter.name} #{format('%+d', after - before)} (누적 #{after}회)#{notes.empty? ? '' : " ➭ #{notes.join(', ')}"}"
      end

      def apply_fx!(effect)
        record = GameEffect.find_by(id: effect['effect_id'])
        return if record.nil?

        entry = Game::Fx.entry(record, effect['minutes'])
        if effect['target'] == 'house'
          @house.update!(effects: Game::Fx.active(@house.effects) + [entry])
          "#{@house.name}: #{record.name} (#{Game::ItemEffects.duration(effect['minutes'])} 동안)"
        else
          character = GameCharacter.for(@target).reload
          character.update!(effects: character.active_effects + [entry.merge('kind' => 'fx', 'item' => @name)])
          "#{name_of(@target)}: #{record.label} (#{Game::ItemEffects.duration(effect['minutes'])} 동안)"
        end
      end

      # 기록의 상대: 내가 대상에게 쓴 것 (나 자신이면 없음) / 대상이 받은 것에는 쓴 사람
      def other_target
        @target if @target && @target.id != @account.id
      end

      def other_user
        @account if @target && @target.id != @account.id
      end

      def detail
        [@name, (@target && "→ #{name_of(@target)}"), (@house && "→ #{@house.name}"), ('(소문)' if @rumor)].compact.join(' ')
      end

      def name_of(account)
        GameCharacter.for(account).display_name
      end

      def message(results)
        who = @target && (@target.id == @account.id ? '자신' : name_of(@target))
        head = who ? "#{who}에게 #{@name}#{particle(@name, '을를')} 사용했습니다." : "#{@name}#{particle(@name, '을를')} 사용했습니다."
        head += " (#{@howler_sent}명에게 전달)" if @howler_sent
        results.empty? ? head : "#{head} ➭ #{results.join(', ')}"
      end

      # 쓴 사람이 직접 보내는 툿 (상점 봇 멘션 + [사용/아이템/@상대/소속] 모양). 상대 캐릭터는 태그해서 알린다
      #   소속이 걸리면 팔로워 공개(모두 보게), 아니면 DM. 소문내기·DM 처리는 시스템 계정·봇에게만 DM (보낸 사람은 아무도 모르게)
      def announce!(shop_item, effects, results)
        specials = effects.select { |effect| effect['type'] == 'special' }.map { |effect| effect['kind'] }
        secret = specials.any? && @target.nil? && @house.nil?
        # ① 웹은 쓴 사람이 시스템 계정에 DM [사용/아이템/내용] 을 보낸 것처럼 먼저 남긴다 (모바일은 쓴 사람이 직접 보낸 DM)
        Game::Gift.announce(@account, command: ['사용', @name, @rumor].compact, system: true) if secret && !%i(bot system).include?(@via)
        # ② 시스템 계정이 연회장 문구를 올리고 ③ 이어서 모든 캐릭터에게 소문 내용을 DM 으로
        Game::ItemUse.announce_howler!(@howler) if @howler
        @howler_sent = Game::ItemUse.broadcast_rumor!(@rumor, header: @howler) if @rumor
        return if %i(bot system).include?(@via) || secret

        target = @target if @target && @target.id != @account.id
        command = ['사용', @name, (target && "@#{target.username}"), @house&.name].compact
        note = shop_item&.effect.presence
        me = GameCharacter.for(@account).display_name
        text = if target
                 Game::Text.render(Game::Config.for('common')['msg_item_use'], player: @account, target: target, item: @name, effect: results.empty? ? '' : " ➭ #{results.join(', ')}")
               else
                 "#{me}#{particle(me, '이가')} #{@name}#{particle(@name, '을를')} 사용했습니다.#{results.empty? ? '' : " ➭ #{results.join(', ')}"}"
               end
        text = [text, note].compact.join("\n")
        Game::Gift.announce(@account, command: command, text: text, receivers: [target].compact, system: specials.include?('staff'), visibility: @house ? 'private' : 'direct')
      end

      def particle(word, key)
        Game::Text.particle(word.to_s.strip[-1], key)
      end
    end
  end
end
