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
    shop_items = GameShopItem.includes(:shop).index_by { |item| Game::Wallet.key(item.name) }
    results = GamePlayer.joins(:session).merge(GameSession.real).where(account: current_account, game_sessions: { status: 'finished' }).group(:result).count
    rewards = GameReward.where(account: current_account)
    # 재화 화면의 툿 합계: 일일 활동 스냅샷(어제까지 저장된 날 + 오늘 툿마다 쌓이는 값)에서 읽는다 (툿을 일일이 세지 않는다)
    totals = Game::ActivitySnapshot.totals([current_account.id])[current_account.id]

    render json: {
      currency: currency,
      money: character.money,
      # 인벤토리 화면 위 착용 슬롯 (칭호·데코·스킨 미리보기에 쓰는 내 아바타·이름)
      me: { name: character.display_name, avatar: full_asset_url(current_account.avatar_static_url) },
      wearing: Game::Fx.wearing(character),
      transfer_enabled: transfer_enabled?,
      gained: rewards.gained.sum(:money),
      spent: rewards.spent.sum(:money),
      # 내 툿 합계 (DM 포함 전체 툿 수 / 글자 수): 재화 화면 누적 사용 옆
      posts: totals.all_posts,
      post_chars: totals.all_chars,
      item_count: character.item_count,
      record: { win: results['win'].to_i, lose: results['lose'].to_i, draw: results['draw'].to_i },
      # 왼쪽 컨텐츠 메뉴 배지: 받고 아직 수락하지 않은 신청 수
      invites: todo_sessions.size,
      # 내가 행동해야 하는 판 (수락 대기·내 차례): 컨텐츠 메뉴 배지와 알림 소리의 기준
      todo: todo_sessions,
      # 글쓰기 패널 맨 아래 소속 점수 (점수 기준 소속, 이번 시즌)
      house_term: Game::Config.for('common')['house_term'],
      my_house_id: character.group_id&.to_s,
      # fx: 아이템으로 붙은 소속 카드 효과 모양 (Game::Fx, 효과가 꺼져 있으면 nil)
      houses: houses_json,
      inventory: Array(character.inventory).map { |item| inventory_json(item, shop_items[Game::Wallet.key(item['name'])]) },
    }
  end

  def records
    scope = GameReward.where(account: current_account)
    scope = { 'gain' => scope.gained, 'spend' => scope.spent, 'items' => scope.with_items }.fetch(params[:filter].to_s, scope)
    scope = scope.where(id: ...params[:max_id].to_i) if params[:max_id].present?
    page = scope.order(id: :desc).limit(RECORDS + 1).to_a

    shown = page.first(RECORDS)
    others = Account.where(id: shown.filter_map(&:other_account_id)).index_by(&:id)
    render json: {
      records: shown.map { |record| record_json(record, others[record.other_account_id]) },
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
    character = Game::Wallet.apply!([{ account: current_account, money: -amount, other: receiver, other_dir: 'to' }, { account: receiver, money: amount, other: current_account, other_dir: 'from' }],
                                    kind: 'transfer', detail: "#{amount}#{currency} → #{name}", actor: 'web').first
    Game::Gift.announce(current_account, command: ['양도', "#{amount}#{currency}", name],
                                         text: Game::Text.render(Game::Config.for('common')['msg_gift_money'], player: current_account, target: receiver, money: amount, currency: currency), receivers: [receiver])
    render json: { message: "#{name}에게 #{amount}#{currency}#{Game::Text.particle(currency.to_s.strip[-1], '을를')} 선물했습니다.", money: character.money }
  rescue Game::Wallet::Error => e
    fail!(e.message)
  end

  private

  # 내 자리에 버튼(행동)이 열려 있는 판: 수락 대기 신청, 내가 고를 차례 (웹 방의 '내 차례예요' 와 같은 기준, Game::Card)
  # 소속마다 점수·카드 효과와, 그 소속 캐릭터들의 누적 수치 결과값 합계 (바뀌면 소속 점수 카드에 알림 배지·소리)
  def houses_json
    counters = GameCounter.where(affects_house: true).includes(:opposite).to_a
    sums = Hash.new(0)
    unless counters.empty?
      GameCharacter.visible.each do |each|
        group = each.group
        sums[group.id] += counters.sum { |counter| counter.net_for(each) } if group
      end
    end
    GameHouse.active.map do |house|
      { id: house.id.to_s, name: house.name, color: house.color, total: house.total, counters: sums[house.id], fx: Game::Fx.house_preset(house), fx_until: Game::Fx.house_until(house) }
    end
  end

  def todo_sessions
    @todo_sessions ||= recruiting_events + my_todo_sessions
  end

  def my_todo_sessions
    GamePlayer.joins(:session).merge(GameSession.current_kinds.real)
              .where(account: current_account, game_sessions: { status: GameSession::OPEN_STATUSES })
              .includes(:session).filter_map do |player|
      session = player.session
      next if session.state['mode'] == 'event' && session.status == 'pending'

      actions = Game::Card.safe { Game::Card.actions_for(session, session.kind_class&.new(session)) } || []
      next unless actions.any? { |action| !action['meta'] && action['seats'].is_a?(Array) && action['seats'].include?(player.seat) }

      { session_id: session.id.to_s, name: session.kind_class&.display_name || session.kind, event: session.kind_class.present? && session.kind_class.max_opponents > 1 }
    end
  end

  # 내가 아직 참가하지 않은 모집 중인 이벤트: 이벤트 메뉴에 알림 배지가 뜬다
  def recruiting_events
    (invitations + open_recruitments).map do |session|
      { session_id: session.id.to_s, name: session.kind_class&.display_name || session.kind, event: true }
    end
  end

  # 초대받고 아직 수락하지 않은 이벤트 대기방 (이벤트 메뉴 알림 배지)
  def invitations
    GameSession.current_kinds.where(status: 'lobby').where("COALESCE(state->'invited', '[]'::jsonb) @> ?::jsonb", [current_account.id].to_json).reject { |session| session.players.any? { |player| player.account_id == current_account.id } }
  end

  def open_recruitments
    GameSession.current_kinds.where(status: 'pending').where("state->>'mode' = 'event'").reject { |session| session.state['opened_by'].to_i == current_account.id || session.players.any? { |player| player.account_id == current_account.id } || (Array(session.state['invited']).any? && Array(session.state['invited']).exclude?(current_account.id)) }
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
      shop: shop_item&.shop&.name,
      count: item['count'].to_i,
      note: item['note'].to_s,
      description: shop_item&.description.to_s,
      usable: shop_item.nil? || shop_item.usable,
      giftable: shop_item.nil? || shop_item.giftable,
      permanent: shop_item&.permanent || false,
      effect: shop_item&.effect.to_s,
      # 사용할 때 고를 것 (캐릭터·소속·소문 내용)과 효과 요약 줄
      needs: Game::ItemUse::Runner.needs(shop_item),
      effects: shop_item ? shop_item.summary : [],
      image: shop_item&.image.present? ? full_asset_url(shop_item.image.url(:small)) : nil,
    }
  end

  def record_json(record, other = nil)
    {
      id: record.id.to_s,
      kind: record.kind,
      kind_name: I18n.t("admin.games.shop.kinds.#{record.kind}", default: record.kind),
      money: record.money,
      items: Array(record.items).map { |item| { name: item['name'], count: item['count'].to_i } },
      reason: reason_label(record.reason),
      # 양도·사용의 상대: dir 'to' 내가 상대에게 / 'from' 상대가 나에게
      other: other && { name: GameCharacter.for(other).display_name, acct: other.acct, avatar: full_asset_url(other.avatar_static_url), dir: record.other_dir },
      created_at: record.created_at.iso8601,
    }
  end

  # 컨텐츠 보상의 'game:jellybean' 같은 사유는 컨텐츠 이름으로
  def reason_label(reason)
    key = reason.to_s.split(':').last
    Game::Kinds.keys.include?(key) ? Game::Kinds.fetch(key).display_name : reason.to_s
  end
end
