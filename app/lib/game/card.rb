# frozen_string_literal: true

module Game
  # 시스템 툿을 PC 웹에서 '컨텐츠 카드'로 그리기 위한 그 순간의 컨텐츠 상태.
  # Game::Poster.to_session 이 툿을 올릴 때 GameEvent 로 저장하고, REST::StatusSerializer 가 game_card 로 내보낸다.
  # (앱은 모르는 필드를 무시하므로 지금처럼 툿 텍스트로 보인다)
  #
  # 공개 결과만 담는다. DM 으로 받은 비밀 선택(주문·조합 등)은 결과가 공개된 뒤의 것만.
  #
  #   kind / name / lesson / mode   컨텐츠 종류·이름, 마법 수업이면 자습(study)·수업(class)
  #   phase                         pending(신청·모집) / active / finished / cancelled
  #   turn, deadline_at             턴, 이번 단계 마감 시각
  #   players                       [{ seat, account_id, acct, name, avatar, house, result, accepted }]
  #   data                          컨텐츠별 공개 상태 (각 Kinds 의 card_data)
  #   actions                       웹 행동 버튼 [{ label, command, seats, dm }] — seats 가 'others' 면 아직 안 낀 사람
  module Card
    VERSION = 1

    module_function

    def build(session, kind = nil)
      kind ||= session.kind_class&.new(session)
      kind_class = session.kind_class

      {
        'version' => VERSION,
        'session_id' => session.id.to_s,
        'kind' => session.kind,
        'name' => kind_class&.display_name || session.kind,
        'lesson' => kind_class&.lesson? || false,
        'mode' => session.state['mode'],
        'phase' => session.status,
        'turn' => session.turn,
        'deadline_at' => session.deadline_at&.iso8601,
        'players' => session.players.map { |player| player_card(player) },
        'data' => safe { kind&.card_data } || {},
        'tournament' => safe { tournament_info(session) },
        'awards' => safe { awards(session) } || [],
        'rewards' => safe { rewards(session) } || [],
        'actions' => session.open? ? (safe { actions_for(session, kind) } || []) : [],
      }
    end

    # 토너먼트 경기면 대회 이름·라운드·경기 번호
    def tournament_info(session)
      match = GameTournamentMatch.find_by(id: session.state['tournament_match_id']) if session.state['tournament_match_id']
      return if match.nil?

      tournament = match.tournament
      { 'name' => tournament.name, 'round' => tournament.round_name(match.round), 'number' => match.position + 1 }
    end

    # 이 판으로 받은 소속 점수 (결과 툿 아래에 '🦁 그리핀도르 +5')
    def awards(session)
      GameHousePoint.where(game_session_id: session.id).includes(:house).order(:id).map do |point|
        { 'house' => house_card(point.house), 'amount' => point.amount }
      end
    end

    # 이 판으로 받은 돈·아이템 (사람마다 한 줄)
    def rewards(session)
      currency = Game::Config.for('common')['currency_name']
      GameReward.where(game_session_id: session.id).includes(:account).order(:id).map do |reward|
        { 'name' => GameCharacter.for(reward.account).display_name, 'money' => reward.money, 'currency' => currency,
          'items' => reward.items.map { |item| Game::Rewards.item_label(item) } }
      end
    end

    def house_card(house)
      house && { 'name' => house.name, 'color' => house.color, 'emoji' => house.emoji }
    end

    # 토너먼트 우승 발표 (판이 없는 카드)
    def champion(tournament, wins, champion)
      {
        'version' => VERSION,
        'kind' => 'tournament',
        'name' => tournament.name,
        'lesson' => false,
        'phase' => 'finished',
        'turn' => 0,
        'players' => [],
        'data' => {
          'champion' => house_card(champion),
          'reward' => tournament.reward,
          'tally' => wins.sort_by { |_, count| -count }.map { |house, count| { 'house' => house_card(house), 'wins' => count } },
        },
        'actions' => [],
        'awards' => [],
      }
    end

    def player_card(player)
      account = player.account
      house = player.character.group
      {
        'seat' => player.seat,
        'account_id' => account.id.to_s,
        'acct' => account.acct,
        'name' => player.name,
        'avatar' => account.avatar_static_url,
        'house' => house_card(house),
        'result' => player.result,
        'accepted' => player.state['accepted'] ? true : false,
      }
    end

    def actions_for(session, kind)
      common = Game::Config.for('common')

      if session.status == 'pending'
        if session.state['mode'] == 'class'
          [action(Game::Lessons.config['cmd_join'], seats: 'others')]
        elsif session.state['mode'] == 'event'
          [action(session.kind_class.config['cmd_join'], seats: 'others')]
        else
          waiting = session.players.reject { |player| player.state['accepted'] }.map(&:seat)
          waiting.empty? ? [] : [action(common['cmd_accept'], seats: waiting), action(common['cmd_decline'], seats: waiting, style: 'secondary')]
        end
      else
        kind&.card_actions || []
      end
    end

    # 웹 버튼 하나: 누르면 '@시스템 [command]' 툿을 쓰는 창이 열린다 (dm 이면 DM 으로)
    def action(command, seats:, label: nil, dm: false, style: 'primary')
      { 'label' => label || command, 'command' => command, 'seats' => seats, 'dm' => dm, 'style' => style }
    end

    # 카드는 덤이라 계산하다 잘못돼도 툿 올리기를 막지 않는다
    def safe
      yield
    rescue => e
      Rails.logger.warn { "Game::Card: #{e.class} #{e.message}" }
      nil
    end
  end
end
