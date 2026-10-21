# frozen_string_literal: true

module Game
  # 컨텐츠 신청 횟수 제한 (컨텐츠 설정 > 설정 > 룰 설정). 둘 다 0 이면 제한 없음.
  #   daily_game_limit      컨텐츠를 모두 합해 하루 동안 내가 보낸 신청 수
  #   daily_opponent_limit  같은 상대와 하루 동안 보낸 신청 수 (컨텐츠를 모두 합해)
  # 센 것: 내가 신청한 판(첫 자리)만. 운영진이 연 이벤트·토너먼트 경기는 세지 않는다. 하루는 한국 시간 0시 기준.
  # 신청할 때 (멘션·웹 버튼 모두) 넘으면 신청되지 않고 안내 문구를 돌려준다.
  module DailyLimits
    module_function

    # 신청해도 되면 nil, 안 되면 안내 문구
    def check(actor, opponents, kind: nil)
      common = Game::Config.for('common')
      game_limit = common['daily_game_limit'].to_i
      opponent_limit = common['daily_opponent_limit'].to_i
      return if game_limit <= 0 && opponent_limit <= 0

      sent = sent_today(actor)
      if game_limit.positive? && sent.count >= game_limit
        return Game::Text.render(common['msg_daily_limit'], game: kind&.display_name.to_s, limit: game_limit)
      end

      if opponent_limit.positive?
        opponents.each do |opponent|
          next if sent.where(id: GamePlayer.where(account_id: opponent.id).select(:game_session_id)).count < opponent_limit

          return Game::Text.render(common['msg_opponent_limit'], game: kind&.display_name.to_s, opponent: opponent, limit: opponent_limit)
        end
      end
      nil
    end

    # 오늘 내가 보낸 신청 (모두 합쳐서, 취소·거절된 것도 센다)
    def sent_today(actor)
      today = Time.now.in_time_zone('Asia/Seoul').beginning_of_day
      GameSession.current_kinds.real.joins(:players)
                 .where(game_players: { account_id: actor.id, seat: 0 })
                 .where(created_at: today..)
                 .where("COALESCE(game_sessions.state->>'mode', '') <> 'event'")
                 .where("game_sessions.state->>'tournament_match_id' IS NULL")
                 .distinct
    end
  end
end
