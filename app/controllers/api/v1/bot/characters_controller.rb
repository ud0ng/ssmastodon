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

    characters = Game::Wallet.apply!(changes, kind: kind, detail: params[:detail], actor: params[:actor].presence || current_account.username,
                                              once_per_day: ActiveModel::Type::Boolean.new.cast(params[:once_per_day]))
    base_stats = GameCharacterField.base_stats.to_a
    statuses = GameCharacterField.statuses.to_a
    render json: { characters: characters.map { |character| character_json(character, base_stats, statuses) } }
  end
end
