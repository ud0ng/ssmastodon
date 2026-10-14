# frozen_string_literal: true

module Admin
  # 관리 > 시트 설정: 자동봇이 쓰는 구글 시트를 보고, 기본 시트의 설정 워크시트를 고친다.
  # (Admin::BotSheets 모듈과 헷갈리지 않게 시트 클래스는 ::BotSheets 로 부른다)
  class BotSheetsController < BaseController
    before_action :set_bot_sheet, only: [:show, :update, :append, :update_row, :destroy_row]

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
        hide_moved_help! if @table
        @formulas = @table ? @bot_sheet.formula_map(@worksheet) : {}
      end
      @moved_worksheets = @bot_sheet.moved_worksheets
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

    # 표의 한 줄 고치기 (row: 시트 행 번호, original[]: 고치기 전에 본 값, cells[]: 새 값)
    def update_row
      authorize :settings, :update?

      with_row do |worksheet, number, original|
        count = @bot_sheet.update_row(worksheet, number, original, Array(params[:cells]).map(&:to_s))
        count.zero? ? t('admin.bot_sheets.nothing_changed') : t('admin.bot_sheets.rows.updated', count: count)
      end
    end

    # 표의 한 줄 지우기
    def destroy_row
      authorize :settings, :update?

      with_row do |worksheet, number, original|
        @bot_sheet.delete_row(worksheet, number, original)
        t('admin.bot_sheets.rows.deleted')
      end
    end

    private

    def with_row
      worksheet = params[:worksheet].to_s
      raise ActionController::BadRequest unless @bot_sheet.worksheets.include?(worksheet)

      flash[:notice] = yield worksheet, params[:row].to_i, Array(params[:original]).map(&:to_s)
    rescue ::BotSheets::Conflict
      flash[:alert] = t('admin.bot_sheets.rows.conflict')
    rescue ::BotSheets::Error => e
      flash[:alert] = t('admin.bot_sheets.errors.save_failed', message: e.message)
    ensure
      redirect_to admin_bot_sheet_path(@bot_sheet.sheet, worksheet: worksheet) unless performed?
    end


    # 기본 시트 도움말: 마스토돈으로 옮긴 재화 명령어 줄은 숨긴다 (자동봇도 [도움말]에서 빼고 마스토돈 문구를 붙인다)
    def hide_moved_help!
      return unless @bot_sheet.settings? && ::BotSheets::HELP_WORKSHEETS.include?(@worksheet)

      column = @table.header.index { |cell| cell.to_s.strip == '명령어' }
      return if column.nil?

      visible = @table.rows.reject { |row| ::BotSheets.moved_command?(row.cells[column]) }
      @hidden_help = @table.rows.size - visible.size
      @table.rows = visible
    end

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
