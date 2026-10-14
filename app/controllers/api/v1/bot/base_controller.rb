# frozen_string_literal: true

# 자동봇(ud0ng/ssbot) 전용 API. 자동봇 계정의 토큰으로 부르고, 컨텐츠 설정의 '자동봇 계정 아이디'에 있는 계정만 쓸 수 있다.
class Api::V1::Bot::BaseController < Api::BaseController
  # 읽기(GET)는 read, 바꾸기는 write 권한
  before_action -> { request.get? ? doorkeeper_authorize!(:read) : doorkeeper_authorize!(:write) }
  before_action :require_user!
  before_action :require_bot_account!

  rescue_from Game::Wallet::Error do |error|
    render json: { error: error.message, code: error.code, details: error.details }, status: 422
  end

  private

  def require_bot_account!
    allowed = Game::Config.for('common')['bot_usernames'].to_s.split(/[,\s]+/).map { |name| name.delete_prefix('@').downcase }
    render json: { error: 'This account is not a bot account' }, status: 403 unless allowed.include?(current_account.username.downcase)
  end

  # 아이디(acct, @ 붙어도 됨)나 캐릭터 이름으로 찾는다 (명단에 보이는 캐릭터만)
  def find_character(query)
    query = query.to_s.strip.delete_prefix('@').split('@').first.to_s
    return if query.empty?

    scope = GameCharacter.visible.joins(:account).includes(:house, :faction, :account)
    scope.find_by('lower(accounts.username) = ?', query.downcase) ||
      scope.to_a.find { |character| Game::Wallet.key(character.display_name) == Game::Wallet.key(query) }
  end

  def character_json(character, base_stats = GameCharacterField.base_stats.to_a, statuses = GameCharacterField.statuses.to_a)
    {
      id: character.id.to_s,
      acct: character.account.username,
      name: character.display_name,
      house: character.house&.name,
      faction: character.faction&.name,
      money: character.money,
      items: Array(character.inventory).map { |item| { name: item['name'], count: item['count'].to_i, note: item['note'].to_s } },
      stats: base_stats.map { |field| { name: field.name, value: character.stat_value(field), type: 'stat', min: field.min, max: field.max } } +
        statuses.map { |field| { name: field.name, value: character.status_value(field, base_stats), type: 'status' } },
    }
  end
end
