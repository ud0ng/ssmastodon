# frozen_string_literal: true

module Admin
  # 컨텐츠 설정 > 상점의 아이템 추가·수정·삭제 (모달)
  class GameShopItemsController < BaseController
    def create
      authorize :settings, :update?

      shop = GameShop.find(item_params[:game_shop_id])
      shop.items.create!(item_params.merge(position: shop.items.count))
      redirect_to admin_game_shops_path, notice: t('generic.changes_saved_msg')
    rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotFound => e
      redirect_to admin_game_shops_path(modal: 'item-add'), alert: e.respond_to?(:record) ? e.record.errors.full_messages.to_sentence : e.message
    end

    def update
      authorize :settings, :update?

      GameShopItem.find(params[:id]).update!(item_params)
      redirect_to admin_game_shops_path, notice: t('generic.changes_saved_msg')
    rescue ActiveRecord::RecordInvalid => e
      redirect_to admin_game_shops_path(modal: "item-#{params[:id]}"), alert: e.record.errors.full_messages.to_sentence
    end

    def destroy
      authorize :settings, :update?

      GameShopItem.find(params[:id]).destroy!
      redirect_to admin_game_shops_path, notice: t('generic.changes_saved_msg')
    end

    private

    # 가격을 비우면 비매품, 스탯을 비우면 수치도 지운다
    def item_params
      permitted = params.expect(game_shop_item: [:game_shop_id, :name, :price, :description, :usable, :giftable, :use_target, :stat_minutes, :effect, :special_kind, :score_delta, :special_limit, :allow_random, :wear_label, :stat_name, :stat_value, :position, :image, :remove_image])
      permitted[:image] = nil if permitted.delete(:remove_image) == '1'
      permitted[:price] = permitted[:price].presence
      permitted[:stat_value] = '' if permitted[:stat_name].blank?
      permitted
    end
  end
end
