# frozen_string_literal: true

module Game
  # 토너먼트제 진행: 정해진 시간에 경기를 열고(Game::TournamentWorker), 끝나면 승자를 다음 칸으로 올리고,
  # 마지막 경기가 끝나면 소속별 승수를 세어 우승 소속에 점수를 준다.
  # 시간 초과·무승부는 경기를 멈추고 운영진 판정(decide!)을 기다린다.
  module Tournament
    module_function

    def scoring_mode?
      Game::Config.for('common')['scoring_mode'] == 'tournament'
    end

    def start!(tournament)
      tournament.update!(status: 'running')
      tournament.matches.each { |match| schedule!(match) }
    end

    # 선수·컨텐츠·시간이 다 정해진 경기를 예약한다 (바뀌면 다시 예약, 예전 작업은 token 으로 무시)
    def schedule!(match)
      return unless match.tournament.status == 'running' && %w(waiting ready judging).include?(match.status)

      unless match.ready_to_schedule?
        match.update!(status: 'waiting')
        return
      end

      match.update!(status: 'ready')
      Game::TournamentWorker.perform_at([match.scheduled_at, Time.now.utc].max, match.id, match.schedule_token)
    end

    # 예약 시간이 된 경기를 연다: 공지 툿(새 스레드) → 컨텐츠 시작
    def open!(match)
      common = Game::Config.for('common')
      kind = Game::Kinds.fetch(match.kind)
      session = GameSession.transaction do
        GameSession.create!(kind: match.kind, status: 'active', visibility: 'private', state: { 'tournament_match_id' => match.id }).tap do |created|
          created.players.create!(account: match.player_a, seat: 0, state: { 'accepted' => true })
          created.players.create!(account: match.player_b, seat: 1, state: { 'accepted' => true })
        end
      end
      match.update!(status: 'playing', session: session)

      tournament = match.tournament
      text = Game::Text.render(common['msg_tournament_open'],
                               tournament: tournament.name, round: tournament.round_name(match.round), number: match.position + 1,
                               player_a: match.player_a, player_b: match.player_b, game: kind.display_name)
      announcement = Game::Poster.post(text, mentions: match.players, thread: nil, visibility: 'private')
      session.update!(root_status_id: announcement&.id, last_status_id: announcement&.id)
      Game::Poster.record_card(session, announcement, nil) if announcement
      kind.new(session).start!
    end

    # 컨텐츠가 끝났을 때 (Kinds::Base#finish! 가 부른다)
    def finished!(session, winner_player, draw:)
      match = GameTournamentMatch.find_by(id: session.state['tournament_match_id'])
      return if match.nil? || match.status == 'done'

      if draw || winner_player.nil?
        match.update!(status: 'judging')
        return
      end

      win!(match, winner_player.account)
    end

    # 시간 초과: 자동으로 지게 하지 않고 운영진 판정을 기다린다
    def judging!(session, reason)
      match = GameTournamentMatch.find_by(id: session.state['tournament_match_id'])
      session.update!(status: 'cancelled', finished_at: Time.now.utc, deadline_at: nil)
      match&.update!(status: 'judging')
      Game::Poster.to_session(session, Game::Text.render(Game::Config.for('common')['msg_tournament_judging'], reason: reason))
    end

    # 운영진 판정 (관리 화면)
    def decide!(match, winner)
      return unless match.players.include?(winner)

      session = match.session
      if session&.open?
        session.update!(status: 'cancelled', finished_at: Time.now.utc, deadline_at: nil)
      end
      if session
        Game::Poster.to_session(session, Game::Text.render(Game::Config.for('common')['msg_tournament_decided'], winner: winner))
      end
      win!(match, winner)
    end

    def win!(match, winner)
      match.update!(winner: winner, status: 'done')
      following = match.next_match
      if following
        following.update!(match.position.even? ? { player_a: winner } : { player_b: winner })
        schedule!(following)
      else
        complete!(match.tournament)
      end
    end

    # 소속별 승수가 가장 많은 소속이 우승 (동률이면 결승 승자의 소속)
    def complete!(tournament)
      tournament.matches.reload
      wins = tournament.house_wins
      best = wins.values.max
      leaders = wins.select { |_, count| count == best }.keys
      final_house = tournament.final&.winner && GameCharacter.for(tournament.final.winner).house
      champion = leaders.include?(final_house) ? final_house : leaders.first

      tournament.update!(status: 'finished', finished_at: Time.now.utc, winner_house: champion)
      return if champion.nil?

      GameHousePoint.create!(house: champion, amount: tournament.reward, reason: "tournament:#{tournament.id}") if tournament.reward.positive?

      common = Game::Config.for('common')
      tally = wins.sort_by { |_, count| -count }.map { |house, count| "#{house.label} #{count}승" }.join("\n")
      status = Game::Poster.post(Game::Text.render(common['msg_tournament_champion'],
                                                   tournament: tournament.name, tally: tally, emoji: champion.emoji, house: champion.name, reward: tournament.reward),
                                 mentions: [], thread: nil, visibility: 'private')
      GameEvent.create!(status: status, payload: Game::Card.champion(tournament, wins, champion)) if status
    end

    def name(account)
      GameCharacter.for(account).display_name
    end
  end
end
