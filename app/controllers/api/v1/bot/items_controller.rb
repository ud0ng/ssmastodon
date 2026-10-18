# frozen_string_literal: true

# 자동봇 [사용/아이템] : 웹 인벤토리 [사용] 과 같은 규칙 (Game::ItemUse::Runner)
#   POST /api/v1/bot/items/use  { acct: 쓰는 사람, name: 아이템, target: 대상 아이디 또는 random, house: 기숙사 이름/번호, text: 소문 내용 }
#   → { message: 안내 문장, notify: [알릴 아이디] }  (캐릭터 대상이면 봇이 답글에 대상을 멘션해 알린다)
#   안 되면 422 { error: 사용자에게 보여 줄 문구 }
class Api::V1::Bot::ItemsController < Api::V1::Bot::BaseController
  rescue_from Game::ItemUse::Error do |error|
    render json: { error: error.message, code: 'use_failed' }, status: 422
  end

  def use
    character = find_character(params[:acct])
    return render json: { error: 'Character not found', code: 'not_found' }, status: 404 if character.nil?

    entry = Array(character.inventory).find { |item| Game::Wallet.key(item['name']) == Game::Wallet.key(params[:name]) }
    raise Game::ItemUse::Error, "'#{params[:name]}'#{Game::Text.particle(params[:name].to_s.strip[-1], '을를')} 가지고 있지 않습니다." if entry.nil? || entry['count'].to_i <= 0

    shop_item = GameShopItem.all.find { |item| Game::Wallet.key(item.name) == Game::Wallet.key(entry['name']) }
    runner = Game::ItemUse::Runner.new(character.account, entry['name'], target: target_acct, house_id: params[:house], text: params[:text], via: :bot)
    render json: { message: runner.call, needs_target: Game::ItemUse::Runner.needs_target?(shop_item) }
  end

  private

  # 대상은 아이디나 캐릭터 이름 (random 은 그대로). 못 찾으면 이름 그대로 넘겨 러너가 안내한다
  def target_acct
    query = params[:target].to_s.strip
    return query if query.blank? || query == 'random'

    find_character(query)&.account&.username || query
  end
end
