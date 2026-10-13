# frozen_string_literal: true

module Admin
  # 관리 > 캐릭터 명단 > 항목 설정: 기숙사·학년 말고 더하는 값 (진영 같은 고르기, 글, 숫자, 전투 스탯)
  class GameCharacterFieldsController < BaseController
    def index
      authorize :settings, :show?

      GameCharacterField.ensure_defaults!
      @fields = GameCharacterField.all
      @currency = Game::Config.for('common')['currency_name']
    end

    def create
      authorize :settings, :update?

      GameCharacterField.create!(field_params.merge(position: GameCharacterField.count))
      redirect_to admin_game_character_fields_path, notice: t('generic.changes_saved_msg')
    rescue ActiveRecord::RecordInvalid => e
      redirect_to admin_game_character_fields_path, alert: e.record.errors.full_messages.to_sentence
    end

    def update
      authorize :settings, :update?

      field = GameCharacterField.find(params[:id])
      old_name = field.name
      GameCharacterField.transaction do
        field.update!(field_params)
        rename_stat!(old_name, field.name) if field.section == 'stat' && old_name != field.name
      end
      redirect_to admin_game_character_fields_path, notice: t('generic.changes_saved_msg')
    rescue ActiveRecord::RecordInvalid => e
      redirect_to admin_game_character_fields_path, alert: e.record.errors.full_messages.to_sentence
    end

    def destroy
      authorize :settings, :update?

      GameCharacterField.find(params[:id]).destroy!
      redirect_to admin_game_character_fields_path, notice: t('generic.changes_saved_msg')
    end

    private

    # 전투 스탯은 캐릭터 stats 에 이름으로 들어 있으니 이름을 바꾸면 값도 옮긴다
    def rename_stat!(from, to)
      GameCharacter.where('stats ? :key', key: from).find_each do |character|
        stats = character.stats.dup
        stats[to] = stats.delete(from)
        character.update_columns(stats: stats)
      end
    end

    def field_params
      params.expect(game_character_field: [:name, :kind, :section, :choices_text, :position])
    end
  end
end
