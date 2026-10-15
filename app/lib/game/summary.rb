# frozen_string_literal: true

module Game
  # 시즌 결산 툿 (캐릭터 관리 > 소속 > 시즌의 버튼). 웹에서는 카드(GameEvent, 판 없음)로도 보인다.
  #   중간 결산: 지금까지의 소속 점수
  #   시즌 종료: 최종 점수를 발표하고 시즌을 끝낸다 → 소속 점수는 0부터 다시 (GameHouse#total)
  module Summary
    module_function

    def season_interim!(season)
      rows = Game::Points.ranking
      announce(season_text('msg_season_interim', season, rows), season_card(season, rows, I18n.t('game.summary.interim', default: '중간 결산')))
    end

    def season_final!(season)
      rows = Game::Points.ranking
      status = announce(season_text('msg_season_final', season, rows), season_card(season, rows, I18n.t('game.summary.final', default: '시즌 종료')))
      season.update!(status: 'finished', finished_at: Time.now.utc,
                     results: rows.map { |house, total| { 'house_id' => house.id, 'name' => house.name, 'color' => house.color, 'total' => total } })
      status
    end

    def season_text(key, season, rows)
      common = Game::Config.for('common')
      champion = rows.first&.first
      Game::Text.render(common[key], season: season.name, period: season.period, houses: Game::Points.ranking_lines(rows).join("\n"),
                                     term: common['house_term'], house: champion&.name || '-')
    end

    def season_card(season, rows, title)
      {
        'kind' => 'term',
        'name' => "#{season.name} · #{title}",
        'data' => {
          'houses' => rows.map { |house, total| { 'house' => Game::Card.house_card(house), 'total' => total } },
          'champion' => Game::Card.house_card(rows.first&.first),
          'toppers' => [],
        },
      }
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
