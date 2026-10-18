# frozen_string_literal: true

module Admin
  # 관리 > 시스템 > 캐릭터 관리 > 컨텐츠 기록: 끝난 컨텐츠를 캐릭터별로 한 줄씩 (시간 · 상대 캐릭터 · 종류 · 결과).
  # 검색: 캐릭터 · 종류 · 결과. 캐릭터 하나를 고르면(상세 화면의 [컨텐츠 기록]) 그 캐릭터의 기록만 보인다.
  class GameRecordsController < BaseController
    PER_PAGE = 30
    RESULTS = %w(win lose draw).freeze

    def index
      authorize :settings, :show?

      @characters = GameCharacter.visible.includes(:account).joins(:account).order(Arel.sql('accounts.username')).to_a
      @kinds = Game::Kinds.all
      @single = single_character
      @players = filtered.includes(:account, session: { players: :account }).page(params[:page]).per(PER_PAGE)
      account_ids = @players.flat_map { |player| [player.account_id, *player.session.players.map(&:account_id)] }.uniq
      @characters_by_account = GameCharacter.where(account_id: account_ids).includes(:account).index_by(&:account_id)
    end

    private

    # 캐릭터 칸이 한 사람을 가리키면 그 사람 (아이디·이름이 정확히 맞는 한 명)
    def single_character
      return GameCharacter.find_by(account_id: params[:character]) if params[:character].present?
      return if params[:q].blank?

      matches = @characters.select { |character| [character.display_name, character.account.username].any? { |name| name.casecmp?(params[:q].to_s.strip) } }
      matches.first if matches.one?
    end

    def filtered
      scope = GamePlayer.joins(:session).merge(GameSession.current_kinds).where(game_sessions: { status: 'finished' })
                        .order(Arel.sql('game_sessions.finished_at DESC NULLS LAST, game_sessions.id DESC, game_players.seat'))
      scope = scope.where(game_sessions: { kind: params[:kind] }) if Game::Kinds.keys.include?(params[:kind].to_s)
      scope = scope.where(result: params[:result]) if RESULTS.include?(params[:result].to_s)
      if @single
        scope.where(account_id: @single.account_id)
      elsif params[:q].present?
        like = "%#{ActiveRecord::Base.sanitize_sql_like(params[:q].to_s.strip.downcase)}%"
        ids = GameCharacter.joins(:account).where('lower(accounts.username) LIKE ? OR lower(game_characters.name) LIKE ?', like, like).pluck(:account_id)
        scope.where(account_id: ids)
      else
        scope
      end
    end
  end
end
