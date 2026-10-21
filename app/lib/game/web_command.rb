# frozen_string_literal: true

module Game
  # 웹 전용 컨텐츠의 행동: 툿을 올리지 않고 웹에서 바로 보낸 명령어. 컨텐츠의 handle(player, command, args, status) 가 보는 status 모양이다
  # (비밀 선택이라 항상 DM 취급, targets 는 [고발] @누구 의 태그 대신 웹에서 고른 사람).
  class WebCommand
    Mention = Struct.new(:account) do
      def account_id
        account.id
      end
    end

    attr_reader :account, :text, :mentions

    def initialize(account, text, targets = [])
      @account = account
      @text = text
      @mentions = targets.map { |target| Mention.new(target) }
    end

    def id
      nil
    end

    def direct_visibility?
      true
    end

    def spoiler_text
      ''
    end

    # 진행 중인 웹 전용 판에 명령어를 넣는다 (판 잠금 안에서). 내 판이 아니거나 진행 중이 아니면 아무 일도 없다
    def self.play(session, account, command, args = [], targets: [])
      command = command.to_s.strip
      session.with_lock do
        player = session.player_for(account)
        next if command.blank? || player.nil? || session.status != 'active'

        status = new(account, "[#{[command, *args].join('/')}]", targets)
        session.kind_class.new(session).handle(player, command, Array(args), status)
      end
    end
  end
end
