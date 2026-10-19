# frozen_string_literal: true

# 자동봇이 보는 캐릭터 명단 (예전 관리·명단 시트). 돈·아이템·스탯은 apply 로만 바꾼다.
class Api::V1::Bot::CharactersController < Api::V1::Bot::BaseController
  def index
    base_stats = GameCharacterField.base_stats.to_a
    statuses = GameCharacterField.statuses.to_a
    characters = GameCharacter.visible.joins(:account).includes(:house, :faction, :account).order('accounts.username')
    render json: characters.map { |character| character_json(character, base_stats, statuses) }
  end

  # GET /api/v1/bot/characters/:id — id 자리에 아이디(acct)나 캐릭터 이름
  def show
    character = find_character(params[:id])
    return render json: { error: 'Character not found', code: 'not_found' }, status: 404 if character.nil?

    render json: character_json(character)
  end

  # POST /api/v1/bot/characters/apply
  #   { kind:, detail:, actor:, once_per_day:, changes: [{ acct:, money:, items: { 이름: 개수 }, stats: { 이름: 값 } }] }
  # 모두 되거나 하나도 안 된다. 모자라면 422 { code: insufficient_money / insufficient_items / already_done / unknown_stat }
  def apply
    kind = params[:kind].to_s
    raise Game::Wallet::Error.new('invalid_kind', "Unknown kind: #{kind}") unless GameReward::KINDS.include?(kind) && kind != 'content'

    changes = Array(params[:changes]).map do |change|
      change = change.permit(:acct, :money, items: {}, stats: {})
      character = find_character(change[:acct])
      raise Game::Wallet::Error.new('not_found', "'#{change[:acct]}' 캐릭터를 찾을 수 없습니다.", acct: change[:acct]) if character.nil?

      { account: character.account, money: change[:money], items: change[:items].to_h, stats: change[:stats].to_h }
    end

    ensure_item_rules!(kind, changes)
    temporary = kind == 'use' ? split_temporary_stats!(changes) : []
    characters = Game::Wallet.apply!(changes, kind: kind, detail: params[:detail], actor: params[:actor].presence || current_account.username,
                                              once_per_day: ActiveModel::Type::Boolean.new.cast(params[:once_per_day]))
    temporary.each { |effect| GameCharacter.for(effect[:account]).add_effect!(**effect.except(:account)) }
    characters.each(&:reload)
    base_stats = GameCharacterField.base_stats.to_a
    statuses = GameCharacterField.statuses.to_a
    render json: { characters: characters.map { |character| character_json(character, base_stats, statuses) } }
  end

  private

  # 예전 자동봇 [사용]: 아이템으로 바뀌는 스탯이 능력치(스탯 유형 '스탯')면 영구 변동이 아니라 일시 효과로 (아이템 스탯 효과의 지속시간). 상태 수치는 그대로 영구.
  def split_temporary_stats!(changes)
    shop_items = GameShopItem.all.to_a
    fields = GameCharacterField.stats.to_a
    effects = []
    changes.each do |change|
      used = change[:items].select { |_, count| count.to_i.negative? }.keys.filter_map { |name| shop_items.find { |item| Game::Wallet.key(item.name) == Game::Wallet.key(name) } }
      change[:stats].to_h.each do |name, delta|
        field = fields.find { |candidate| Game::Wallet.key(candidate.name) == Game::Wallet.key(name) }
        next unless field&.stat?

        item, effect = used.lazy.filter_map { |candidate| (found = candidate.effects_list.find { |each| each['type'] == 'stat' && Game::Wallet.key(each['stat']) == Game::Wallet.key(field.name) }) && [candidate, found] }.first
        next if item.nil?

        change[:stats].delete(name)
        effects << { account: change[:account], stat: field.name, delta: delta.to_i, minutes: effect['minutes'].to_i, item: item.name }
      end
    end
    effects
  end

  # 아이템마다 정한 [사용]·[선물] 가능 여부를 서버에서도 지킨다 (자동봇이 모르는 옛 버전이어도)
  def ensure_item_rules!(kind, changes)
    return unless %w(use transfer).include?(kind)

    rules = GameShopItem.all.index_by { |item| Game::Wallet.key(item.name) }
    changes.each do |change|
      change[:items].each do |name, count|
        next unless count.to_i.negative?

        item = rules[Game::Wallet.key(name)]
        raise Game::Wallet::Error.new('not_usable', "#{name}은(는) 사용할 수 없는 아이템입니다.") if kind == 'use' && item && !item.usable
        raise Game::Wallet::Error.new('not_giftable', "#{name}은(는) 선물할 수 없는 아이템입니다.") if kind == 'transfer' && item && !item.giftable
      end
    end
  end
end
