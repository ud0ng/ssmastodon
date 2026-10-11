# frozen_string_literal: true

# 이 탭은 '서버 정보' 탭으로 합쳤다. 예전 주소로 들어오면 그쪽으로 보낸다.
class Admin::Settings::AboutController < Admin::SettingsController
  def show
    authorize :settings, :show?

    redirect_to admin_settings_branding_path
  end

  private

  def after_update_redirect_path
    admin_settings_branding_path
  end
end
