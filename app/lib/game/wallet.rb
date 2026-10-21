# frozen_string_literal: true

module Game
  # 캐릭터 돈·아이템·스탯을 바꾸고 기록한다 (자동봇 /api/v1/bot 과 운영진).
  # 여러 캐릭터를 한 번에 (양도), 모두 되거나 하나도 안 되게 처리한다.
  #
  #   Game::Wallet.apply!([{ account:, money: -3, items: { '사과' => 1 }, stats: { '힘' => 2 }, other: 상대계정, other_dir: 'to' }],
  #                       kind: 'purchase', detail: '사과 1개', actor: 'ssbot', once_per_day: false)
  #
  # 돈·아이템이 모자라면 Insufficient, 오늘 이미 했으면(once_per_day) AlreadyDone,
  # 없는 스탯이거나 상태 수치(계산값)면 UnknownStat 을 낸다. 스탯은 최소~최대 안으로 맞춘다.
  module Wallet
    class Error < StandardError
      attr_reader :code, :details

      def initialize(code, message, details = {})
        super(message)
        @code = code
        @details = details
      end
    end

    module_function

    # 이름 비교: 공백 무시, 소문자 (자동봇 normalize_key 와 같음)
    def key(name)
      name.to_s.gsub(/\s+/, '').downcase
    end

    def apply!(changes, kind:, detail: '', actor: '', once_per_day: false)
      changes = Array(changes).map { |change| normalize_change(change) }
      raise Error.new('empty', '바꿀 캐릭터가 없습니다.') if changes.empty?

      ensure_not_same_house!(changes) if kind == 'transfer'

      base_stats = GameCharacterField.stats.to_a # 스탯(저장된 값에 더함)과 상태 수치(영구 변동분을 쌓음)
      GameCharacter.transaction do
        characters = changes.map { |change| GameCharacter.for(change[:account]) }
        # 같은 순서로 잠가서 양도끼리 서로 기다리지 않게
        characters.uniq.sort_by(&:id).each(&:lock!)
        characters.each(&:reload)

        if once_per_day
          done = changes.find { |change| GameReward.today.exists?(account: change[:account], kind: kind) }
          raise Error.new('already_done', '오늘은 이미 했습니다.', acct: done[:account].username) if done
        end

        changes.zip(characters).each do |change, character|
          apply_one(character, change, base_stats)
          character.save!
          GameReward.create!(account: change[:account], kind: kind, money: change[:money], items: change[:items].map { |name, count| { 'name' => name, 'count' => count } },
                             stats: change[:stats], reason: detail.to_s.truncate(500), actor: actor.to_s.truncate(100),
                             other_account_id: change[:other]&.id, other_dir: change[:other] ? change[:other_dir].to_s : '')
        end
        characters
      end
    end

    # 소속 점수를 올리는 아이템은 같은 소속끼리 양도·선물할 수 없다
    def ensure_not_same_house!(changes)
      return unless changes.size == 2

      groups = changes.map { |change| GameCharacter.for(change[:account]).group_id }
      return if groups.any?(&:nil?) || groups.uniq.size != 1

      names = changes.flat_map { |change| change[:items].select { |_, count| count.positive? }.keys }
      return unless names.any? { |name| GameShopItem.raises_house_points?(name) }

      raise Error.new('same_house', '같은 소속끼리는 소속 점수를 올리는 아이템을 양도·선물할 수 없습니다.')
    end

    def normalize_change(change)
      change = change.to_h.symbolize_keys
      {
        account: change.fetch(:account),
        money: change[:money].to_i,
        items: change[:items].to_h.transform_keys(&:to_s).transform_values(&:to_i).reject { |name, count| name.strip.empty? || count.zero? },
        stats: change[:stats].to_h.transform_keys(&:to_s).transform_values(&:to_i).reject { |name, _| name.strip.empty? },
        # 양도·사용의 상대 (기록에 누가 누구에게 했는지): other 계정, other_dir 'to'(내가 상대에게) / 'from'(상대가 나에게)
        other: change[:other],
        other_dir: change[:other_dir],
      }
    end

    def apply_one(character, change, base_stats)
      acct = character.account.username

      money = character.money + change[:money]
      raise Error.new('insufficient_money', '소지금이 부족합니다.', acct: acct, money: character.money, needed: -change[:money]) if money.negative?

      character.money = money
      character.inventory = changed_inventory(character, change[:items])
      character.stats = changed_stats(character, change[:stats], base_stats)
    end

    # 이름이 같은(공백·대소문자 무시) 아이템에 더한다. 0개가 되면 뺀다
    def changed_inventory(character, items)
      list = Array(character.inventory).map(&:dup)
      items.each do |name, delta|
        entry = list.find { |item| key(item['name']) == key(name) }
        count = entry.to_h['count'].to_i + delta
        if count.negative?
          raise Error.new('insufficient_items', "'#{name}'#{Game::Text.particle(name.to_s.strip[-1], '이가')} 부족합니다.",
                          acct: character.account.username, item: name, count: entry.to_h['count'].to_i, needed: -delta)
        end

        if entry
          entry['count'] = count
        elsif count.positive?
          list << { 'name' => name.strip, 'count' => count, 'note' => '' }
        end
      end
      list.reject { |item| item['count'].to_i <= 0 }
    end

    def changed_stats(character, deltas, base_stats)
      stats = character.stats.dup
      deltas.each do |name, delta|
        field = base_stats.find { |stat| key(stat.name) == key(name) }
        raise Error.new('unknown_stat', "'#{name}' 스탯이 없습니다.", stat: name) if field.nil?

        stats[field.name] = field.status? ? (stats[field.name].to_i + delta).to_s : field.clamp(character.raw_stat_value(field) + delta).to_s
      end
      stats
    end
  end
end
