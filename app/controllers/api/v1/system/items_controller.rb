# frozen_string_literal: true

# 웹 인벤토리 아이템 모달: [사용] [선물] [버리기] (자동봇 [사용]·[양도]·[소모]와 같은 규칙)
class Api::V1::System::ItemsController < Api::BaseController
  before_action -> { doorkeeper_authorize! :write }
  before_action :require_user!
  before_action :set_item

  def use
    shop_item = GameShopItem.all.find { |item| Game::Wallet.key(item.name) == Game::Wallet.key(@name) }
    return fail!("#{@name}#{particle(@name, '은는')} 사용할 수 없는 아이템입니다.") if shop_item && !shop_item.usable

    stats = {}
    if shop_item&.stat_name.present? && shop_item.stat_value.present?
      # 자동봇 [사용]과 같이: 연결된 스탯이 지워졌으면 쓰지 않는다
      stat = GameCharacterField.base_stats.find { |field| Game::Wallet.key(field.name) == Game::Wallet.key(shop_item.stat_name) }
      return fail!("'#{shop_item.stat_name}' 스탯이 없습니다. 운영진에게 문의해 주세요.") if stat.nil?

      stats[stat.name] = Game::Dice.amount(shop_item.stat_value)
      before = @character.stat_value(stat)
    end

    character = apply!([{ account: current_account, items: { @name => -1 }, stats: stats }], 'use', @name)
    message = "#{@name}#{particle(@name, '을를')} 사용했습니다."
    message += " ➭ #{stat.name} #{format('%+d', stats[stat.name])} (#{before} → #{character.stat_value(stat)})" if stats.any?
    render json: { message: message }
  rescue Game::Dice::Error
    fail!('아이템 수치가 잘못되었습니다. 운영진에게 문의해 주세요.')
  rescue Game::Wallet::Error => e
    fail!(e.message)
  end

  def gift
    return fail!('지금은 선물할 수 없습니다.') unless Game::Config.for('currency')['transfer_enabled']

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

  # 인벤토리에 있는 이름 그대로 (공백·대소문자 무시)
  def set_item
    @character = GameCharacter.for(current_account)
    entry = Array(@character.inventory).find { |item| Game::Wallet.key(item['name']) == Game::Wallet.key(params[:name]) }
    return fail!('가지고 있지 않은 아이템입니다.') if entry.nil? || params[:name].blank?

    @name = entry['name']
    @count = params[:count].to_i.clamp(1, [entry['count'].to_i, 1].max)
  end

  def notify_receiver(receiver)
    Game::Gift.notify(Game::Config.for('common')['msg_gift_item'], receiver, player: current_account, target: receiver, item: @name, count: @count)
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
