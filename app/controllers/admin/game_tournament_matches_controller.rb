# frozen_string_literal: true

module Admin
  # 대진표의 한 경기: 컨텐츠·시간·선수 정하기, 운영진 판정
  class GameTournamentMatchesController < BaseController
    before_action :set_match

    def update
      authorize :settings, :update?

      if %w(playing done).include?(@match.status)
        redirect_to admin_game_tournament_path(@match.tournament), alert: t('admin.games.tournaments.locked')
        return
      end

      attributes = params.expect(game_tournament_match: [:kind, :scheduled_at, :player_a_id, :player_b_id])
      attributes[:scheduled_at] = parse_time(attributes[:scheduled_at])
      @match.update!(attributes.to_h.transform_values(&:presence))
      Game::Tournament.schedule!(@match)
      redirect_to admin_game_tournament_path(@match.tournament, anchor: "match-#{@match.id}"), notice: t('generic.changes_saved_msg')
    rescue ActiveRecord::RecordInvalid => e
      redirect_to admin_game_tournament_path(@match.tournament), alert: e.record.errors.full_messages.to_sentence
    end

    # 운영진 판정: 고른 선수의 승리
    def decide
      authorize :settings, :update?

      winner = @match.players.find { |player| player.id == params[:winner_id].to_i }
      @match.with_lock { Game::Tournament.decide!(@match, winner) } if winner && @match.status != 'done'
      redirect_to admin_game_tournament_path(@match.tournament, anchor: "match-#{@match.id}"), notice: t('generic.changes_saved_msg')
    end

    private

    def set_match
      @match = GameTournamentMatch.find(params[:id])
    end

    # 관리 화면의 시간은 한국 시간
    def parse_time(value)
      value.present? ? ActiveSupport::TimeZone['Asia/Seoul'].parse(value) : nil
    end
  end
end
