# frozen_string_literal: true

module Game
  # 자동봇 도움말 (컨텐츠 설정 > 도움말, /api/v1/bot/config 로 자동봇에 보낸다).
  #   [도움말]         기본 명령어 + 분류별 도움말 목록
  #   [상점 도움말]    재화·아이템·상점 명령어
  #   [컨텐츠 도움말]  시스템 계정이 처리하는 컨텐츠 명령어
  #   [운영진 도움말]  운영진 명령어 (운영진만)
  # 도움말 줄은 '명령어|설명' 표로 고친다. 설명이 비면 그 줄은 소제목(▸ 대결 등)으로 보인다.
  # 표를 고치지 않으면 지금 설정(명령어 이름·켜진 컨텐츠·양도/출석)으로 만든 기본 줄을 쓴다.
  module Help
    F = Game::Config::Field
    COLUMNS = %w(명령어 설명).freeze
    SEP = '|'

    FIELDS = [
      # 도움말 명령어와 [도움말] 에 보이는 분류 안내 (명령어 | 설명 짝으로 한 줄씩, Game::Config::ROW_STARTS)
      F.new(key: 'cmd_help', type: :string, default: '도움말', group: 'help_commands', label: '도움말'),
      F.new(key: 'cmd_shop_help', type: :string, default: '상점 도움말', group: 'help_commands', label: '상점 도움말'),
      F.new(key: 'desc_shop_help', type: :string, default: '재화·아이템·상점 명령어를 보여줍니다.', group: 'help_commands', label: '상점 도움말 설명'),
      F.new(key: 'cmd_content_help', type: :string, default: '컨텐츠 도움말', group: 'help_commands', label: '컨텐츠 도움말'),
      F.new(key: 'desc_content_help', type: :string, default: '대결·마법 수업 등 컨텐츠 명령어를 보여줍니다.', group: 'help_commands', label: '컨텐츠 도움말 설명'),
      F.new(key: 'cmd_admin_help', type: :string, default: '운영진 도움말', group: 'help_commands', label: '운영진 도움말'),
      F.new(key: 'desc_admin_help', type: :string, default: '운영진 명령어를 보여줍니다.', group: 'help_commands', label: '운영진 도움말 설명', hint: '운영진에게만 보입니다'),

      F.new(key: 'rows_basic', type: :lines, group: 'help_basic', label: '기본 도움말', columns: COLUMNS,
            default: ['NdM|M면체 주사위를 N개 굴립니다.', '랜덤/A, B, C...|여러 옵션 중 1개를 골라 출력합니다.', '운세|오늘의 운세를 확인합니다.'],
            hint: '[도움말] 맨 위에 보입니다. 모두 지우면 자동봇 시트의 도움말을 씁니다'),
      F.new(key: 'rows_shop', type: :lines, group: 'help_shop', label: '상점 도움말', columns: COLUMNS, default: -> { Game::Help.default_shop_rows }),
      F.new(key: 'intro_content', type: :string, group: 'help_content', label: '첫 줄', default: -> { "컨텐츠 명령어는 @#{Game::System.username}에게 멘션으로 보냅니다." }),
      F.new(key: 'rows_content', type: :lines, group: 'help_content', label: '컨텐츠 도움말', columns: COLUMNS, default: -> { Game::Help.default_content_rows },
            hint: '설명을 비우면 소제목 줄이 됩니다 (▸ 대결)'),
      F.new(key: 'rows_admin', type: :lines, group: 'help_admin', label: '운영진 도움말', columns: COLUMNS, default: -> { Game::Help.default_admin_rows }),
    ].freeze

    LAYOUT = [
      ['help_commands', %w(help_commands)],
      ['help_basic', %w(help_basic)],
      ['help_shop', %w(help_shop)],
      ['help_content', %w(help_content)],
      ['help_admin', %w(help_admin)],
    ].freeze

    module_function

    def config
      Game::Config.for('help')
    end

    # 자동봇에 보내는 도움말 (/api/v1/bot/config)
    def bot_json
      values = config
      {
        help_command: values['cmd_help'],
        basic_help: lines(values['rows_basic']),
        help: lines(values['rows_shop']),
        content_help: [values['intro_content'].presence, *lines(values['rows_content'])].compact,
        admin_help: lines(values['rows_admin']),
        help_topics: %w(shop content admin).map do |topic|
          { key: topic, command: values["cmd_#{topic}_help"], description: values["desc_#{topic}_help"], admin: topic == 'admin' }
        end,
      }
    end

    # '명령어|설명' 줄 → '[명령어] 설명'. 설명이 없으면 소제목 (앞에 빈 줄)
    def lines(rows)
      Array(rows).each_with_object([]) do |row, result|
        command, description = row.to_s.split(SEP, 2).map { |cell| cell.to_s.strip }
        next if command.blank?

        if description.blank?
          result << '' if result.any?
          result << command
        else
          result << "[#{command}] #{description}"
        end
      end
    end

    # 기본 줄: 자동봇 상점 명령어 (꺼진 양도·출석은 뺀다)
    def default_shop_rows
      rows_from(Game::Config::SHOP_HELP)
    end

    def default_admin_rows
      rows_from(Game::Config::SHOP_ADMIN_HELP)
    end

    def rows_from(templates)
      currency = Game::Config.for('currency')
      common = Game::Config.for('common')
      templates.filter_map do |key, template|
        next if key == 'cmd_transfer' && !currency['transfer_enabled']
        next if key == 'cmd_attendance' && common['attendance_reward'].to_i <= 0

        line = format(template, cmd: currency[key], currency: common['currency_name'])
        match = line.match(/\A\[(.+?)\]\s*(.*)\z/)
        match ? "#{match[1]}#{SEP}#{match[2]}" : line
      end
    end

    # 기본 줄: 지금 켜진 컨텐츠와 설정한 명령어 이름
    def default_content_rows
      common = Game::Config.for('common')
      rows = []

      matches = Game::Kinds.matches.select(&:enabled?)
      if matches.any?
        rows << "▸ 대결#{SEP}"
        rows += matches.map { |kind| match_row(kind) }
        rows << "#{common['cmd_accept']}#{SEP}받은 신청을 받아들입니다."
        rows << "#{common['cmd_decline']}#{SEP}받은 신청을 거절합니다."
        rows << "#{common['cmd_forfeit']}#{SEP}진행 중인 컨텐츠를 포기합니다."
      end

      lessons = Game::Lessons.all.select(&:enabled?)
      if lessons.any?
        lesson = Game::Lessons.config
        rows << "▸ 마법 수업#{SEP}"
        rows << "#{lesson['cmd_study']}/과목#{SEP}과목을 혼자 연습합니다. (과목: #{lessons.map(&:display_name).join(', ')})"
        rows << "#{lesson['cmd_join']}#{SEP}열린 수업에 참가합니다."
        rows << "#{lesson['cmd_report']}#{SEP}내 성적표를 봅니다."
      end

      events = Game::Kinds.events.select(&:enabled?)
      if events.any?
        rows << "▸ 이벤트#{SEP}"
        rows += events.map { |kind| event_row(kind) }
      end

      rows << "▸ 점수·전적#{SEP}"
      rows << "#{common['cmd_points']}#{SEP}소속 점수를 봅니다."
      rows << "#{common['cmd_record']}#{SEP}내 전적을 봅니다."
      rows
    end

    def match_row(kind)
      name = kind.display_name.to_s.strip
      opponents = kind.max_opponents > 1 ? "@상대 … (최대 #{kind.max_opponents}명)" : '@상대'
      web = kind.web? ? ' 웹 진행 화면에서 합니다.' : ''
      "#{kind.config['command']}#{SEP}#{opponents} #{name}#{Game::Text.particle(name[-1], '을를')} 신청합니다.#{web}"
    end

    def event_row(kind)
      name = kind.display_name.to_s.strip
      command = kind.config['command'].to_s.strip
      "#{kind.config['cmd_join']}#{SEP}#{name}#{Game::Text.particle(name[-1], '이가')} 열리면 참가합니다. " \
        "(운영진이 [#{command}]#{Game::Text.particle(command[-1], '으로로')} 엽니다)"
    end
  end
end
