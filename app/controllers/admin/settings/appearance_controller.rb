# frozen_string_literal: true

# 이 탭은 '디자인' 탭으로 합쳤다. 예전 주소로 들어오면 그쪽으로 보낸다.
class Admin::Settings::AppearanceController < Admin::SettingsController
  def show
    authorize :settings, :show?

    redirect_to admin_settings_community_theme_path
  end

  private

  def after_update_redirect_path
    admin_settings_community_theme_path
  end
end
