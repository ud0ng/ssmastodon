# frozen_string_literal: true

module Game
  # 시스템 툿을 PC 웹에서 '컨텐츠 카드'로 그리기 위한 그 순간의 컨텐츠 상태.
  # Game::Poster.to_session 이 툿을 올릴 때 GameEvent 로 저장하고, REST::StatusSerializer 가 game_card 로 내보낸다.
  # (앱은 모르는 필드를 무시하므로 지금처럼 툿 텍스트로 보인다)
  #
  # 공개 결과만 담는다. DM 으로 받은 비밀 선택(주문·조합 등)은 결과가 공개된 뒤의 것만.
  #
  #   kind / name / mode            컨텐츠 종류·이름, 서버 이벤트면 mode=event
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
        'mode' => session.state['mode'],
        'phase' => session.status,
        'turn' => session.turn,
        'max_turns' => safe { kind&.max_turns },
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
        { 'house' => house_card(point.house), 'amount' => point.amount, 'account_id' => point.account_id&.to_s }
      end
    end

    # 이 판으로 받은 돈·아이템 (사람마다 한 줄)
    def rewards(session)
      currency = Game::Config.for('common')['currency_name']
      images = GameShopItem.by_key
      GameReward.where(game_session_id: session.id).includes(:account).order(:id).map do |reward|
        { 'name' => GameCharacter.for(reward.account).display_name, 'account_id' => reward.account_id.to_s, 'money' => reward.money, 'currency' => currency,
          'items' => reward.items.map { |item| Game::Rewards.item_label(item) },
          # 웹 방 화면: 아이템 그림과 개수 (그림은 상점 아이템에 올린 것)
          'item_list' => reward.items.map { |item| item_card(item, images) } }
      end
    end

    def item_card(item, images)
      image = images[Game::Wallet.key(item['name'])]&.image
      { 'name' => item['name'], 'count' => item['count'].to_i.clamp(1, nil), 'image' => image.present? ? image.url(:small) : nil }
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

      actions =
        if session.status == 'pending'
          if session.state['mode'] == 'event'
            [action(session.kind_class.config['cmd_join'], seats: 'others')]
          else
            waiting = session.players.reject { |player| player.state['accepted'] }.map(&:seat)
            waiting.empty? ? [] : [action(common['cmd_accept'], seats: waiting), action(common['cmd_decline'], seats: waiting, style: 'secondary')]
          end
        else
          kind&.card_actions || []
        end
      actions + meta_actions(session, kind, common, actions)
    end

    # 모든 컨텐츠 공통 보조 버튼 (meta: 내 차례 알림·할 일 수에는 세지 않는다)
    #   수락 대기 중: 신청한 사람의 [신청 취소]
    #   진행 중: 내 차례인 사람의 [항복] — 1:1 이거나 팀전(기권하면 상대 팀 승리)일 때. 서버 이벤트(비밀의방 등)는 제외.
    def meta_actions(session, kind, common, actions)
      return [] if session.state['mode'] == 'event'

      if session.status == 'pending'
        seats = session.players.select { |player| player.state['accepted'] }.map(&:seat)
        return seats.empty? ? [] : [action(common['cmd_cancel'], label: '신청 취소', seats: seats, style: 'secondary', row: 9, meta: true)]
      end

      return [] unless session.players.size == 2 || session.state['teams'].present?

      seats = actions.flat_map { |each| each['seats'].is_a?(Array) ? each['seats'] : [] }.uniq
      seats = session.players.map(&:seat) if seats.empty? && session.kind_class&.web?
      seats.empty? ? [] : [action(common['cmd_forfeit'], label: '항복', seats: seats, style: 'danger', row: 9, meta: true)]
    end

    # 웹 버튼 하나: 누르면 '@시스템 [command]' 툿을 쓰는 창이 열린다 (dm 이면 DM 으로)
    # row: 버튼 줄 (웹 방 입력창 위에서 줄 단위로 나눈다. 필살기처럼 다음 줄에 둘 때 2)
    # hint: 마우스를 올리면 보이는 설명 (아이템 효과 등)
    def action(command, seats:, label: nil, dm: false, style: 'primary', row: 1, meta: false, hint: nil)
      { 'label' => label || command, 'command' => command, 'seats' => seats, 'dm' => dm, 'style' => style, 'row' => row, 'meta' => meta, 'hint' => hint }.compact
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
