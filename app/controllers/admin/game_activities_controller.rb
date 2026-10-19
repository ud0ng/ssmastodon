# frozen_string_literal: true

module Admin
  # 관리 > 시스템 > 캐릭터 관리 > 활동: 캐릭터마다 전체 툿·글자 수, DM 툿·글자 수, 답 횟수, 미디어 툿 수, 재화.
  # 머리 칸을 누르면 그 칸으로 정렬(오름차순/내림차순). 줄을 누르면 그 캐릭터의 컨텐츠 기록. 위의 [지급]으로 재화나 아이템을 여러 캐릭터에게 준다.
  class GameActivitiesController < BaseController
    include Admin::GameGiveForm

    RECORDS = 30
    SORTS = %w(name posts chars dms dm_chars replies media public_posts public_chars reply_posts reply_chars money).freeze
    # 예전 칸(퍼블 툿·답 툿)의 값은 Game::Activity.stats 에서
    STATS_SORTS = { 'public_posts' => :posts, 'public_chars' => :post_chars, 'reply_posts' => :replies, 'reply_chars' => :reply_chars }.freeze
    helper_method :sort_column, :sort_direction

    def index
      authorize :settings, :show?

      GameCharacter.sync!
      @characters = GameCharacter.visible.includes(:house, :faction, :account).joins(:account)
                                 .order(Arel.sql('accounts.username')).to_a
      ids = @characters.map(&:account_id)
      @activity = Game::Activity.overview(ids)
      @stats = Game::Activity.stats(ids)
      sorted = @characters.sort_by { |character| sort_value(character) }
      @characters = sort_direction == 'desc' ? sorted.reverse : sorted
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
      items = params[:give_kind] == 'items' ? picked_items : {}
      if accounts.empty? || (money.zero? && items.empty?)
        redirect_to give_return_path(modal: 'activity-give'), alert: t('admin.games.activity.give_nothing')
        return
      end

      changes = accounts.map { |account| { account: account, money: money, items: items } }
      Game::Wallet.apply!(changes, kind: 'admin', detail: params[:reason].to_s.strip.presence || t('admin.games.activity.give'), actor: current_account.username)
      notify_given(accounts, money, items)
      redirect_to give_return_path, notice: t('admin.games.activity.given', count: accounts.size)
    end

    private

    # 받은 캐릭터마다 시스템 계정이 DM 으로 알린다 (여러 명이면 한 명씩 따로). 하나가 실패해도 나머지는 보낸다.
    # 지급은 이미 끝난 뒤라(트랜잭션 밖) 멘션 알림이 바로 간다.
    def notify_given(accounts, money, items)
      common = Game::Config.for('common')
      rewards = Game::Rewards.describe(money, items.map { |name, count| { 'name' => name, 'count' => count } }, common['currency_name'])
      text = Game::Text.render(common['msg_admin_give'], rewards: rewards)
      accounts.each do |account|
        Game::Poster.post(text, mentions: [account], thread: nil, visibility: 'direct')
      rescue StandardError => e
        Rails.logger.warn { "admin give notice to #{account.username} failed: #{e.class} #{e.message}" }
      end
    end

    def sort_column
      SORTS.include?(params[:sort]) ? params[:sort] : 'name'
    end

    def sort_direction
      params[:dir] == 'desc' ? 'desc' : 'asc'
    end

    def sort_value(character)
      return [character.display_name.downcase] if sort_column == 'name'
      return [character.money.to_i, character.display_name.downcase] if sort_column == 'money'

      return [@stats[character.account_id].public_send(STATS_SORTS[sort_column]).to_i, character.display_name.downcase] if STATS_SORTS.key?(sort_column)

      [@activity[character.account_id].public_send(sort_column).to_i, character.display_name.downcase]
    end

    # 아이템 고르기(admin/ui/_item_picker): items[][name], items[][count] → { 이름 => 개수 } (상점에 있는 아이템만, 같은 이름은 더한다)
    def picked_items
      known = GameShopItem.pluck(:name).to_set
      Array(params[:items]).each_with_object(Hash.new(0)) do |item, total|
        name = item[:name].to_s.strip
        count = item[:count].to_i
        total[name] += count if known.include?(name) && count.positive?
      end
    end
  end
end
