# frozen_string_literal: true

module Game
  # 정기 툿: 주간 결산(정한 요일·시각, Game::WeeklySummaryWorker 가 매시 확인)과 학기 마감(관리 화면 버튼).
  # 웹에서는 카드(GameEvent, 판 없음)로도 보인다.
  module Summary
    TIME_ZONE = 'Asia/Seoul'

    module_function

    # 지금이 정한 요일·시각이고 이번 주에 아직 안 올렸으면 올린다
    def weekly_due?(now = Time.now.utc)
      common = Game::Config.for('common')
      return false unless common['weekly_enabled']

      local = now.in_time_zone(TIME_ZONE)
      local.wday == common['weekly_wday'].to_i && local.hour == common['weekly_hour'].to_i.clamp(0, 23)
    end

    def weekly!(now = Time.now.utc)
      key = "game/weekly/#{now.in_time_zone(TIME_ZONE).to_date.cweek}-#{now.in_time_zone(TIME_ZONE).to_date.cwyear}"
      return if Rails.cache.read(key)

      Rails.cache.write(key, true, expires_in: 8.days)
      post_weekly!(now)
    end

    def post_weekly!(now = Time.now.utc)
      common = Game::Config.for('common')
      since = now - 7.days
      week = GameHousePoint.where(created_at: since..now).group(:game_house_id).sum(:amount)
      houses = GameHouse.active.map { |house| [house, week.fetch(house.id, 0), house.total] }.sort_by { |_, gained, total| [-gained, -total] }
      games = GameSession.where(status: 'finished', finished_at: since..now).count
      wins = GamePlayer.joins(:session).where(result: 'win', game_sessions: { finished_at: since..now }).group(:account_id).count
      best = wins.values.max
      top = best ? Account.where(id: wins.select { |_, count| count == best }.keys).map { |account| GameCharacter.for(account).display_name } : []

      local_since = since.in_time_zone(TIME_ZONE).strftime('%m/%d')
      local_now = now.in_time_zone(TIME_ZONE).strftime('%m/%d')
      text = Game::Text.render(common['msg_weekly'],
                               range: "#{local_since}~#{local_now}",
                               houses: houses.map { |house, gained, total| "#{house.label} +#{gained} (합계 #{total})" }.join("\n"),
                               games: games,
                               winners: top.any? ? "#{top.join(', ')} (#{best}승)" : '-')
      announce(text, {
        'kind' => 'weekly',
        'name' => I18n.t('game.summary.weekly', default: '주간 결산'),
        'data' => {
          'range' => "#{local_since}~#{local_now}",
          'houses' => houses.map { |house, gained, total| { 'house' => Game::Card.house_card(house), 'gained' => gained, 'total' => total } },
          'games' => games,
          'winners' => top,
          'best' => best.to_i,
        },
      })
    end

    # 학기 마감: 소속 순위, 우승 소속, 과목별 수석 (O 가 가장 많은 사람, 같으면 평균 등급이 좋은 사람)
    def term_end!
      common = Game::Config.for('common')
      houses = GameHouse.active.map { |house| [house, house.total] }.sort_by { |_, total| -total }
      champion = houses.first&.first
      toppers = Game::Lessons.all.filter_map do |kind|
        grades = GameGrade.where(subject: kind.key).group_by(&:account_id)
        next if grades.empty?

        account_id, list = grades.max_by do |_, items|
          ranks = items.map { |grade| GameGrade.rank_of(grade.grade) }
          [items.count { |grade| grade.grade == 'O' }, -(ranks.sum.to_f / ranks.size)]
        end
        { 'subject' => kind.display_name, 'name' => GameCharacter.for(Account.find(account_id)).display_name, 'best' => GameGrade.best(list.map(&:grade)) }
      end

      text = Game::Text.render(common['msg_term'],
                               houses: houses.each_with_index.map { |(house, total), index| "#{index + 1}. #{house.label} #{total}점" }.join("\n"),
                               term: common['house_term'], emoji: champion&.emoji, house: champion&.name || '-',
                               toppers: toppers.map { |row| "#{row['subject']}: #{row['name']} (#{row['best']})" }.join("\n").presence || '-')
      announce(text, {
        'kind' => 'term',
        'name' => I18n.t('game.summary.term', default: '학기 마감'),
        'data' => {
          'houses' => houses.map { |house, total| { 'house' => Game::Card.house_card(house), 'total' => total } },
          'champion' => Game::Card.house_card(champion),
          'toppers' => toppers,
        },
      })
    end

    def announce(text, card)
      status = Game::Poster.post(text, mentions: [], thread: nil, visibility: 'private')
      return if status.nil?

      payload = { 'version' => Game::Card::VERSION, 'lesson' => false, 'phase' => 'finished', 'turn' => 0, 'players' => [], 'actions' => [], 'awards' => [] }
      GameEvent.create!(status: status, payload: payload.merge(card))
      status
    end
  end
end
