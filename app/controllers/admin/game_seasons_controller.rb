# frozen_string_literal: true

module Admin
  # 캐릭터 관리 > 소속 > 시즌: 시즌 만들기·고치기·지우기, 중간 결산·시즌 종료 툿, 시즌 문구
  class GameSeasonsController < BaseController
    def create
      authorize :settings, :update?

      GameSeason.create!(season_params)
      redirect_to admin_game_houses_path, notice: t('generic.changes_saved_msg')
    rescue ActiveRecord::RecordInvalid => e
      redirect_to admin_game_houses_path(modal: 'season-add'), alert: e.record.errors.full_messages.to_sentence
    end

    def update
      authorize :settings, :update?

      GameSeason.find(params[:id]).update!(season_params)
      redirect_to admin_game_houses_path, notice: t('generic.changes_saved_msg')
    rescue ActiveRecord::RecordInvalid => e
      redirect_to admin_game_houses_path(modal: "season-#{params[:id]}"), alert: e.record.errors.full_messages.to_sentence
    end

    def destroy
      authorize :settings, :update?

      GameSeason.find(params[:id]).destroy!
      redirect_to admin_game_houses_path, notice: t('generic.changes_saved_msg')
    end

    # 중간 결산: 지금까지의 소속 점수를 툿으로
    def interim
      authorize :settings, :update?

      season = GameSeason.started.find(params[:id])
      Game::Summary.season_interim!(season)
      redirect_to admin_game_houses_path, notice: t('admin.games.seasons.posted')
    end

    # 시즌 종료: 최종 점수를 툿으로 발표. 새 시즌을 만들 때까지 소속 점수를 얻지 못하고 최종 순위가 보인다 (GameSeason.closed?)
    def finish
      authorize :settings, :update?

      season = GameSeason.started.find(params[:id])
      Game::Summary.season_final!(season)
      redirect_to admin_game_houses_path, notice: t('admin.games.seasons.finished')
    end

    # 시즌 문구 (중간 결산·시즌 종료)
    def messages
      authorize :settings, :update?

      keys = Game::Config.sections('common', 'season').flat_map(&:last).map(&:key)
      Game::Config.merge!('common', params.fetch(:config, {}).permit(*keys).to_h)
      redirect_to admin_game_houses_path, notice: t('generic.changes_saved_msg')
    end

    private

    def season_params
      params.expect(game_season: [:name, :starts_on, :ends_on])
    end
  end
end
