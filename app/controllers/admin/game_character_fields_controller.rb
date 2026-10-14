# frozen_string_literal: true

module Admin
  # 관리 > 시스템 > 캐릭터 관리 > 항목: 캐릭터마다 적는 정보 (혈통 같은 고르기, 글). 이름·종류·고를 항목·설명
  class GameCharacterFieldsController < BaseController
    def index
      authorize :settings, :show?

      @fields = GameCharacterField.profile.to_a
    end

    def create
      authorize :settings, :update?

      GameCharacterField.create!(field_params.merge(section: 'profile', position: GameCharacterField.profile.count))
      redirect_to admin_game_character_fields_path, notice: t('generic.changes_saved_msg')
    rescue ActiveRecord::RecordInvalid => e
      redirect_to admin_game_character_fields_path(modal: 'field-add'), alert: e.record.errors.full_messages.to_sentence
    end

    def update
      authorize :settings, :update?

      GameCharacterField.profile.find(params[:id]).update!(field_params)
      redirect_to admin_game_character_fields_path, notice: t('generic.changes_saved_msg')
    rescue ActiveRecord::RecordInvalid => e
      redirect_to admin_game_character_fields_path(modal: "field-#{params[:id]}"), alert: e.record.errors.full_messages.to_sentence
    end

    def destroy
      authorize :settings, :update?

      field = GameCharacterField.profile.find(params[:id])
      field.destroy!
      # 지운 항목의 값도 캐릭터에서 걷어 낸다
      GameCharacter.where('profile ? :key', key: field.id.to_s).find_each { |character| character.update_columns(profile: character.profile.except(field.id.to_s)) }
      redirect_to admin_game_character_fields_path, notice: t('generic.changes_saved_msg')
    end

    private

    def field_params
      permitted = params.expect(game_character_field: [:name, :kind, :choices_text, :description])
      permitted[:kind] = GameCharacterField::EDITABLE_KINDS.include?(permitted[:kind]) ? permitted[:kind] : 'text'
      permitted
    end
  end
end
