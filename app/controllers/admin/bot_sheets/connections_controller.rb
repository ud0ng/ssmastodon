# frozen_string_literal: true

# 관리 > 시트 설정 > 연결: 자동봇 시트 ID (서버 설정 bot_sheet_*_id)
class Admin::BotSheets::ConnectionsController < Admin::SettingsController
  def show
    super
    @service_account_email = service_account_email
  end

  private

  # 시트 [공유]에 넣을 이메일 (VM 이 아니면 없다)
  def service_account_email
    return if ENV['BOT_SHEETS_LOCAL_DIR'].present?

    Rails.cache.fetch('bot_sheets:service_account_email', expires_in: 1.day, skip_nil: true) do
      ::BotSheets::GoogleBackend.service_account_email
    end
  end

  def after_update_redirect_path
    admin_bot_sheet_connection_path
  end
end
