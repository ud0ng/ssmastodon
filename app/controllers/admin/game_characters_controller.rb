# frozen_string_literal: true

module Admin
  # 관리 > 시스템 > 캐릭터 관리 > 명단: 회원 목록에서 자동으로 만들어지는 캐릭터를 소속별 표로 보고,
  # 캐릭터를 눌러 이름·소속·학년·항목 값·스탯·돈·인벤토리를 고친다.
  class GameCharactersController < BaseController
    PER_PAGE = 100

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

    # 고른 캐릭터들의 기숙사·진영이나 항목 값을 한꺼번에 바꾼다
    #   target: 'house:<id>' / 'house:none' / 'faction:<id>' / 'faction:none' / 'field:<항목 id>:<값>' (값이 비면 지움)
    def bulk
      authorize :settings, :update?

      ids = Array(params[:ids]).compact_blank
      kind, id, value = params[:target].to_s.split(':', 3)
      characters = GameCharacter.where(id: ids)
      if ids.any? && kind == 'house'
        house = id == 'none' ? nil : GameHouse.houses.find(id)
        characters.find_each { |character| character.update!(house: house) }
      elsif ids.any? && kind == 'faction'
        faction = id == 'none' ? nil : GameHouse.factions.find(id)
        characters.find_each { |character| character.update!(faction: faction) }
      elsif ids.any? && kind == 'field'
        field = GameCharacterField.profile.find(id)
        characters.find_each do |character|
          profile = character.profile.dup
          if value.present? && field.choice(value)
            profile[field.id.to_s] = value
          else
            profile.delete(field.id.to_s)
          end
          character.update!(profile: profile)
        end
      end
      redirect_to admin_game_characters_path(filter_params), notice: t('generic.changes_saved_msg')
    end

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
      @character.assign_attributes(character_params.except(:profile, :stat_values))
      @character.profile = profile_values
      @character.stats = stat_values
      if @character.save
        redirect_to admin_game_characters_path(filter_params), notice: t('generic.changes_saved_msg')
      else
        render :edit
      end
    end

    private

    def load_columns
      @houses = GameHouse.houses.to_a
      @factions = GameHouse.factions.to_a
      @labels = Game::Config.for('common').slice('house_label', 'faction_label')
      @profile_fields = GameCharacterField.profile.to_a
      @base_stats = GameCharacterField.base_stats.to_a
      @statuses = GameCharacterField.statuses.to_a
      @currency = Game::Config.for('common')['currency_name']
    end

    def prepare_form
      load_columns
      @rewards = GameReward.where(account_id: @character.account_id).order(id: :desc).limit(15)
    end

    def filter_params
      { q: params[:q], house: params[:house], faction: params[:faction], field: params[:field] }.compact_blank
    end

    # 항목 값: 있는 항목만, 고르기는 목록에 있는 값만
    def profile_values
      given = character_params[:profile].to_h
      GameCharacterField.profile.each_with_object({}) do |field, values|
        value = given[field.id.to_s].to_s.strip
        next if value.blank?
        next if field.select? && !field.choice(value)

        values[field.id.to_s] = value
      end
    end

    # 스탯: 정의된 스탯만, 최소~최대 안으로 (비우면 저장하지 않아 최소치)
    def stat_values
      given = character_params[:stat_values].to_h
      GameCharacterField.base_stats.each_with_object({}) do |field, values|
        value = given[field.name].to_s.strip
        values[field.name] = field.clamp(value).to_s if value.present?
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
      params.require(:game_character).permit(:name, :game_house_id, :game_faction_id, :grade, :note, :money, :inventory_text, profile: {}, stat_values: {})
    end
  end
end
