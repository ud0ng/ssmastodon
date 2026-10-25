# frozen_string_literal: true

module Admin
  # 관리 > 시스템 > 캐릭터 관리 > 소속 기록: 소속 점수를 얻거나 잃은 기록 (시간 · 소속 · 캐릭터 · 점수 · 내용=사유).
  # 검색: 캐릭터 · 소속. 맨 위에 몇 건인지 보인다. 기록을 지우면 그만큼 소속 점수도 빠진다 (소속 점수 = 기록의 합).
  class GameHouseRecordsController < BaseController
    PER_PAGE = 30

    def index
      authorize :settings, :show?

      @characters = GameCharacter.visible.includes(:account).joins(:account).order(Arel.sql('accounts.username')).to_a
      @houses = GameHouse.order(:category, :position, :id).to_a
      @points = filtered.includes(:house, :account).page(params[:page]).per(PER_PAGE)
      @characters_by_account = GameCharacter.where(account_id: @points.filter_map(&:account_id).uniq).includes(:account).index_by(&:account_id)
    end

    def destroy
      authorize :settings, :update?

      GameHousePoint.find(params[:id]).destroy!
      redirect_to admin_game_house_records_path(params.permit(:house, :q, :page).to_h), notice: t('admin.games.house_records.deleted')
    end

    private

    def filtered
      scope = GameHousePoint.order(id: :desc)
      scope = scope.where(game_house_id: params[:house]) if params[:house].present?
      if params[:q].present?
        like = "%#{ActiveRecord::Base.sanitize_sql_like(params[:q].to_s.strip.downcase)}%"
        ids = GameCharacter.joins(:account).where('lower(accounts.username) LIKE ? OR lower(game_characters.name) LIKE ?', like, like).pluck(:account_id)
        scope = scope.where(account_id: ids)
      end
      scope
    end
  end
end
