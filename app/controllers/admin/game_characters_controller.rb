# frozen_string_literal: true

module Admin
  # 관리 > 시스템 > 캐릭터 관리 > 명단: 회원 목록에서 자동으로 만들어지는 캐릭터를 소속별 표로 보고,
  # 캐릭터를 눌러 상세 화면(소속·스탯·재화·인벤토리·전적)에서 고친다.
  class GameCharactersController < BaseController
    PER_PAGE = 100
    RECENT_GAMES = 10
    RECENT_REWARDS = 10

    helper_method :filter_params

    def index
      authorize :settings, :show?

      GameHouse.ensure_defaults!
      GameCharacterField.ensure_defaults!
      GameCharacter.sync!
      load_columns
      @characters = filtered.includes(:house, :faction, account: :user)
                            .order(Arel.sql('game_houses.position NULLS LAST, game_houses.id NULLS LAST, accounts.username'))
                            .page(params[:page]).per(PER_PAGE)
    end

    # 고른 캐릭터들의 기숙사·진영을 한꺼번에 바꾼다
    #   target: 'house:<id>' / 'house:none' / 'faction:<id>' / 'faction:none'
    def bulk
      authorize :settings, :update?

      ids = Array(params[:ids]).compact_blank
      kind, id = params[:target].to_s.split(':', 2)
      characters = GameCharacter.where(id: ids)
      if ids.any? && kind == 'house'
        house = id == 'none' ? nil : GameHouse.houses.find(id)
        characters.find_each { |character| character.update!(house: house) }
      elsif ids.any? && kind == 'faction'
        faction = id == 'none' ? nil : GameHouse.factions.find(id)
        characters.find_each { |character| character.update!(faction: faction) }
      end
      redirect_to admin_game_characters_path(filter_params), notice: t('generic.changes_saved_msg')
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
      @character.assign_attributes(character_params.slice(:name, :game_house_id, :game_faction_id, :grade, :note, :money))
      @character.stats = stat_values
      @character.inventory = inventory_rows
      if @character.save
        redirect_to edit_admin_game_character_path(@character, filter_params), notice: t('generic.changes_saved_msg')
      else
        render :edit
      end
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

    # 상세 화면: 재화 기록, 전적(승·패·무)과 최근 판
    def prepare_form
      load_columns
      @rewards = GameReward.where(account_id: @character.account_id).order(id: :desc).limit(RECENT_REWARDS)
      finished = GamePlayer.joins(:session).where(account_id: @character.account_id, game_sessions: { status: 'finished' })
      @record = finished.group(:result).count
      @games = finished.includes(session: { players: :account }).order('game_sessions.finished_at DESC NULLS LAST, game_sessions.id DESC').limit(RECENT_GAMES)
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

    # 인벤토리 줄: 이름이 있는 줄만, 개수는 1 이상
    def inventory_rows
      Array(character_params[:inventory]).filter_map do |row|
        name = row[:name].to_s.strip
        next if name.empty?

        { 'name' => name, 'count' => [row[:count].to_i, 1].max, 'note' => row[:note].to_s.strip }
      end
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
      params.require(:game_character).permit(:name, :game_house_id, :game_faction_id, :grade, :note, :money, stat_values: {}, inventory: [:name, :count, :note])
    end
  end
end
