# frozen_string_literal: true

module Game
  # 기숙사 점수 지급 (공통 규칙: 같은 상대와 하루 N판까지, 같은 기숙사끼리면 일부만)
  module Points
    module_function

    # 게임 결과로 점수를 준다. 지급 안내 문구를 돌려준다 (안 줬으면 nil 또는 기숙사 없음 안내)
    def award(session, player, amount)
      return if amount.to_i <= 0
      # 토너먼트제 기간에는 평소 컨텐츠 점수가 없다 (우승 점수만)
      return if Game::Tournament.scoring_mode?

      common = Game::Config.for('common')
      character = player.character
      house = character.house
      return Game::Text.render(common['msg_no_house'], player: character.display_name, term: common['house_term']) if house.nil?

      opponents = session.players.reject { |other| other.id == player.id }
      return if over_daily_limit?(player.account, opponents.map(&:account_id), common['daily_pair_limit'].to_i)

      amount = amount.to_i
      amount = (amount * common['same_house_percent'].to_i / 100.0).round if opponents.any? { |other| other.character.game_house_id == house.id }
      return if amount <= 0

      GameHousePoint.create!(house: house, account: player.account, session: session, amount: amount, reason: session.kind)
      Game::Text.render(common['msg_points'], emoji: house.emoji, house: house.name, amount: amount, player: character.display_name, term: common['house_term'])
    end

    # 오늘(한국 시간) 같은 상대와의 게임으로 이미 limit 번 점수를 받았는가
    def over_daily_limit?(account, opponent_ids, limit)
      return false if limit <= 0 || opponent_ids.empty?

      shared = GamePlayer.where(account_id: opponent_ids).select(:game_session_id)
      GameHousePoint.where(account: account, game_session_id: shared)
                    .where(created_at: Time.now.in_time_zone('Asia/Seoul').beginning_of_day..)
                    .count >= limit
    end

    # [점수] 답장
    def board
      common = Game::Config.for('common')
      houses = GameHouse.all.map { |house| [house, house.total] }.sort_by { |_, total| -total }
      lines = houses.each_with_index.map { |(house, total), index| "#{index + 1}. #{house.label} #{total}점" }
      ([Game::Text.render(common['msg_board'], term: common['house_term'])] + lines).join("\n")
    end

    # [내전적] 답장
    def record(account)
      results = GamePlayer.joins(:session).where(account: account, game_sessions: { status: 'finished' }).group(:result).count
      Game::Text.render(Game::Config.for('common')['msg_record'],
                        player: GameCharacter.for(account).display_name,
                        win: results['win'].to_i, lose: results['lose'].to_i, draw: results['draw'].to_i)
    end
  end
end
