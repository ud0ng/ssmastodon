# frozen_string_literal: true

module Admin
  module Settings
    # 서버 설정 > 디자인 > 프리셋: 지금 디자인 저장 / 이름·이미지 고치기 / 덮어쓰기 / 적용 (DesignPreset)
    class DesignPresetsController < Admin::BaseController
      before_action :set_preset, only: [:update, :destroy, :apply]

      def create
        authorize :settings, :update?

        preset = DesignPreset.capture!(params.dig(:design_preset, :name).to_s.strip)
        redirect_to admin_settings_community_theme_path, notice: t('admin.settings.design_presets.overwritten', name: preset.name)
      rescue ActiveRecord::RecordInvalid => e
        redirect_to admin_settings_community_theme_path(modal: 'design-preset-add'), alert: e.record.errors.full_messages.to_sentence
      end

      def update
        authorize :settings, :update?

        if params[:overwrite] == '1'
          @preset.capture!
          return redirect_to admin_settings_community_theme_path, notice: t('admin.settings.design_presets.overwritten', name: @preset.name)
        end

        DesignPreset.transaction do
          @preset.update!(name: params.dig(:design_preset, :name).to_s.strip, clear_images: DesignPreset::IMAGE_VARS.select { |var| params.dig(:design_preset, :clear, var) == '1' })
          DesignPreset::IMAGE_VARS.each do |var|
            file = params.dig(:design_preset, :images, var)
            if file.present?
              (@preset.image(var) || @preset.images.build(var: var)).update!(file: file)
            elsif params.dig(:design_preset, :remove_images, var) == '1'
              @preset.image(var)&.destroy!
            end
          end
        end
        redirect_to admin_settings_community_theme_path, notice: t('generic.changes_saved_msg')
      rescue ActiveRecord::RecordInvalid => e
        redirect_to admin_settings_community_theme_path(modal: "design-preset-#{@preset.id}"), alert: e.record.errors.full_messages.to_sentence
      end

      def destroy
        authorize :settings, :update?

        @preset.destroy!
        redirect_to admin_settings_community_theme_path, notice: t('generic.changes_saved_msg')
      end

      def apply
        authorize :settings, :update?

        @preset.apply!
        redirect_to admin_settings_community_theme_path, notice: t('admin.settings.design_presets.applied', name: @preset.name)
      rescue ActiveRecord::RecordInvalid => e
        redirect_to admin_settings_community_theme_path, alert: e.record.errors.full_messages.to_sentence
      end

      private

      def set_preset
        @preset = DesignPreset.includes(:images).find(params[:id])
      end
    end
  end
end
