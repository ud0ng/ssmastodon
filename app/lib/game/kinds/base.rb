# frozen_string_literal: true

module Game
  module Kinds
    # 게임 종류의 공통 부분. 하위 클래스는 KEY, FIELDS 와 start! / handle / timeout! 을 정한다.
    class Base
      F = Game::Config::Field

      # 모든 게임에 있는 설정 (켜기, 이름, 시작 명령어, 점수)
      def self.base_fields(name:, command:, points_win:, points_draw: 0)
        [
          F.new(key: 'enabled', type: :boolean, default: true, group: 'basic', label: '켜기'),
          F.new(key: 'name', type: :string, default: name, group: 'basic', label: '컨텐츠 이름'),
          F.new(key: 'command', type: :string, default: command, group: 'basic', label: '시작 명령어', hint: '[명령어] 와 상대를 태그해 신청'),
          F.new(key: 'points_win', type: :integer, default: points_win, group: 'points', label: '승리 점수'),
          F.new(key: 'points_draw', type: :integer, default: points_draw, group: 'points', label: '무승부 점수'),
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

        # 마법 수업 과목인가 (Game::Lessons::Base)
        def lesson?
          false
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
        winner = session.opponent_of(player)
        finish!(winner: winner, message: render(common['msg_forfeit'], player: player, winner: winner))
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
        Game::Engine.set_deadline!(session, common['turn_minutes'].to_i)
      end

      # 게임 끝: 결과 기록, 점수 지급, 결과 툿
      def finish!(winner: nil, message: nil, draw: false)
        players.each do |player|
          player.update!(result: draw ? 'draw' : (player == winner ? 'win' : 'lose'))
        end
        session.update!(status: 'finished', finished_at: Time.now.utc, deadline_at: nil)

        # 토너먼트 경기: 점수 대신 승자를 다음 칸으로 (무승부면 운영진 판정)
        if tournament?
          post(message) if message
          Game::Tournament.finished!(session, winner, draw: draw)
          return
        end

        point_lines = if draw
                        players.map { |player| Game::Points.award(session, player, config['points_draw']) }
                      elsif winner
                        [Game::Points.award(session, winner, config['points_win'])]
                      else
                        []
                      end
        post([message, *point_lines.compact].compact.join("\n\n"))
      end
    end
  end
end
