# frozen_string_literal: true

module Admin
  # 관리 > 시스템 > 캐릭터 관리 > 명단: 회원 목록에서 자동으로 만들어지는 캐릭터를 소속별 표로 보고,
  # 캐릭터를 눌러 상세 화면(소속·스탯·메모·전적)에서 고친다. 재화·인벤토리는 활동 탭.
  class GameCharactersController < BaseController
    PER_PAGE = 100

    helper_method :filter_params

    def index
      authorize :settings, :show?

      GameHouse.ensure_defaults!
      GameCharacterField.ensure_defaults!
      GameCharacter.sync!
      load_columns
      @counter_groups = helpers.game_counter_groups(GameCounter.includes(:opposite).to_a)
      @characters = filtered.includes(:house, :faction, account: :user)
                            .order(Arel.sql('game_houses.position NULLS LAST, game_houses.id NULLS LAST, accounts.username'))
                            .page(params[:page]).per(PER_PAGE)
      load_records(@characters.map(&:account_id))
    end

    # 명단에서 소속·진영을 눌러 바로 바꾼다 (kind: house|faction, value: 소속 번호, 비우면 없음)
    def assign_group
      authorize :settings, :update?

      character = GameCharacter.find(params[:id])
      value = params[:value].presence
      case params[:kind]
      when 'house' then character.update!(house: value && GameHouse.houses.find(value))
      when 'faction' then character.update!(faction: value && GameHouse.factions.find(value))
      else return head :unprocessable_entity
      end
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

    # 활동 > 인벤토리 카드: 아이템 더하기 (이름이 같으면 개수만 더한다)
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
      redirect_to admin_game_activity_path(character), notice: t('generic.changes_saved_msg')
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
      @labels = Game::Config.for('common').slice('house_label', 'faction_label')
      @base_stats = GameCharacterField.base_stats.to_a
      @statuses = GameCharacterField.statuses.to_a
      @currency = Game::Config.for('common')['currency_name']
    end

    # 명단의 전적: 계정마다 { 'win' => n, 'lose' => n, 'draw' => n } (끝난 판만)
    def load_records(account_ids)
      counts = GamePlayer.joins(:session).merge(GameSession.current_kinds).where(account_id: account_ids, game_sessions: { status: 'finished' }).group(:account_id, :result).count
      @records = Hash.new { |hash, key| hash[key] = {} }
      counts.each { |(account_id, result), count| @records[account_id][result] = count }
    end

    # 상세 화면: 전적(승·패·무)과 최근 판
    def prepare_form
      load_columns
      @counters = GameCounter.includes(:opposite).to_a
      finished = GamePlayer.joins(:session).where(account_id: @character.account_id, game_sessions: { status: 'finished' })
      @record = finished.group(:result).count
    end

    def filter_params
      { q: params[:q], house: params[:house], faction: params[:faction] }.compact_blank
    end

    # 스탯: 정의된 스탯만, 최소~최대 안으로 (비우면 저장하지 않아 최소치)
    def stat_values
      given = character_params[:stat_values].to_h
      GameCharacterField.base_stats.each_with_object({}) do |field, values|
        value = given[field.name].to_s.strip
        values[field.name] = field.clamp(value).to_s if value.present?
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
      redirect_to admin_game_activity_path(character)
    end

    def filtered
      scope = GameCharacter.visible.joins(:account).left_joins(:house)
      if params[:q].present?
        query = "%#{ActiveRecord::Base.sanitize_sql_like(params[:q].strip)}%"
        scope = scope.where('game_characters.name ILIKE :q OR accounts.username ILIKE :q OR accounts.display_name ILIKE :q', q: query)
      end
      scope = params[:house] == 'none' ? scope.where(game_house_id: nil) : scope.where(game_house_id: params[:house]) if params[:house].present?
      scope = params[:faction] == 'none' ? scope.where(game_faction_id: nil) : scope.where(game_faction_id: params[:faction]) if params[:faction].present?
      scope
    end

    def character_params
      params.require(:game_character).permit(:name, :game_house_id, :game_faction_id, :note, stat_values: {})
    end
  end
end
