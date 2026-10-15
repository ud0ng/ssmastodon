# frozen_string_literal: true

module Admin
  # 관리 > 시스템 > 캐릭터 관리 > 활동: 캐릭터마다 퍼블 툿·답 툿 수와 글자 수, 재화.
  # 줄을 누르면 상세 (활동·재화 내역·인벤토리). 위의 [지급]으로 재화나 아이템을 여러 캐릭터에게 준다.
  class GameActivitiesController < BaseController
    RECORDS = 30

    def index
      authorize :settings, :show?

      GameCharacter.sync!
      @characters = GameCharacter.visible.includes(:house, :faction, :account).joins(:account)
                                 .order(Arel.sql('accounts.username')).to_a
      @stats = Game::Activity.stats(@characters.map(&:account_id))
      load_give_form
    end

    def show
      authorize :settings, :show?

      @character = GameCharacter.visible.find(params[:id])
      @stats = Game::Activity.stats([@character.account_id])[@character.account_id]
      @records = GameReward.where(account_id: @character.account_id).order(id: :desc).limit(RECORDS)
      @item_images = GameShopItem.by_key
      @shop_item_names = GameShopItem.pluck(:name)
      @currency = Game::Config.for('common')['currency_name']
      @rule = Game::Activity.reward_rule
    end

    # 지급: 재화(kind money) 또는 아이템(kind items)을 고른 캐릭터들에게
    def give
      authorize :settings, :update?

      accounts = GameCharacter.visible.where(id: Array(params[:character_ids])).includes(:account).map(&:account)
      money = params[:give_kind] == 'money' ? [params[:money].to_i, 0].max : 0
      items = if params[:give_kind] == 'items'
                count = [params[:count].to_i, 1].max
                GameShopItem.where(name: Array(params[:item_names])).pluck(:name).index_with { count }
              else
                {}
              end
      if accounts.empty? || (money.zero? && items.empty?)
        redirect_to admin_game_activities_path(modal: 'activity-give'), alert: t('admin.games.activity.give_nothing')
        return
      end

      changes = accounts.map { |account| { account: account, money: money, items: items } }
      Game::Wallet.apply!(changes, kind: 'admin', detail: params[:reason].to_s.strip.presence || t('admin.games.activity.give'), actor: current_account.username)
      redirect_to admin_game_activities_path, notice: t('admin.games.activity.given', count: accounts.size)
    end

    private

    def load_give_form
      @currency = Game::Config.for('common')['currency_name']
      @shop_item_names = GameShopItem.pluck(:name)
    end
  end
end
