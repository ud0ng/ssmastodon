# frozen_string_literal: true

module Admin
  # 관리 > 시트 설정: 자동봇이 쓰는 구글 시트를 보고, 기본 시트의 설정 워크시트를 고친다.
  # (Admin::BotSheets 모듈과 헷갈리지 않게 시트 클래스는 ::BotSheets 로 부른다)
  class BotSheetsController < BaseController
    before_action :set_bot_sheet, only: [:show, :update, :append]

    def index
      authorize :settings, :show?

      sheet = ::BotSheets.connected.first
      redirect_to sheet ? admin_bot_sheet_path(sheet) : admin_bot_sheet_connection_path
    end

    def show
      authorize :settings, :show?

      return redirect_to admin_bot_sheet_connection_path unless @bot_sheet.connected?

      @worksheets = @bot_sheet.worksheets
      @worksheet = @worksheets.include?(params[:worksheet]) ? params[:worksheet] : default_worksheet
      if settings_worksheet?
        @settings = @bot_sheet.settings
      elsif @worksheet
        @table = @bot_sheet.table(@worksheet)
        @rows = @bot_sheet.rows(@worksheet) if @table.nil?
      end
    rescue ::BotSheets::Error => e
      @error = e
    end

    def update
      authorize :settings, :update?

      changes = params.fetch(:items, {}).to_unsafe_h.to_h do |row, item|
        [row.to_i, [item['original'].to_s, item['value'].to_s]]
      end
      count = @bot_sheet.update_settings(changes)
      flash[:notice] = count.zero? ? t('admin.bot_sheets.nothing_changed') : t('admin.bot_sheets.saved', count: count)
      redirect_to admin_bot_sheet_path(@bot_sheet.sheet, worksheet: ::BotSheets::SETTINGS_WORKSHEET)
    rescue ::BotSheets::Conflict => e
      flash[:alert] = t('admin.bot_sheets.conflict', names: e.names.join(', '))
      redirect_to admin_bot_sheet_path(@bot_sheet.sheet, worksheet: ::BotSheets::SETTINGS_WORKSHEET)
    rescue ::BotSheets::Error => e
      flash[:alert] = t('admin.bot_sheets.errors.save_failed', message: e.message)
      redirect_to admin_bot_sheet_path(@bot_sheet.sheet, worksheet: ::BotSheets::SETTINGS_WORKSHEET)
    end

    # 표 맨 아래에 한 줄 더하기 (헤더 순서대로 cells[])
    def append
      authorize :settings, :update?

      worksheet = params[:worksheet].to_s
      raise ActionController::BadRequest unless @bot_sheet.worksheets.include?(worksheet)

      added = @bot_sheet.append_row(worksheet, Array(params[:cells]).map(&:to_s))
      flash[:notice] = added ? t('admin.bot_sheets.rows.added') : t('admin.bot_sheets.rows.empty')
      redirect_to admin_bot_sheet_path(@bot_sheet.sheet, worksheet: worksheet)
    rescue ::BotSheets::Error => e
      flash[:alert] = t('admin.bot_sheets.errors.save_failed', message: e.message)
      redirect_to admin_bot_sheet_path(@bot_sheet.sheet, worksheet: worksheet)
    end

    private

    def set_bot_sheet
      @bot_sheet = ::BotSheets.new(params[:id])
    end

    def default_worksheet
      return ::BotSheets::SETTINGS_WORKSHEET if @bot_sheet.settings? && @worksheets.include?(::BotSheets::SETTINGS_WORKSHEET)

      @worksheets.first
    end

    def settings_worksheet?
      @bot_sheet.settings? && @worksheet == ::BotSheets::SETTINGS_WORKSHEET
    end
  end
end
