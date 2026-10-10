# frozen_string_literal: true

class Admin::Settings::CommunityController < Admin::SettingsController
  private

  def after_update_redirect_path
    admin_settings_community_path
  end
end
