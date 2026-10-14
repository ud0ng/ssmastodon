# frozen_string_literal: true

module Admin
  # 관리 > 시스템 > 컨텐츠 설정 > 상점: 상점 목록·아이템 목록, 재화 규칙(양도·출석·툿 보상·도움말), 최근 재화 기록.
  # 자동봇은 /api/v1/bot 으로 같은 데이터를 쓴다 (예전 자동봇 시트의 상점·관리·출석부·기록 워크시트를 대신함).
  class GameShopsController < BaseController
    def index
      authorize :settings, :show?

      GameCharacterField.ensure_defaults!
      @shops = GameShop.includes(:items).to_a
      @base_stats = GameCharacterField.base_stats.pluck(:name)
      @currency = Game::Config.for('common')['currency_name']
      @fields = Game::Config.schema('currency')
      @values = Game::Config.for('currency')
      @records = GameReward.includes(:account).order(id: :desc).limit(30)
      @names = GameCharacter.where(account_id: @records.map(&:account_id)).to_h { |character| [character.account_id, character.display_name] }
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

    # 재화 규칙 저장 (Game::Config 'currency')
    def currency
      authorize :settings, :update?

      Game::Config.update!('currency', params.fetch(:config, {}).permit!.to_h)
      redirect_to admin_game_shops_path, notice: t('generic.changes_saved_msg')
    end

    private

    def shop_params
      params.expect(game_shop: [:name, :description, :position])
    end
  end
end
