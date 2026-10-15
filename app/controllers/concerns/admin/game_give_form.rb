# frozen_string_literal: true

# 지급 모달(admin/game_activities/_give_modal)에 필요한 것: 받을 캐릭터 목록, 상점 아이템(이름·그림), 재화 이름.
# 활동 탭과 상점 탭이 같이 쓴다. 지급 뒤에는 return_to(관리 화면 주소)로 돌아간다.
module Admin::GameGiveForm
  extend ActiveSupport::Concern

  private

  def load_give_form
    @currency = Game::Config.for('common')['currency_name']
    @give_characters = GameCharacter.visible.includes(:account).joins(:account).order(Arel.sql('accounts.username')).to_a
    @shop_items = GameShopItem.order(:name).map { |item| [item.name, item.image.present? ? item.image.url(:small) : nil] }
  end

  # 돌아갈 곳: 이 서버의 관리 화면 주소만 (그 밖이면 활동 탭)
  def give_return_path(**query)
    path = params[:return_to].to_s
    path = admin_game_activities_path unless path.start_with?('/admin/') && !path.start_with?('//')
    query.any? ? "#{path}?#{query.to_query}" : path
  end
end
