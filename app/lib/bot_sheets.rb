# frozen_string_literal: true

require 'csv'

# 자동봇(ud0ng/ssbot)이 쓰는 구글 시트를 읽고 쓴다 (관리 > 시트 설정).
#
# 시트 ID 는 서버 설정 bot_sheet_<시트>_id (시트 주소를 통째로 넣어도 된다).
# 구글 시트 API 는 이 서버(GCP VM)의 서비스 계정으로 부른다. 자동봇과 같은 계정이라
# 봇이 쓰는 시트면 따로 공유하지 않아도 된다.
# BOT_SHEETS_LOCAL_DIR 가 있으면 구글 대신 <폴더>/<시트>/<워크시트>.csv 를 쓴다 (미리보기·테스트용).
class BotSheets
  SHEETS = %w(main reservation story investigation).freeze

  # 기본 시트의 설정 워크시트: 항목 | 값 | 설명
  SETTINGS_SHEET = 'main'
  SETTINGS_WORKSHEET = '설정'
  SETTINGS_HEADERS = { name: '항목', value: '값', description: '설명' }.freeze
  HEADER_SEARCH_ROWS = 5

  # 설정 화면에서 같이 보여 줄 항목 (자동봇 설정 워크시트의 항목 이름). 여기 없는 항목은 기타로.
  SETTINGS_GROUPS = {
    'features' => ['키워드 이미지', '하루 조사 횟수', '랜덤박스 명령어'],
    'staff' => ['운영진'],
  }.freeze

  # 마스토돈으로 옮긴 것 (컨텐츠 설정 > 상점, 캐릭터 관리). 시트에 남아 있어도 화면에 보이지 않고 자동봇도 쓰지 않는다.
  MOVED_SETTINGS = ['재화 이름', '재화', '양도', '출석 보상', '툿 보상 기준', '툿 보상 재화'].freeze
  MOVED_WORKSHEETS = { 'main' => %w(명단 관리 상점 출석부 기록) }.freeze
  # 도움말에서 옮긴 명령어 ([ 다음 첫 낱말, 공백 무시). 운영진 명령어 [소지금 추가] [아이템 차감] [힘 변경] 도 포함
  MOVED_COMMANDS = %w(가방 상점 구매 설명 소모 상태확인 상태 사용 양도 출석 소지금추가 소지금차감 아이템추가 아이템차감).freeze
  HELP_WORKSHEET = '도움말'

  # 켜기/끄기 스위치로 보여 줄 값 (켜짐, 꺼짐)
  SWITCH = %w(사용 미사용).freeze

  # 표의 헤더: 앞쪽 몇 줄 중 칸이 두 개 이상 찬 첫 줄 (그 위는 안내 문구)
  HEADER_MIN_CELLS = 2

  SettingItem = Struct.new(:row, :column, :name, :value, :description, :formula, keyword_init: true) do
    def switch?
      SWITCH.include?(value)
    end

    def number?
      value.match?(/\A-?\d+\z/)
    end
  end

  # rows: TableRow (number 는 시트의 행 번호)
  Table = Struct.new(:notes, :header_row, :header, :rows, keyword_init: true) do
    def width
      ([header] + rows.map(&:cells)).map(&:size).max.to_i
    end
  end

  TableRow = Struct.new(:number, :cells)

  class Error < StandardError; end

  # 시트를 열 수 없음 (공유 안 됨, ID 틀림)
  class AccessError < Error; end

  # 고치는 사이에 시트에서 값이 바뀜
  class Conflict < Error
    attr_reader :names

    def initialize(names)
      @names = names
      super(names.join(', '))
    end
  end

  class << self
    def id(sheet)
      value = Setting.public_send(:"bot_sheet_#{sheet}_id").to_s.strip
      value[%r{/spreadsheets/d/([\w-]+)}, 1] || value
    end

    def connected
      SHEETS.select { |sheet| id(sheet).present? }
    end

    def backend
      dir = ENV.fetch('BOT_SHEETS_LOCAL_DIR', nil)
      dir.present? ? LocalBackend.new(dir) : GoogleBackend.new
    end
  end

  attr_reader :sheet

  def initialize(sheet, backend: self.class.backend)
    raise ArgumentError, sheet unless SHEETS.include?(sheet)

    @sheet = sheet
    @id = self.class.id(sheet)
    @backend = backend
  end

  def connected?
    @id.present?
  end

  def url
    "https://docs.google.com/spreadsheets/d/#{@id}/edit"
  end

  # 화면에 보이는 워크시트 (마스토돈으로 옮긴 워크시트는 뺀다)
  def worksheets
    titles = @backend.titles(@sheet, @id)
    titles - MOVED_WORKSHEETS.fetch(@sheet, [])
  end

  # 시트에 아직 남아 있는 옮긴 워크시트 (지워도 된다고 안내)
  def moved_worksheets
    @backend.titles(@sheet, @id) & MOVED_WORKSHEETS.fetch(@sheet, [])
  end

  # 도움말 줄이 마스토돈으로 옮긴 명령어인가 ('[가방]', '[구매/아이템명]', '[힘 변경/+3/이름]')
  def self.moved_command?(text)
    head = text.to_s.strip[%r{\A\[([^\]/]+)}, 1].to_s.gsub(/\s+/, '')
    return false if head.empty?

    MOVED_COMMANDS.include?(head) || (head.end_with?('변경') && head.size > 2)
  end

  def rows(worksheet)
    @backend.values(@sheet, @id, worksheet)
  end

  # 안내 문구 / 헤더 / 내용으로 나눈 워크시트 (헤더가 없으면 nil)
  def table(worksheet)
    rows = rows(worksheet)
    index = rows.first(HEADER_SEARCH_ROWS).index { |row| row.count { |cell| cell.to_s.strip.present? } >= HEADER_MIN_CELLS }
    return if index.nil?

    Table.new(
      notes: rows.first(index).flatten.map(&:strip).compact_blank,
      header_row: index + 1,
      header: rows[index],
      rows: rows.each_with_index.drop(index + 1).filter_map { |row, row_index| TableRow.new(row_index + 1, row) unless row.all?(&:blank?) }
    )
  end

  # 수식이 들어 있는 칸 (열 번호 0부터) — 줄을 고칠 때 덮어쓰지 않게
  def formula_columns(worksheet, number)
    row = @backend.formulas(@sheet, @id, worksheet)[number - 1].to_a
    row.each_index.select { |index| row[index].to_s.start_with?('=') }
  end

  # 워크시트 전체의 수식 칸: { 행 번호 => [열 번호...] } (수정 모달에서 잠글 칸)
  def formula_map(worksheet)
    @backend.formulas(@sheet, @id, worksheet).each_with_index.each_with_object({}) do |(row, index), map|
      columns = row.to_a.each_index.select { |column| row[column].to_s.start_with?('=') }
      map[index + 1] = columns if columns.any?
    end
  end

  # 표의 한 줄을 고친다. original: 고치기 시작할 때 본 그 줄 (그사이 바뀌었거나 줄이 밀렸으면 Conflict)
  def update_row(worksheet, number, original, values)
    header = verified_row(worksheet, number, original)
    formulas = formula_columns(worksheet, number)
    cells = header.each_index.filter_map do |index|
      next if header[index].to_s.strip.empty? || formulas.include?(index)

      value = values[index].to_s
      [[number, index + 1], value] if value != original[index].to_s
    end
    return 0 if cells.empty?

    @backend.update_cells(@sheet, @id, worksheet, cells.to_h)
    cells.size
  end

  # 표의 한 줄을 지운다 (아래 줄이 올라온다)
  def delete_row(worksheet, number, original)
    verified_row(worksheet, number, original)
    @backend.delete_row(@sheet, @id, worksheet, number)
  end

  # 표 맨 아래에 한 줄 더한다. values: 헤더 순서대로 (빈 헤더 칸은 비워 둔다)
  def append_row(worksheet, values)
    header = table(worksheet)&.header
    raise Error, worksheet if header.nil?

    row = header.each_with_index.map { |name, index| name.to_s.strip.present? ? values[index].to_s : '' }
    return false if row.all?(&:blank?)

    @backend.append_row(@sheet, @id, worksheet, row)
    true
  end

  # 설정 항목을 SETTINGS_GROUPS 대로 묶는다: [[그룹, 항목들], ...]
  def self.group_settings(items)
    grouped = SETTINGS_GROUPS.map { |group, names| [group, names.filter_map { |name| items.find { |item| item.name == name } }] }
    others = items - grouped.flat_map(&:last)
    (grouped + [['others', others]]).reject { |_, group_items| group_items.empty? }
  end

  def settings?
    @sheet == SETTINGS_SHEET
  end

  # 설정 워크시트의 항목들 (헤더가 없으면 nil)
  def settings
    all_settings&.reject { |item| MOVED_SETTINGS.include?(item.name) }
  end

  # 설정 워크시트의 모든 항목 (옮긴 항목 포함 — 저장할 때 행 확인용)
  def all_settings
    rows = rows(SETTINGS_WORKSHEET)
    formulas = @backend.formulas(@sheet, @id, SETTINGS_WORKSHEET)
    header_row, columns = find_header(rows)
    return if header_row.nil?

    rows.each_with_index.filter_map do |row, index|
      next if index <= header_row

      name = row[columns[:name]].to_s.strip
      next if name.empty?

      SettingItem.new(
        row: index + 1,
        column: columns[:value] + 1,
        name: name,
        value: row[columns[:value]].to_s,
        description: columns[:description] && row[columns[:description]].to_s,
        formula: formulas.dig(index, columns[:value]).to_s.start_with?('=')
      )
    end
  end

  # changes: { 행 번호 => [처음 본 값, 새 값] }. 그사이 시트에서 바뀐 항목이 있으면 아무것도 쓰지 않는다.
  def update_settings(changes)
    items = settings.to_a.index_by(&:row)
    changes = changes.select { |row, (original, value)| items[row] && !items[row].formula && original != value }
    return 0 if changes.empty?

    conflicts = changes.filter_map { |row, (original, _)| items[row].name if items[row].value != original }
    raise Conflict, conflicts if conflicts.any?

    @backend.update_cells(@sheet, @id, SETTINGS_WORKSHEET, changes.to_h { |row, (_, value)| [[row, items[row].column], value] })
    changes.size
  end

  private

  # 시트의 number 번째 줄이 original 과 같은지 확인하고 헤더를 돌려준다
  def verified_row(worksheet, number, original)
    table = table(worksheet)
    raise Error, worksheet if table.nil?

    row = table.rows.find { |table_row| table_row.number == number }
    raise Conflict, [worksheet] if row.nil? || !same_cells?(row.cells, original)

    table.header
  end

  def same_cells?(cells, original)
    width = [cells.size, original.size].max
    Array.new(width) { |index| cells[index].to_s } == Array.new(width) { |index| original[index].to_s }
  end

  def find_header(rows)
    rows.first(HEADER_SEARCH_ROWS).each_with_index do |row, index|
      cleaned = row.map { |cell| cell.to_s.strip }
      columns = SETTINGS_HEADERS.transform_values { |header| cleaned.index(header) }
      return [index, columns] if columns[:name] && columns[:value]
    end
    nil
  end

  # 구글 시트 API (GCP VM 서비스 계정)
  class GoogleBackend
    API = 'https://sheets.googleapis.com/v4/spreadsheets'
    METADATA = 'http://169.254.169.254/computeMetadata/v1/instance/service-accounts/default'
    TOKEN_CACHE_KEY = 'bot_sheets:access_token'
    TIMEOUT = 10

    def titles(_sheet, id)
      get("#{API}/#{id}", fields: 'sheets.properties.title')['sheets'].to_a.map { |sheet| sheet.dig('properties', 'title') }
    end

    def values(_sheet, id, worksheet)
      read(id, worksheet, 'FORMATTED_VALUE')
    end

    def formulas(_sheet, id, worksheet)
      read(id, worksheet, 'FORMULA')
    end

    def update_cells(_sheet, id, worksheet, cells)
      data = cells.map { |(row, column), value| { range: "#{quote(worksheet)}!#{a1(row, column)}", values: [[value]] } }
      request(:post, "#{API}/#{id}/values:batchUpdate", json: { valueInputOption: 'USER_ENTERED', data: data })
    end

    def append_row(_sheet, id, worksheet, row)
      request(:post, "#{API}/#{id}/values/#{ERB::Util.url_encode("#{quote(worksheet)}!A1")}:append",
              params: { valueInputOption: 'USER_ENTERED', insertDataOption: 'INSERT_ROWS' },
              json: { values: [row] })
    end

    def delete_row(_sheet, id, worksheet, number)
      sheet_id = get("#{API}/#{id}", fields: 'sheets.properties(sheetId,title)')['sheets'].to_a
                 .find { |sheet| sheet.dig('properties', 'title') == worksheet }&.dig('properties', 'sheetId')
      raise AccessError, worksheet if sheet_id.nil?

      request(:post, "#{API}/#{id}:batchUpdate", json: {
        requests: [{ deleteDimension: { range: { sheetId: sheet_id, dimension: 'ROWS', startIndex: number - 1, endIndex: number } } }],
      })
    end

    # 시트 [공유]에 넣을 이메일
    def self.service_account_email
      HTTP.timeout(3).headers('Metadata-Flavor' => 'Google').get("#{METADATA}/email").then { |response| response.status.success? ? response.to_s : nil }
    rescue HTTP::Error, OpenSSL::SSL::SSLError, Errno::ECONNREFUSED, Errno::EHOSTUNREACH
      nil
    end

    private

    def read(id, worksheet, render)
      get("#{API}/#{id}/values/#{ERB::Util.url_encode(quote(worksheet))}", valueRenderOption: render)['values'] || []
    end

    def quote(worksheet)
      "'#{worksheet.gsub("'", "''")}'"
    end

    def a1(row, column)
      letters = +''
      while column.positive?
        column, remainder = (column - 1).divmod(26)
        letters.prepend((65 + remainder).chr)
      end
      "#{letters}#{row}"
    end

    def get(url, params)
      request(:get, url, params: params)
    end

    def request(method, url, **options)
      response = HTTP.timeout(TIMEOUT).auth("Bearer #{token}").public_send(method, url, **options)
      body = response.parse(:json) rescue {} # rubocop:disable Style/RescueModifier
      return body if response.status.success?

      message = body.dig('error', 'message') || response.status.to_s
      raise AccessError, message if [403, 404].include?(response.code)

      raise Error, message
    rescue HTTP::Error, OpenSSL::SSL::SSLError => e
      raise Error, e.message
    end

    def token
      Rails.cache.read(TOKEN_CACHE_KEY) || fetch_token
    end

    def fetch_token
      response = HTTP.timeout(3).headers('Metadata-Flavor' => 'Google').get("#{METADATA}/token")
      raise Error, I18n.t('admin.bot_sheets.errors.no_token') unless response.status.success?

      body = response.parse(:json)
      Rails.cache.write(TOKEN_CACHE_KEY, body['access_token'], expires_in: [body['expires_in'].to_i - 60, 60].max.seconds)
      body['access_token']
    rescue HTTP::Error, Errno::ECONNREFUSED, Errno::EHOSTUNREACH
      raise Error, I18n.t('admin.bot_sheets.errors.no_token')
    end
  end

  # <폴더>/<시트>/<워크시트>.csv (자동봇의 LOCAL_SHEETS_DIR 과 같은 모양)
  class LocalBackend
    def initialize(dir)
      @dir = Pathname.new(dir)
    end

    def titles(sheet, _id)
      folder = @dir.join(sheet)
      raise AccessError, folder.to_s unless folder.directory?

      folder.glob('*.csv').map { |path| path.basename('.csv').to_s.unicode_normalize(:nfc) }.sort
    end

    def values(sheet, _id, worksheet)
      CSV.read(path(sheet, worksheet), encoding: 'bom|utf-8')
         .map { |row| row.map(&:to_s) }
    rescue CSV::MalformedCSVError => e
      raise Error, e.message
    end

    def formulas(sheet, id, worksheet)
      values(sheet, id, worksheet)
    end

    def update_cells(sheet, id, worksheet, cells)
      rows = values(sheet, id, worksheet)
      cells.each do |(row, column), value|
        rows[row - 1] ||= []
        rows[row - 1][column - 1] = value
      end
      write(sheet, worksheet, rows)
    end

    def append_row(sheet, id, worksheet, row)
      write(sheet, worksheet, values(sheet, id, worksheet) + [row])
    end

    def delete_row(sheet, id, worksheet, number)
      rows = values(sheet, id, worksheet)
      rows.delete_at(number - 1)
      write(sheet, worksheet, rows)
    end

    private

    def write(sheet, worksheet, rows)
      CSV.open(path(sheet, worksheet), 'w') { |csv| rows.each { |row| csv << row } }
    end

    def path(sheet, worksheet)
      path = @dir.join(sheet, "#{worksheet}.csv")
      raise AccessError, worksheet unless path.file?

      path
    end
  end
end
