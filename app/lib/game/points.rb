# frozen_string_literal: true

module Game
  # 소속 점수 지급. 점수 방식(캐릭터 관리 > 소속 > 시즌):
  #   점수제(points) 컨텐츠마다 정한 점수 (승리·무승부·패배)   판수제(games) 이긴 판마다 1점
  module Points
    module_function

    def games_mode?
      Game::Config.for('common')['scoring_mode'] == 'games'
    end

    # 게임 결과로 점수를 준다. outcome: 'win' / 'draw' / 'lose'. 지급 안내 문구를 돌려준다 (안 줬으면 nil)
    def award(session, player, amount, outcome: 'win')
      amount = games_mode? ? (outcome == 'win' ? 1 : 0) : amount.to_i
      return if amount <= 0
      # 토너먼트제 기간에는 평소 컨텐츠 점수가 없다 (우승 점수만)
      return if Game::Tournament.scoring_mode?

      give(session, player, amount, reason: session.kind)
    end

    # 상대 없이 주는 점수 (마법 수업·이벤트 등)
    def give(session, player, amount, reason:)
      return if amount.to_i <= 0
      return if Game::Tournament.scoring_mode?

      common = Game::Config.for('common')
      house = player.character.group
      return Game::Text.render(common['msg_no_house'], player: player, term: common['house_term']) if house.nil?

      GameHousePoint.create!(house: house, account: player.account, session: session, amount: amount.to_i, reason: reason)
      Game::Text.render(common['msg_points'], emoji: house.emoji, house: house.name, amount: amount.to_i, player: player, term: common['house_term'])
    end

    # [점수] 답장 (이번 시즌 점수)
    def board
      common = Game::Config.for('common')
      ([Game::Text.render(common['msg_board'], term: common['house_term'])] + ranking_lines).join("\n")
    end

    # 소속 순위 줄 ("1. 그리핀도르 120점")
    def ranking
      GameHouse.active.map { |house| [house, house.total] }.sort_by { |_, total| -total }
    end

    def ranking_lines(rows = ranking)
      rows.each_with_index.map { |(house, total), index| "#{index + 1}. #{house.label} #{total}점" }
    end

    # [내전적] 답장
    def record(account)
      results = GamePlayer.joins(:session).where(account: account, game_sessions: { status: 'finished' }).group(:result).count
      Game::Text.render(Game::Config.for('common')['msg_record'],
                        player: account,
                        win: results['win'].to_i, lose: results['lose'].to_i, draw: results['draw'].to_i)
    end
  end
end
