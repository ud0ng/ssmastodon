# frozen_string_literal: true

module Admin
  # 관리 > 시스템 > 캐릭터 관리 > 스탯: 이름·유형. 유형이 '스탯'이면 최소·최대치, '상태 수치'면 스탯으로 계산하는 수식.
  #   예) 스탯 '힘', 상태 수치 '체력' 수식 {{힘}}*5 → 힘 10 이면 체력 50 이 캐릭터마다 자동 적용
  class GameCharacterStatsController < BaseController
    def index
      authorize :settings, :show?

      GameCharacterField.ensure_defaults!
      @stats = GameCharacterField.stats.to_a
      @base_names = @stats.select(&:stat?).map(&:name)
    end

    def create
      authorize :settings, :update?

      GameCharacterField.create!(stat_params.merge(section: 'stat', kind: 'number', position: GameCharacterField.count))
      redirect_to admin_game_character_stats_path, notice: t('generic.changes_saved_msg')
    rescue ActiveRecord::RecordInvalid => e
      redirect_to admin_game_character_stats_path(modal: 'stat-add'), alert: e.record.errors.full_messages.to_sentence
    end

    def update
      authorize :settings, :update?

      stat = GameCharacterField.stats.find(params[:id])
      old_name = stat.name
      GameCharacterField.transaction do
        stat.update!(stat_params)
        rename!(old_name, stat.name) if old_name != stat.name
      end
      redirect_to admin_game_character_stats_path, notice: t('generic.changes_saved_msg')
    rescue ActiveRecord::RecordInvalid => e
      redirect_to admin_game_character_stats_path(modal: "stat-#{params[:id]}"), alert: e.record.errors.full_messages.to_sentence
    end

    def destroy
      authorize :settings, :update?

      stat = GameCharacterField.stats.find(params[:id])
      users = stat.stat? ? GameCharacterField.statuses.select { |status| Game::Formula.names(status.formula).include?(stat.name) } : []
      if users.any?
        redirect_to admin_game_character_stats_path, alert: t('admin.games.stats.in_use', name: stat.name, users: users.map(&:name).join(', '))
        return
      end

      stat.destroy!
      GameCharacter.where('stats ? :key', key: stat.name).find_each { |character| character.update_columns(stats: character.stats.except(stat.name)) }
      redirect_to admin_game_character_stats_path, notice: t('generic.changes_saved_msg')
    end

    private

    # 스탯 이름을 바꾸면 캐릭터 값과 다른 상태 수치의 수식도 따라 바꾼다
    def rename!(from, to)
      GameCharacter.where('stats ? :key', key: from).find_each do |character|
        stats = character.stats.dup
        stats[to] = stats.delete(from)
        character.update_columns(stats: stats)
      end
      GameCharacterField.statuses.each do |status|
        status.update_columns(formula: status.formula.gsub(/\{\{\s*#{Regexp.escape(from)}\s*\}\}/, "{{#{to}}}")) if Game::Formula.names(status.formula).include?(from)
      end
    end

    def stat_params
      permitted = params.expect(game_character_field: [:name, :stat_type, :min_value, :max_value, :formula, :description])
      permitted[:stat_type] = GameCharacterField::STAT_TYPES.include?(permitted[:stat_type]) ? permitted[:stat_type] : 'stat'
      if permitted[:stat_type] == 'status'
        permitted.merge(min_value: nil, max_value: nil)
      else
        permitted.merge(formula: '')
      end
    end
  end
end
