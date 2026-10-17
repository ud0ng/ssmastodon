# frozen_string_literal: true

module Game
  module Kinds
    # 게임 종류의 공통 부분. 하위 클래스는 KEY, FIELDS 와 start! / handle / timeout! 을 정한다.
    class Base
      F = Game::Config::Field

      # 모든 게임에 있는 설정 (켜기, 이름, 시작 명령어, 점수, 보상)
      def self.base_fields(name:, command:, points_win:, points_draw: 0, points_lose: 0)
        [
          F.new(key: 'enabled', type: :boolean, default: true, group: 'basic', label: '켜기'),
          F.new(key: 'name', type: :string, default: name, group: 'basic', label: '컨텐츠 이름'),
          F.new(key: 'description', type: :string, default: '', group: 'basic', label: '설명', hint: '웹 컨텐츠 메뉴에 보이는 한 줄 소개. 비우면 기본 소개를 씁니다'),
          F.new(key: 'command', type: :string, default: command, group: 'basic', label: '시작 명령어', hint: '[명령어] 와 상대를 태그해 신청'),
          F.new(key: 'points_win', type: :integer, default: points_win, group: 'points', label: '승리 점수'),
          F.new(key: 'points_draw', type: :integer, default: points_draw, group: 'points', label: '무승부 점수'),
          F.new(key: 'points_lose', type: :integer, default: points_lose, group: 'points', label: '패배 점수', hint: '판수제에서는 쓰지 않습니다'),
          F.new(key: 'reward_money_win', type: :integer, default: 10, group: 'rewards', label: '승리 돈'),
          F.new(key: 'reward_money_draw', type: :integer, default: 5, group: 'rewards', label: '무승부 돈'),
          F.new(key: 'reward_money_lose', type: :integer, default: 2, group: 'rewards', label: '패배(참가) 돈'),
          F.new(key: 'reward_items_win', type: :lines, default: ['초콜릿 개구리|1|30'], group: 'rewards', label: '승리 아이템', hint: Game::Rewards::ITEMS_HINT),
        ]
      end

      class << self
        def key
          self::KEY
        end

        def schema
          self::FIELDS
        end

        def config
          Game::Config.for(key)
        end

        def enabled?
          config['enabled']
        end

        def display_name
          config['name']
        end

        # 턴 시간 초과가 그 컨텐츠 규칙의 일부인가 (곱스톤 빗나감, 결투 주문 실패 등).
        # false 면 시간 초과 = 패배이고, 토너먼트 경기에서는 운영진 판정으로 넘긴다.
        def continues_on_timeout?
          false
        end

        # 여러 날 진행하는 서버 이벤트인가 (Game::Events)
        def event?
          false
        end

        # 웹 진행 화면에서만 하는 컨텐츠인가 (Game::Web)
        def web?
          false
        end

        # 신청할 때 함께 태그할 수 있는 상대 수 (1:1 이면 1)
        def max_opponents
          1
        end

        # 신청할 때 태그해야 하는 최소 상대 수 (신청자 제외)
        def min_opponents
          1
        end

        # 팀 대결인가 (퀴디치): 웹 신청은 우리 팀을 먼저 고르고 상대 팀을 고른다
        def team_game?
          false
        end

        # 인원이 규칙에 맞지 않으면 안내 문구 (total: 신청자 포함 인원)
        def invite_error(_total)
          nil
        end
      end

      attr_reader :session

      def initialize(session)
        @session = session
      end

      def config
        @config ||= self.class.config
      end

      def common
        @common ||= Game::Config.for('common')
      end

      def players
        session.players
      end

      def state
        session.state
      end

      # PC 웹 카드에 보일 공개 상태 (Game::Card). 하위 클래스가 채운다.
      def card_data
        {}
      end

      # PC 웹 카드의 행동 버튼 (진행 중일 때). Game::Card.action 으로 만든다.
      def card_actions
        []
      end

      # 동시에 고르는 컨텐츠(결투·퀴디치·비행)에서 아직 이번 턴 선택을 내지 않은 자리들 — 선택한 사람의 웹 버튼·'내 차례'를 거두는 데 쓴다
      def pending_seats
        players.map(&:seat).reject { |seat| (state['choices'] || {}).key?(seat.to_s) }
      end

      # 최대 라운드(턴) 수: 방 맨 위에 '1라운드 / 10라운드' 로 보여 준다. 정해져 있지 않으면 nil
      def max_turns
        nil
      end

      # 수락되어 게임이 시작될 때
      def start!
        raise NotImplementedError
      end

      # 진행 중 명령어. 처리했으면 true
      def handle(_player, _command, _args, _status)
        false
      end

      # 턴 시간 초과
      def timeout!
        raise NotImplementedError
      end

      # 기권 → 상대 승리
      def forfeit!(player)
        winners = forfeit_winners(player)
        finish!(winners: winners, message: render(common['msg_forfeit'], player: player, winner: winners.first))
      end

      # 기권하면 이기는 사람들: 1:1 이면 상대 (팀전은 하위 클래스가 상대 팀으로)
      def forfeit_winners(player)
        players.reject { |other| other.id == player.id }
      end

      protected

      def tournament?
        state['tournament_match_id'].present?
      end

      def render(template, **values)
        Game::Text.render(template, game: self.class.display_name, **values)
      end

      def post(text)
        Game::Poster.to_session(session, text, kind: self)
      end

      # 한 사람에게만 DM (비밀 선택 안내). 같은 DM 스레드로 이어 보낸다.
      def dm(player, text)
        thread = Status.find_by(id: player.state['dm_status_id'])
        status = Game::Poster.post(text, mentions: [player.account], thread: thread, visibility: 'direct')
        player.update!(state: player.state.merge('dm_status_id' => status.id.to_s)) if status
        status
      end

      # 비밀 선택은 DM 으로만 받는다 (공개 툿이면 안내만)
      def require_dm!(player, status)
        return true if status.direct_visibility?

        dm(player, render(common['msg_secret_in_dm']))
        false
      end

      # 다음 턴 시간 제한
      def wait_for_turn!
        Game::Engine.set_deadline_in!(session, Game::Config.turn_seconds.seconds)
      end

      # 게임 끝: 결과 기록, 점수·보상 지급, 결과 툿. winners: 팀전처럼 이긴 사람이 여럿일 때
      def finish!(winner: nil, winners: nil, message: nil, draw: false)
        winners = draw ? [] : (winners || [winner]).compact
        players.each do |player|
          player.update!(result: draw ? 'draw' : (winners.include?(player) ? 'win' : 'lose'))
        end
        session.update!(status: 'finished', finished_at: Time.now.utc, deadline_at: nil)
        reward_lines = draw || winners.any? ? give_rewards! : []

        # 토너먼트 경기: 점수 대신 승자를 다음 칸으로 (무승부면 운영진 판정). 돈·아이템 보상은 그대로.
        if tournament?
          text = [message, *reward_lines].compact.join("\n\n")
          post(text) if text.present?
          Game::Tournament.finished!(session, winners.first, draw: draw)
          return
        end

        point_lines = players.map do |player|
          outcome = player.result
          Game::Points.award(session, player, config["points_#{outcome}"], outcome: outcome)
        end
        post([message, *point_lines.compact, *reward_lines].compact.join("\n\n"))
      end

      # 결과(player.result)에 따른 돈·아이템 (Game::Rewards). 안내를 한 문단으로 묶어 [문단] 또는 [] 를 돌려준다.
      def give_rewards!
        lines = players.filter_map do |player|
          next if player.result.blank?

          Game::Rewards.for_outcome(session, player, config, player.result, reason: "game:#{self.class.key}")
        end
        lines.any? ? [lines.join("\n")] : []
      end
    end
  end
end
