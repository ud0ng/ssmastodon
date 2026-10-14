# frozen_string_literal: true

module Admin
  # 컨텐츠 설정 > 토너먼트: 대진표 만들기·경기 설정·시작
  class GameTournamentsController < BaseController
    before_action :set_tournament, only: [:show, :update, :destroy, :start]

    def index
      authorize :settings, :show?

      @tournaments = GameTournament.order(id: :desc)
    end

    def create
      authorize :settings, :update?

      tournament = GameTournament.create!(tournament_params)
      redirect_to admin_game_tournament_path(tournament)
    rescue ActiveRecord::RecordInvalid => e
      redirect_to admin_game_tournaments_path, alert: e.record.errors.full_messages.to_sentence
    end

    def show
      authorize :settings, :show?

      @characters = GameCharacter.visible.includes(:house, :faction, :account).order(:game_house_id, :name)
      @kinds = Game::Kinds.matches
    end

    def update
      authorize :settings, :update?

      @tournament.update!(params.expect(game_tournament: [:name, :reward]))
      redirect_to admin_game_tournament_path(@tournament), notice: t('generic.changes_saved_msg')
    end

    def destroy
      authorize :settings, :update?

      @tournament.destroy!
      redirect_to admin_game_tournaments_path, notice: t('generic.changes_saved_msg')
    end

    def start
      authorize :settings, :update?

      Game::Tournament.start!(@tournament) if @tournament.status == 'draft'
      redirect_to admin_game_tournament_path(@tournament), notice: t('admin.games.tournaments.started')
    end

    private

    def set_tournament
      @tournament = GameTournament.find(params[:id])
    end

    def tournament_params
      params.expect(game_tournament: [:name, :size, :reward])
    end
  end
end
