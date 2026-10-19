# frozen_string_literal: true

# 자동봇 [사용/아이템] : 웹 인벤토리 [사용] 과 같은 규칙 (Game::ItemUse::Runner)
#   POST /api/v1/bot/items/use  { acct: 쓰는 사람, name: 아이템, args: [사용/아이템/…] 뒤에 붙은 말들 (@상대·캐릭터 이름·소속 이름) }
#     (예전 자동봇: target, house, text 도 받는다)
#   → { message: 안내 문장, notify: [상대 아이디] (답글에 멘션해 알린다), needs: { character, house, text } }
#   안 되면 422 { error: 사용자에게 보여 줄 문구 }
class Api::V1::Bot::ItemsController < Api::V1::Bot::BaseController
  rescue_from Game::ItemUse::Error, Game::Wallet::Error do |error|
    render json: { error: error.message, code: 'use_failed' }, status: 422
  end

  def use
    character = find_character(params[:acct])
    return render json: { error: 'Character not found', code: 'not_found' }, status: 404 if character.nil?

    entry = Array(character.inventory).find { |item| Game::Wallet.key(item['name']) == Game::Wallet.key(params[:name]) }
    raise Game::ItemUse::Error, "'#{params[:name]}'#{Game::Text.particle(params[:name].to_s.strip[-1], '을를')} 가지고 있지 않습니다." if entry.nil? || entry['count'].to_i <= 0

    shop_item = GameShopItem.all.find { |item| Game::Wallet.key(item.name) == Game::Wallet.key(entry['name']) }
    args = params.key?(:args) ? Array(params[:args]) : [params[:target], params[:house]].compact_blank
    runner = Game::ItemUse::Runner.from_args(character.account, entry['name'], args, via: :bot)
    message = runner.call
    target = runner.target
    render json: { message: message, notify: target && target.id != character.account_id ? [target.username] : [], needs: Game::ItemUse::Runner.needs(shop_item) }
  end
end
