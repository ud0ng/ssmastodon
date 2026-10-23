# frozen_string_literal: true

module Admin
  # 관리 > 상점 설정 > 재화 기록 / 아이템 기록: 캐릭터(아바타·이름)·획득/차감 배지·검색 (소속·캐릭터·획득/차감·종류·기간)
  # 아이템은 사용·버리기·양도로 줄어든 것이 차감, 구매·보상·지급으로 늘어난 것이 획득.
  class GameShopRecordsController < BaseController
    PER_PAGE = 30
    # 아이템 기록은 한 기록에 아이템이 여러 개라 펼쳐서 거르니, 최근 기록 이만큼까지만 본다
    ITEM_SCAN_LIMIT = 3000
    ItemRow = Struct.new(:record, :name, :count, keyword_init: true)

    before_action :load_filters
    helper_method :filter_params

    def money
      @records = filtered.where.not(money: 0)
      @records = @records.gained if params[:direction] == 'gain'
      @records = @records.spent if params[:direction] == 'spend'
      @records = @records.page(params[:page]).per(PER_PAGE)
      load_names(@records.map(&:account_id))
    end

    def items
      records = filtered.with_items.limit(ITEM_SCAN_LIMIT)
      rows = records.flat_map do |record|
        Array(record.items).map { |item| ItemRow.new(record: record, name: item['name'].to_s, count: item['count'].to_i) }
      end
      rows.reject! { |row| row.count.zero? }
      rows.select! { |row| row.count.positive? } if params[:direction] == 'gain'
      rows.select! { |row| row.count.negative? } if params[:direction] == 'spend'
      if params[:item].present?
        needle = params[:item].to_s.delete(' ').downcase
        rows.select! { |row| row.name.delete(' ').downcase.include?(needle) }
      end
      @rows = Kaminari.paginate_array(rows).page(params[:page]).per(PER_PAGE)
      @item_images = GameShopItem.all.to_h { |item| [Game::Wallet.key(item.name), item.image.present? ? item.image.url(:small) : nil] }
      load_names(@rows.map { |row| row.record.account_id })
    end


    # 누적 수치 기록: 시간 · 캐릭터 · 종류 · 수치(변동값) · 결과값(상성 상쇄 뒤) · 누적치 · 내용
    def counters
      authorize :settings, :show?

      @counter_list = GameCounter.all.to_a
      scope = GameCounterLog.includes(:account, :counter).order(id: :desc)
      scope = scope.where(game_counter_id: params[:counter]) if params[:counter].present?
      scope = scope.where(created_at: Time.zone.parse(params[:from].to_s).beginning_of_day..) if params[:from].present? && Time.zone.parse(params[:from].to_s)
      scope = scope.where(created_at: ..Time.zone.parse(params[:to].to_s).end_of_day) if params[:to].present? && Time.zone.parse(params[:to].to_s)
      ids = character_account_ids
      scope = scope.where(account_id: ids) if ids
      @records = scope.page(params[:page]).per(PER_PAGE)
      load_names(@records.map(&:account_id))
    end
    private

    def filtered
      authorize :settings, :show?

      scope = GameReward.includes(:account).order(id: :desc)
      scope = scope.where(kind: params[:kind]) if GameReward::KINDS.include?(params[:kind].to_s)
      scope = scope.where(created_at: Time.zone.parse(params[:from].to_s).beginning_of_day..) if params[:from].present? && Time.zone.parse(params[:from].to_s)
      scope = scope.where(created_at: ..Time.zone.parse(params[:to].to_s).end_of_day) if params[:to].present? && Time.zone.parse(params[:to].to_s)
      ids = character_account_ids
      ids ? scope.where(account_id: ids) : scope
    end

    # 소속·캐릭터·이름 검색이 하나라도 있으면 그 캐릭터들의 계정 (없으면 nil = 거르지 않음)
    def character_account_ids
      return unless params[:house].present? || params[:character].present? || params[:q].present?

      characters = GameCharacter.joins(:account)
      if params[:house].present?
        mode = GameHouse.mode
        if mode == 'house' || mode == 'faction'
          column = mode == 'faction' ? :game_faction_id : :game_house_id
          characters = characters.where(column => params[:house] == 'none' ? nil : params[:house])
        else
          characters = params[:house] == 'none' ? characters.where('game_characters.extra_group_ids ->> ? IS NULL', mode) : characters.where('game_characters.extra_group_ids ->> ? = ?', mode, params[:house].to_s)
        end
      end
      characters = characters.where(account_id: params[:character]) if params[:character].present?
      if params[:q].present?
        like = "%#{ActiveRecord::Base.sanitize_sql_like(params[:q].to_s.strip.downcase)}%"
        characters = characters.where('lower(accounts.username) LIKE ? OR lower(game_characters.name) LIKE ?', like, like)
      end
      characters.pluck(:account_id)
    end

    def load_filters
      @currency = Game::Config.for('common')['currency_name']
      @house_label = Game::Config.for('common')['house_term'].presence || I18n.t('admin.games.shop.records_ui.house')
      @houses = GameHouse.active.to_a
      @item_names = GameShopItem.order(:name).pluck(:name)
      @characters = GameCharacter.visible.includes(:account).joins(:account).order(Arel.sql('accounts.username')).to_a
    end

    def load_names(account_ids)
      @characters_by_account = GameCharacter.where(account_id: account_ids.uniq).includes(:account).index_by(&:account_id)
    end

    def filter_params
      params.permit(:house, :character, :q, :direction, :kind, :from, :to, :item, :counter).to_h.compact_blank
    end
  end
end
