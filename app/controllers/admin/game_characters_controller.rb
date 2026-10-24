# frozen_string_literal: true

module Admin
  # 관리 > 시스템 > 캐릭터 관리 > 명단: 회원 목록에서 자동으로 만들어지는 캐릭터를 소속별 표로 보고,
  # 캐릭터를 눌러 상세 화면(소속·스탯·메모·전적)에서 고친다. 재화·인벤토리는 활동 탭.
  class GameCharactersController < BaseController
    include Admin::GameGiveForm

    PER_PAGE = 100

    helper_method :filter_params, :roster_sort

    def index
      authorize :settings, :show?

      GameHouse.ensure_defaults!
      GameCharacterField.ensure_defaults!
      GameCharacter.sync!
      load_columns
      @counter_groups = helpers.game_counter_groups(GameCounter.includes(:opposite).to_a)
      scope = filtered.includes(:house, :faction, account: :user)
                      .order(Arel.sql('game_houses.position NULLS LAST, game_houses.id NULLS LAST, accounts.username'))
      # 머리 칸을 누르면 그 칸으로 정렬 (활동 탭 표처럼, 같은 칸을 다시 누르면 반대로). 고르지 않으면 소속 순서
      @characters = if roster_sort.first
                      Kaminari.paginate_array(sorted_characters(scope.to_a)).page(params[:page]).per(PER_PAGE)
                    else
                      scope.page(params[:page]).per(PER_PAGE)
                    end
    end

    # 명단에서 소속·진영을 눌러 바로 바꾼다 (kind: house|faction, value: 소속 번호, 비우면 없음)
    def assign_group
      authorize :settings, :update?

      character = GameCharacter.find(params[:id])
      value = params[:value].presence
      return head :unprocessable_entity unless GameHouse.categories.include?(params[:kind].to_s)

      character.assign_group!(params[:kind].to_s, value && GameHouse.where(category: params[:kind].to_s).find(value))
      head :no_content
    rescue ActiveRecord::RecordNotFound, ActiveRecord::RecordInvalid
      head :unprocessable_entity
    end

    # 상세 화면
    def edit
      authorize :settings, :show?

      GameCharacterField.ensure_defaults!
      @character = GameCharacter.find(params[:id])
      prepare_form
    end

    def update
      authorize :settings, :update?

      @character = GameCharacter.find(params[:id])
      prepare_form
      @character.assign_attributes(character_params.slice(:name, :game_house_id, :game_faction_id, :note))
      @character.stats = stat_values if GameCharacterField.stats.exists? # 스탯이 하나도 없으면 화면에 칸이 없으니 저장된 값을 그대로 둔다
      if @character.save
        update_counters!
        redirect_to edit_admin_game_character_path(@character, filter_params), notice: t('generic.changes_saved_msg')
      else
        render :edit
      end
    end

    # 상세 > 효과 카드: 칭호·데코·스킨을 직접 붙인다
    def add_effect
      authorize :settings, :update?

      character = GameCharacter.find(params[:id])
      effect = GameEffect.find_by(id: params[:effect_id], kind: 'character')
      return redirect_to(edit_admin_game_character_path(character, filter_params), alert: t('admin.games.fx.bad_effect')) if effect.nil?

      entry = Admin::GameFxTime.entry(effect, params).merge('kind' => 'fx', 'item' => t('admin.games.fx.by_admin'))
      character.update!(effects: character.active_effects + [entry])
      Game::Fx.expire!(character.account_id)
      redirect_to edit_admin_game_character_path(character, filter_params), notice: t('generic.changes_saved_msg')
    end

    # 상세 > 효과 카드: 끝나는 때 고치기 (permanent=1 이면 영구)·지우기
    def update_effect
      authorize :settings, :update?

      character = GameCharacter.find(params[:id])
      time = Admin::GameFxTime.parse(params)
      return redirect_to(edit_admin_game_character_path(character, filter_params), alert: t('admin.games.fx.bad_time')) if time.nil?

      character.update!(effects: Game::Fx.change_entry(character.effects, params[:index], params[:effect_id], time))
      Game::Fx.expire!(character.account_id)
      redirect_to edit_admin_game_character_path(character, filter_params), notice: t('generic.changes_saved_msg')
    end

    def remove_effect
      authorize :settings, :update?

      character = GameCharacter.find(params[:id])
      character.update!(effects: Game::Fx.change_entry(character.effects, params[:index], params[:effect_id], nil))
      Game::Fx.expire!(character.account_id)
      redirect_to edit_admin_game_character_path(character, filter_params), notice: t('generic.changes_saved_msg')
    end

    # 상세 > 인벤토리 카드: 아이템 더하기 (이름이 같으면 개수만 더한다)
    def add_item
      authorize :settings, :update?

      character = GameCharacter.find(params[:id])
      item = item_params
      if item['name'].present?
        character.with_lock do
          inventory = Array(character.inventory).map(&:dup)
          existing = inventory.find { |entry| Game::Wallet.key(entry['name']) == Game::Wallet.key(item['name']) }
          if existing
            existing['count'] = existing['count'].to_i + item['count']
            existing['note'] = item['note'] if item['note'].present?
          else
            inventory << item
          end
          character.update!(inventory: inventory)
        end
      end
      redirect_to edit_admin_game_character_path(character, filter_params), notice: t('generic.changes_saved_msg')
    end

    # 인벤토리 카드: 개수·메모 고치기 (그사이 그 자리의 아이템이 바뀌었으면 고치지 않는다)
    def update_item
      authorize :settings, :update?

      change_item { |inventory, index| inventory[index] = item_params.merge('name' => inventory[index]['name']) }
    end

    def remove_item
      authorize :settings, :update?

      change_item { |inventory, index| inventory.delete_at(index) }
    end

    private

    def load_columns
      @houses = GameHouse.houses.to_a
      @factions = GameHouse.factions.to_a
      @extra_kinds = Game::GroupKinds.extras.map { |kind| [kind, GameHouse.where(category: kind['key']).to_a] }
      @labels = Game::Config.for('common').slice('house_label', 'faction_label')
      @base_stats = GameCharacterField.base_stats.to_a
      @statuses = GameCharacterField.statuses.to_a
      @currency = Game::Config.for('common')['currency_name']
    end

    # 상세 화면: 전적(승·패·무)과 최근 판
    def prepare_form
      load_columns
      @counters = GameCounter.includes(:opposite).to_a
      finished = GamePlayer.joins(:session).merge(GameSession.real).where(account_id: @character.account_id, game_sessions: { status: 'finished' })
      @record = finished.group(:result).count
      @item_images = GameShopItem.by_key
      load_give_form
    end

    def filter_params
      { q: params[:q], house: params[:house], faction: params[:faction], groups: params[:groups]&.permit!&.to_h, sort: params[:sort], dir: params[:dir] }.compact_blank
    end

    # 명단 정렬: [칸, 방향]. 칸은 name / house / faction / money / group:<종류> / counter:<번호> / stat:<번호> / status:<번호>
    def roster_sort
      key = params[:sort].to_s
      key = nil unless key.match?(/\A(name|house|faction|money|(group|counter|stat|status):[\w-]+)\z/)
      [key, params[:dir] == 'desc' ? 'desc' : 'asc']
    end

    # 고른 칸의 값으로 세운다 (같은 값이면 원래 소속 순서). 값이 없는 칸(소속 없음 등)은 늘 맨 뒤
    def sorted_characters(list)
      key, direction = roster_sort
      kind, id = key.split(':', 2)
      houses = GameHouse.all.index_by(&:id)
      fields = GameCharacterField.all.index_by { |field| field.id.to_s }
      counters = GameCounter.includes(:opposite).index_by { |counter| counter.id.to_s }
      base = GameCharacterField.base_stats.to_a
      value = lambda do |character|
        case kind
        when 'name' then character.display_name.to_s.downcase
        when 'house', 'faction'
          house = houses[kind == 'house' ? character.game_house_id : character.game_faction_id]
          house && [house.position.to_i, house.name.to_s]
        when 'group'
          house = houses[character.extra_group_ids[id].to_i]
          house && [house.position.to_i, house.name.to_s]
        when 'money' then character.money.to_i
        when 'counter' then counters[id]&.net_for(character).to_i
        when 'stat' then fields[id] && character.stat_value(fields[id]).to_i
        when 'status' then fields[id] && character.status_value(fields[id], base)
        end
      end
      present, missing = list.each_with_index.map { |character, index| [character, value.call(character), index] }.partition { |_, each, _| !each.nil? }
      sorted = present.sort_by { |_, each, index| [each, index] }.map(&:first)
      sorted.reverse! if direction == 'desc'
      sorted + missing.map(&:first)
    end

    # 스탯: 정의된 스탯만, 최소~최대 안으로 (비우면 저장하지 않아 최소치)
    def stat_values
      given = character_params[:stat_values].to_h
      GameCharacterField.base_stats.each_with_object({}) do |field, values|
        value = given[field.name].to_s.strip
        values[field.name] = field.clamp(value).to_s if value.present?
      end
    end

    # 누적 수치: 바뀐 누적치만 add! 로 (누적 효과·기록이 함께 맞춰진다)
    def update_counters!
      given = character_params[:counter_values].to_h
      @counters.each do |counter|
        value = given[counter.id.to_s].to_s.strip
        next if value.blank?

        delta = [value.to_i, 0].max - counter.raw_for(@character.reload)
        counter.add!(@character, delta, reason: helpers.game_t('admin.games.manage.detail.counter_reason'), actor: current_account.username) unless delta.zero?
      end
    end

    # 인벤토리 아이템 한 개: 이름, 개수(1 이상), 메모
    def item_params
      item = params.expect(item: [:name, :count, :note])
      { 'name' => item[:name].to_s.strip.first(50), 'count' => [item[:count].to_i, 1].max, 'note' => item[:note].to_s.strip.first(200) }
    end

    def change_item
      character = GameCharacter.find(params[:id])
      index = params[:index].to_i
      character.with_lock do
        inventory = Array(character.inventory).map(&:dup)
        if inventory[index] && inventory[index]['name'] == params[:original_name].to_s
          yield inventory, index
          character.update!(inventory: inventory)
          flash[:notice] = t('generic.changes_saved_msg')
        else
          flash[:alert] = t('admin.games.manage.detail.item_conflict')
        end
      end
      redirect_to edit_admin_game_character_path(character, filter_params)
    end

    def filtered
      scope = GameCharacter.visible.joins(:account).left_joins(:house)
      if params[:q].present?
        query = "%#{ActiveRecord::Base.sanitize_sql_like(params[:q].strip)}%"
        scope = scope.where('game_characters.name ILIKE :q OR accounts.username ILIKE :q OR accounts.display_name ILIKE :q', q: query)
      end
      scope = params[:house] == 'none' ? scope.where(game_house_id: nil) : scope.where(game_house_id: params[:house]) if params[:house].present?
      scope = params[:faction] == 'none' ? scope.where(game_faction_id: nil) : scope.where(game_faction_id: params[:faction]) if params[:faction].present?
      Game::GroupKinds.extras.each do |kind|
        value = params.dig(:groups, kind['key']).presence
        next if value.nil?

        scope = value == 'none' ? scope.where('game_characters.extra_group_ids ->> ? IS NULL', kind['key']) : scope.where('game_characters.extra_group_ids ->> ? = ?', kind['key'], value.to_s)
      end
      scope
    end

    def character_params
      params.require(:game_character).permit(:name, :game_house_id, :game_faction_id, :note, stat_values: {}, counter_values: {})
    end
  end
end
