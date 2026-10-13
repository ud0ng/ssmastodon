# frozen_string_literal: true

module Admin
  # 관리 > 캐릭터 명단: 회원 목록에서 만들고 캐릭터 이름·기숙사·학년·개인 값을 고친다
  class GameCharactersController < BaseController
    PER_PAGE = 50

    def index
      authorize :settings, :show?

      GameHouse.ensure_defaults!
      GameCharacter.sync!
      @houses = GameHouse.all
      @characters = filtered.includes(:house, account: :user).order('game_houses.position NULLS LAST', 'accounts.username')
                            .page(params[:page]).per(PER_PAGE)
    end

    def edit
      authorize :settings, :show?

      @character = GameCharacter.find(params[:id])
      @houses = GameHouse.all
    end

    def update
      authorize :settings, :update?

      @character = GameCharacter.find(params[:id])
      if @character.update(character_params)
        redirect_to admin_game_characters_path(q: params[:q], house: params[:house]), notice: t('generic.changes_saved_msg')
      else
        @houses = GameHouse.all
        render :edit
      end
    end

    private

    def filtered
      scope = GameCharacter.joins(:account).left_joins(:house).where(account_id: GameCharacter.eligible_accounts.select(:id))
      if params[:q].present?
        query = "%#{ActiveRecord::Base.sanitize_sql_like(params[:q].strip)}%"
        scope = scope.where('game_characters.name ILIKE :q OR accounts.username ILIKE :q OR accounts.display_name ILIKE :q', q: query)
      end
      scope = params[:house] == 'none' ? scope.where(game_house_id: nil) : scope.where(game_house_id: params[:house]) if params[:house].present?
      scope
    end

    def character_params
      params.expect(game_character: [:name, :game_house_id, :grade, :note, :stats_text])
    end
  end
end
