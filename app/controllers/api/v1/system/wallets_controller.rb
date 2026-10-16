# frozen_string_literal: true

# 웹 글쓰기 패널 아래 재화 | 인벤토리 | 전적 버튼과 재화·인벤토리 화면
#   show     내 재화·누적 획득/사용·인벤토리·전적
#   records  재화 기록 (filter: all gain spend items, max_id 로 다음 쪽)
#   gift     재화 선물 (받는 사람에게 시스템 DM)
class Api::V1::System::WalletsController < Api::BaseController
  include RoutingHelper

  RECORDS = 30

  before_action -> { doorkeeper_authorize! :read }, except: [:gift]
  before_action -> { doorkeeper_authorize! :write }, only: [:gift]
  before_action :require_user!

  def show
    character = GameCharacter.for(current_account)
    shop_items = GameShopItem.all.index_by { |item| Game::Wallet.key(item.name) }
    results = GamePlayer.joins(:session).where(account: current_account, game_sessions: { status: 'finished' }).group(:result).count
    rewards = GameReward.where(account: current_account)

    render json: {
      currency: currency,
      money: character.money,
      transfer_enabled: transfer_enabled?,
      gained: rewards.gained.sum(:money),
      spent: rewards.spent.sum(:money),
      item_count: character.item_count,
      record: { win: results['win'].to_i, lose: results['lose'].to_i, draw: results['draw'].to_i },
      # 왼쪽 컨텐츠 메뉴 배지: 받고 아직 수락하지 않은 신청 수
      invites: invites_count,
      # 글쓰기 패널 맨 아래 소속 점수 (점수 기준 소속, 이번 시즌)
      house_term: Game::Config.for('common')['house_term'],
      my_house_id: character.group_id&.to_s,
      houses: GameHouse.active.map { |house| { id: house.id.to_s, name: house.name, color: house.color, total: house.total } },
      inventory: Array(character.inventory).map { |item| inventory_json(item, shop_items[Game::Wallet.key(item['name'])]) },
    }
  end

  def records
    scope = GameReward.where(account: current_account)
    scope = { 'gain' => scope.gained, 'spend' => scope.spent, 'items' => scope.with_items }.fetch(params[:filter].to_s, scope)
    scope = scope.where(id: ...params[:max_id].to_i) if params[:max_id].present?
    page = scope.order(id: :desc).limit(RECORDS + 1).to_a

    render json: {
      records: page.first(RECORDS).map { |record| record_json(record) },
      next_max_id: page.size > RECORDS ? page[RECORDS - 1].id.to_s : nil,
    }
  end

  def gift
    return fail!('지금은 선물할 수 없습니다.') unless transfer_enabled?

    amount = params[:amount].to_i
    return fail!('1 이상만 선물할 수 있습니다.') unless amount.positive?

    receiver = GameCharacter.eligible_accounts.where.not(id: current_account.id).find_by(username: params[:acct].to_s.delete_prefix('@'))
    return fail!('받을 사람을 골라 주세요.') if receiver.nil?

    name = GameCharacter.for(receiver).display_name
    character = Game::Wallet.apply!([{ account: current_account, money: -amount }, { account: receiver, money: amount }],
                                    kind: 'transfer', detail: "#{amount}#{currency} → #{name}", actor: 'web').first
    Game::Gift.notify(Game::Config.for('common')['msg_gift_money'], receiver, player: current_account, target: receiver, money: amount, currency: currency)
    render json: { message: "#{name}에게 #{amount}#{currency}#{Game::Text.particle(currency.to_s.strip[-1], '을를')} 선물했습니다.", money: character.money }
  rescue Game::Wallet::Error => e
    fail!(e.message)
  end

  private

  def invites_count
    GamePlayer.joins(:session).merge(GameSession.current_kinds)
              .where(account: current_account, game_sessions: { status: 'pending' })
              .where("COALESCE(game_players.state->>'accepted', 'false') <> 'true'")
              .where("COALESCE(game_sessions.state->>'mode', '') <> 'event'")
              .count
  end

  def currency
    Game::Config.for('common')['currency_name']
  end

  def transfer_enabled?
    Game::Config.for('currency')['transfer_enabled']
  end

  def fail!(message)
    render json: { error: message }, status: 422
  end

  def inventory_json(item, shop_item)
    {
      name: item['name'],
      count: item['count'].to_i,
      note: item['note'].to_s,
      description: shop_item&.description.to_s,
      usable: shop_item.nil? || shop_item.usable,
      stat: shop_item&.stat_name.presence,
      stat_value: shop_item&.stat_name.present? ? shop_item.stat_value : nil,
      image: shop_item&.image.present? ? full_asset_url(shop_item.image.url(:small)) : nil,
    }
  end

  def record_json(record)
    {
      id: record.id.to_s,
      kind: record.kind,
      kind_name: I18n.t("admin.games.shop.kinds.#{record.kind}", default: record.kind),
      money: record.money,
      items: Array(record.items).map { |item| { name: item['name'], count: item['count'].to_i } },
      reason: reason_label(record.reason),
      created_at: record.created_at.iso8601,
    }
  end

  # 컨텐츠 보상의 'game:jellybean' 같은 사유는 컨텐츠 이름으로
  def reason_label(reason)
    key = reason.to_s.split(':').last
    Game::Kinds.keys.include?(key) ? Game::Kinds.fetch(key).display_name : reason.to_s
  end
end
