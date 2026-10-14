# frozen_string_literal: true

# 웹 게임 화면에서 상대 고르기: 컨텐츠에 낄 수 있는 서버원과 캐릭터 이름·소속
class Api::V1::System::MembersController < Api::BaseController
  before_action -> { doorkeeper_authorize! :read }
  before_action :require_user!

  def index
    accounts = GameCharacter.eligible_accounts.where.not(id: current_account.id).order(:username)
    characters = GameCharacter.where(account_id: accounts.select(:id)).includes(:house, :faction).index_by(&:account_id)
    render json: accounts.map { |account|
      character = characters[account.id]
      group = character&.group
      {
        acct: account.acct,
        name: character&.display_name || account.display_name.presence || account.username,
        avatar: account.avatar_static_url,
        house: group && { name: group.name, color: group.color, emoji: group.emoji },
      }
    }
  end
end
