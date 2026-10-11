# frozen_string_literal: true

class Admin::Settings::CommunityThemeController < Admin::SettingsController
  private

  def after_update_redirect_path
    admin_settings_community_theme_path
  end
end
