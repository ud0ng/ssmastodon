# frozen_string_literal: true

# 웹 인벤토리 아이템 모달: [사용] [선물] [버리기] (자동봇 [사용]·[양도]·[버리기]와 같은 규칙)
class Api::V1::System::ItemsController < Api::BaseController
  before_action -> { doorkeeper_authorize! :write }
  before_action :require_user!
  before_action :set_item

  # [사용]: 규칙은 Game::ItemUse::Runner (자동봇 [사용]과 같다)
  #   params: name, acct (캐릭터를 고르는 효과: 아이디), house_id (소속을 고르는 효과), text (소문내기 내용)
  def use
    runner = Game::ItemUse::Runner.new(current_account, @name, target: params[:acct], house_id: params[:house_id], text: params[:text], via: :web)
    render json: { message: runner.call }
  rescue Game::ItemUse::Error, Game::Wallet::Error => e
    fail!(e.message)
  end

  def gift
    return fail!('지금은 선물할 수 없습니다.') unless Game::Config.for('currency')['transfer_enabled']

    shop_item = GameShopItem.all.find { |item| Game::Wallet.key(item.name) == Game::Wallet.key(@name) }
    return fail!("#{@name}#{particle(@name, '은는')} 선물할 수 없는 아이템입니다.") if shop_item && !shop_item.giftable

    receiver = GameCharacter.eligible_accounts.where.not(id: current_account.id).find_by(username: params[:acct].to_s.delete_prefix('@'))
    return fail!('받을 사람을 골라 주세요.') if receiver.nil?

    name = GameCharacter.for(receiver).display_name
    apply!([{ account: current_account, items: { @name => -@count }, other: receiver, other_dir: 'to' }, { account: receiver, items: { @name => @count }, other: current_account, other_dir: 'from' }],
           'transfer', "#{@name} #{@count}개 → #{name}")
    announce!(['양도', "#{@name}: #{@count}", name], Game::Text.render(Game::Config.for('common')['msg_gift_item'], player: current_account, target: receiver, item: @name, count: @count), receivers: [receiver])
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

  # 쓴 사람이 직접 보내는 툿 (받는 사람·상점 봇 멘션 + 명령어 모양). Game::Gift.announce
  def announce!(command, text, receivers: [], system: false, visibility: 'direct')
    Game::Gift.announce(current_account, command: command, text: text, receivers: receivers, system: system, visibility: visibility)
  end

  # 인벤토리에 있는 이름 그대로 (공백·대소문자 무시)
  def set_item
    @character = GameCharacter.for(current_account)
    entry = Array(@character.inventory).find { |item| Game::Wallet.key(item['name']) == Game::Wallet.key(params[:name]) }
    return fail!('가지고 있지 않은 아이템입니다.') if entry.nil? || params[:name].blank?

    @name = entry['name']
    @count = params[:count].to_i.clamp(1, [entry['count'].to_i, 1].max)
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
