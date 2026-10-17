# frozen_string_literal: true

# 웹 인벤토리 아이템 모달: [사용] [선물] [버리기] (자동봇 [사용]·[양도]·[소모]와 같은 규칙)
class Api::V1::System::ItemsController < Api::BaseController
  before_action -> { doorkeeper_authorize! :write }
  before_action :require_user!
  before_action :set_item

  class UseError < StandardError; end

  MAX_HOWLER = 200

  # [사용]: 아이템의 사용 대상에 따라
  #   stat       스탯을 바꾼다 (스탯 유형 '스탯'은 일시, '상태 수치'는 영구). 스탯을 정하지 않았으면 소모만
  #   character  태그한 캐릭터(본인도 가능, 랜덤 1인 가능한 아이템도 있다)에게 쓴다: 스탯·착용이 적용되고 본인이 아니면 시스템 DM 으로 알린다
  #   special    특수: 시스템 계정에 DM (staff) / 캐릭터 신고 (report) / 기숙사 점수 차감 (bomb) / 소문 내기 (howler)
  def use
    shop_item = shop_item_for(@name)
    return fail!("#{@name}#{particle(@name, '은는')} 사용할 수 없는 아이템입니다.") if shop_item && !shop_item.usable

    field = shop_item&.stat_field
    return fail!("'#{shop_item.stat_name}' 스탯이 없습니다. 운영진에게 문의해 주세요.") if shop_item&.stat_name.present? && field.nil?

    render json: { message: use_item!(shop_item, field) }
  rescue UseError => e
    fail!(e.message)
  rescue Game::Dice::Error
    fail!('아이템 수치가 잘못되었습니다. 운영진에게 문의해 주세요.')
  rescue Game::Wallet::Error => e
    fail!(e.message)
  end

  def gift
    return fail!('지금은 선물할 수 없습니다.') unless Game::Config.for('currency')['transfer_enabled']

    shop_item = GameShopItem.all.find { |item| Game::Wallet.key(item.name) == Game::Wallet.key(@name) }
    return fail!("#{@name}#{particle(@name, '은는')} 선물할 수 없는 아이템입니다.") if shop_item && !shop_item.giftable

    receiver = GameCharacter.eligible_accounts.where.not(id: current_account.id).find_by(username: params[:acct].to_s.delete_prefix('@'))
    return fail!('받을 사람을 골라 주세요.') if receiver.nil?

    name = GameCharacter.for(receiver).display_name
    apply!([{ account: current_account, items: { @name => -@count } }, { account: receiver, items: { @name => @count } }],
           'transfer', "#{@name} #{@count}개 → #{name}")
    notify_receiver(receiver)
    render json: { message: "#{name}에게 #{@name} #{@count}개#{particle('개', '을를')} 선물했습니다." }
  rescue Game::Wallet::Error => e
    fail!(e.message)
  end

  def discard
    apply!([{ account: current_account, items: { @name => -@count } }], 'consume', "#{@name} #{@count}개 버림")
    render json: { message: "#{@name} #{@count}개#{particle('개', '을를')} 버렸습니다." }
  rescue Game::Wallet::Error => e
    fail!(e.message)
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
    target ||= current_account

    house = pick_house! if special == 'bomb'
    rumor = pick_rumor! if special == 'howler'

    delta = field && shop_item.stat_value.present? ? Game::Dice.amount(shop_item.stat_value) : nil
    temporary = field&.stat?
    target_character = GameCharacter.for(target)
    before = field && delta ? (temporary ? target_character.stat_value(field) : target_character.status_value(field)) : nil

    changes = [{ account: current_account, items: { @name => -1 } }]
    if delta && !temporary
      # 상태 수치는 영구 변동: 본인이면 한 번에 합친다
      if target.id == current_account.id
        changes.first[:stats] = { field.name => delta }
      else
        changes << { account: target, stats: { field.name => delta } }
      end
    end

    result = nil
    GameCharacter.transaction do
      Game::Wallet.apply!(changes, kind: 'use', detail: use_detail(kind, special, target, house), actor: 'web')
      target_character.reload
      target_character.add_effect!(stat: field.name, delta: delta, minutes: shop_item.stat_minutes, item: @name) if delta && temporary
      target_character.add_wear!(label: shop_item.wear_label, minutes: shop_item.stat_minutes, item: @name) if shop_item&.wearable? && kind == 'character'
      result = use_special!(shop_item, special, target, house, rumor) if special
    end

    target_character.reload
    effect = effect_text(field, delta, temporary, shop_item, before, target_character)
    notify_target(target, effect, shop_item) if kind == 'character'
    use_message(kind, target, effect, result)
  end

  # 캐릭터를 태그해서 쓰는 아이템의 대상 (acct 가 random 이고 랜덤을 허용하는 아이템이면 다른 서버원 중 한 명)
  def pick_character!(shop_item, allow_self:)
    if params[:acct].to_s == 'random'
      raise UseError, '이 아이템은 랜덤으로 쓸 수 없습니다.' unless shop_item&.allow_random

      target = GameCharacter.eligible_accounts.where.not(id: current_account.id).order(Arel.sql('RANDOM()')).first
      raise UseError, '랜덤으로 고를 사람이 없습니다.' if target.nil?

      return target
    end

    target = GameCharacter.eligible_accounts.find_by(username: params[:acct].to_s.delete_prefix('@'))
    raise UseError, '아이템을 쓸 캐릭터를 골라 주세요.' if target.nil?
    raise UseError, '자신에게는 쓸 수 없습니다.' if !allow_self && target.id == current_account.id

    target
  end

  def pick_house!
    house = GameHouse.active.find { |item| item.id.to_s == params[:house_id].to_s }
    raise UseError, '점수를 깎을 기숙사를 골라 주세요.' if house.nil?

    house
  end

  def pick_rumor!
    text = params[:text].to_s.strip.delete('@＠')[0, MAX_HOWLER]
    raise UseError, '소문 내용을 적어 주세요.' if text.blank?

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
      name = target.id == current_account.id ? '자신' : GameCharacter.for(target).display_name
      "#{name}에게 #{@name}#{particle(@name, '을를')} 사용했습니다.#{effect}"
    when 'special'
      "#{@name}#{particle(@name, '을를')} 사용했습니다. #{result}"
    else
      "#{@name}#{particle(@name, '을를')} 사용했습니다.#{effect}"
    end
  end

  # 특수 아이템: 쓴 사람이 시스템 계정에 DM 을 보낸 것처럼 남기고(운영진이 확인), 종류에 따라 점수·소문을 처리한다. 결과 안내 문장을 돌려준다.
  def use_special!(shop_item, special, target, house, rumor)
    case special
    when 'report' then use_report!(shop_item, target)
    when 'bomb' then use_bomb!(shop_item, house)
    when 'howler' then use_howler!(rumor)
    else
      send_system_dm!('')
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
    send_system_dm!("#{name} 신고 (누적 #{count}회#{volunteer ? ', 봉사활동 대상' : ''})")
    notice = "교내 신고가 접수되었습니다. (누적 #{count}회)"
    notice += ' 누적 한도를 넘어 교수님께서 봉사활동을 시키실 거예요.' if volunteer
    Game::Gift.notify(notice, target)
    "#{name}#{particle(name, '을를')} 신고했습니다. (누적 #{count}회)#{volunteer ? ' 한도를 넘어 봉사활동 대상이 되었습니다.' : ''}"
  end

  def use_bomb!(shop_item, house)
    deduct!(house, shop_item.score_delta, "#{@name} → #{house.name}")
    send_system_dm!("#{house.name} 점수 #{shop_item.score_delta}")
    "#{house.name}에 똥폭탄을 던졌습니다. (소속 점수 #{shop_item.score_delta})"
  end

  # 호울러: 내용을 모든 서버원에게 DM 으로 소문처럼 보낸다 (누가 보냈는지는 밝히지 않는다. 운영진 DM 에는 남는다)
  def use_howler!(text)
    send_system_dm!(text)
    everyone = GameCharacter.eligible_accounts.to_a
    Game::Poster.post("호울러가 울려 퍼집니다!\n#{text}", mentions: everyone, thread: nil, visibility: 'direct') if everyone.any?
    '호울러가 호그와트 전체에 울려 퍼졌습니다.'
  end

  def deduct!(house, amount, reason)
    return if house.nil? || amount.zero?

    GameHousePoint.create!(house: house, account: current_account, amount: amount, reason: reason.to_s.truncate(200))
  end

  # 쓴 사람이 시스템 계정에 DM 을 보낸 것처럼 남긴다 (운영진 확인용)
  def send_system_dm!(extra)
    system = Game::System.account
    raise UseError, '시스템 계정을 찾지 못했습니다. 운영진에게 문의해 주세요.' if system.nil?

    PostStatusService.new.call(current_account, text: "@#{system.username} [사용/#{@name}] #{extra}".strip, visibility: 'direct')
  end

  def notify_target(target, effect, shop_item)
    note = shop_item&.effect.presence
    Game::Gift.notify(Game::Config.for('common')['msg_item_use'], target, from: current_account, player: current_account, target: target, item: @name, effect: [effect, note].compact_blank.join("\n"))
  end

  # 인벤토리에 있는 이름 그대로 (공백·대소문자 무시)
  def set_item
    @character = GameCharacter.for(current_account)
    entry = Array(@character.inventory).find { |item| Game::Wallet.key(item['name']) == Game::Wallet.key(params[:name]) }
    return fail!('가지고 있지 않은 아이템입니다.') if entry.nil? || params[:name].blank?

    @name = entry['name']
    @count = params[:count].to_i.clamp(1, [entry['count'].to_i, 1].max)
  end

  def notify_receiver(receiver)
    Game::Gift.notify(Game::Config.for('common')['msg_gift_item'], receiver, from: current_account, player: current_account, target: receiver, item: @name, count: @count)
  end

  def apply!(changes, kind, detail)
    Game::Wallet.apply!(changes, kind: kind, detail: detail, actor: 'web').first
  end

  def particle(word, key)
    Game::Text.particle(word.to_s.strip[-1], key)
  end

  def fail!(message)
    render json: { error: message }, status: 422
  end
end
