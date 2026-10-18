# frozen_string_literal: true

module Admin
  # 관리 > 시스템 > 상점 설정: 설정(상점 열기) · 명령어(자동봇 상점·운영진 명령어 이름) · 상점 목록(아이템 추가·지급).
  # 재화 기록·아이템 기록은 Admin::GameShopRecordsController.
  # 자동봇은 /api/v1/bot 으로 같은 데이터를 쓴다 (예전 자동봇 시트의 상점·관리·출석부·기록 워크시트를 대신함).
  class GameShopsController < BaseController
    include Admin::GameGiveForm

    # 설정: 상점 열기
    def settings
      authorize :settings, :show?

      load_currency_form
    end

    # 명령어: 상점 명령어 · 운영진 명령어
    def commands
      authorize :settings, :show?

      load_currency_form
    end

    # 상점 목록
    def index
      authorize :settings, :show?

      GameCharacterField.ensure_defaults!
      # 아이템은 상점(분류) 안에 들어가니 처음에는 하나 만들어 둔다
      GameShop.create!(name: t('admin.games.shop.default_shop'), position: 0) if GameShop.none?
      @shops = GameShop.includes(:items).to_a
      @base_stats = GameCharacterField.stats.pluck(:name)
      # 사용 효과로 고를 수 있는 스탯: 스탯(능력치)은 일시, 상태 수치는 영구 변동
      @stat_options = GameCharacterField.stats.map { |field| ["#{field.name} (#{field.stat? ? I18n.t('admin.games.shop.stat_temporary') : I18n.t('admin.games.shop.stat_permanent')})", field.name] }
      @currency = Game::Config.for('common')['currency_name']
      load_give_form
    end

    def create
      authorize :settings, :update?

      GameShop.create!(shop_params.merge(position: GameShop.count))
      redirect_to admin_game_shops_path, notice: t('generic.changes_saved_msg')
    rescue ActiveRecord::RecordInvalid => e
      redirect_to admin_game_shops_path(modal: 'shop-add'), alert: e.record.errors.full_messages.to_sentence
    end

    def update
      authorize :settings, :update?

      GameShop.find(params[:id]).update!(shop_params)
      redirect_to admin_game_shops_path, notice: t('generic.changes_saved_msg')
    rescue ActiveRecord::RecordInvalid => e
      redirect_to admin_game_shops_path(modal: "shop-#{params[:id]}"), alert: e.record.errors.full_messages.to_sentence
    end

    def destroy
      authorize :settings, :update?

      GameShop.find(params[:id]).destroy!
      redirect_to admin_game_shops_path, notice: t('generic.changes_saved_msg')
    end

    # 명령어·운영진 명령어 저장 (Game::Config 'currency'). 한 묶음만 보내도 나머지 값은 그대로 둔다
    def currency
      authorize :settings, :update?

      Game::Config.merge!('currency', params.fetch(:config, {}).permit!.to_h)
      back = params[:return_to].to_s
      redirect_to (back.start_with?('/admin/shop/') && !back.start_with?('//') ? back : admin_game_shop_settings_path), notice: t('generic.changes_saved_msg')
    end

    private

    # 설정·명령어 화면의 폼: Game::Config 'currency' 묶음별 칸
    def load_currency_form
      @sections = Game::Config.schema('currency').group_by(&:group)
      @values = Game::Config.for('currency')
      @accounts = Account.local.without_instance_actor.without_suspended.order(:username).to_a
    end

    def shop_params
      params.expect(game_shop: [:name, :description, :position])
    end
  end
end
