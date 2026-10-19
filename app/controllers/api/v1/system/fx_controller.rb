# frozen_string_literal: true

# 웹이 아바타 데코·이름 칭호를 그릴 때 보는 한 곳: 지금 효과가 붙은 캐릭터 { 계정 번호 => { title, deco } }
# (계정 정보마다 싣지 않고 여기서만 받아서, 화면마다 받은 시점이 달라 데코가 바뀌어 보이는 일이 없다. components/game_fx)
class Api::V1::System::FxController < Api::BaseController
  before_action -> { doorkeeper_authorize! :read }
  before_action :require_user!

  def show
    render json: { accounts: Game::Fx.all_accounts }
  end
end
