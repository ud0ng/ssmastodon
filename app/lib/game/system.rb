# frozen_string_literal: true

module Game
  # 게임을 진행하는 시스템 계정 (공통 설정의 시스템 계정 아이디, 기본 @system)
  module System
    module_function

    def username
      Game::Config.for('common')['system_username'].to_s.delete_prefix('@').strip
    end

    def account
      name = username
      name.present? ? Account.local.find_by(username: name) : nil
    end

    # 툿마다 부르는 곳(StatusSerializer)용. 시스템 계정 아이디를 바꾸면 몇 분 뒤 반영된다.
    def cached_account_id
      # 계정이 아직 없을 때는 기억하지 않는다 (만들자마자 카드가 보이게)
      Rails.cache.fetch('game/system_account_id', expires_in: 5.minutes, skip_nil: true) { account&.id }
    end

    # 사람이 시스템 계정을 멘션한 툿인가
    def mentioned_in?(status)
      system = account
      return false if system.nil? || status.account_id == system.id || !status.local?

      status.mentions.any? { |mention| mention.account_id == system.id && !mention.silent? }
    end

    # 컨텐츠 안에서 쓰지 않는 기본 명령어: 도움말·점수·내전적·사용. 이 명령어와 그 답장, 단순 멘션은 웹 알림창에도 보인다
    def basic_commands
      common = Game::Config.for('common')
      use = Game::Config.for('currency')['cmd_use'].to_s.strip.presence || '사용'
      [Game::Help.system_command.presence, common['cmd_points'], common['cmd_record'], use].map { |name| name.to_s.strip }.compact_blank.uniq
    end

    # 툿 글의 첫 [명령어] 이름 ("[먹기/2]" → "먹기"), 없으면 nil
    def command_of(text)
      Game::Engine.parse(text)&.first.to_s.strip.presence
    end

    # 웹 알림창에서 숨길 컨텐츠 알림인가: 시스템이 보낸 알림(기본 명령어에 단 답장은 빼고), 시스템을 멘션하며 컨텐츠 명령어를 쓴 툿의 멘션 알림, 그 컨텐츠 대화 안의 멘션 알림
    # (Notification.without_game 의 SQL 과 같은 판단)
    def hidden_notification?(notification)
      system = account
      return false if system.nil?

      status = notification.type == :mention ? notification.target_status : nil
      if notification.from_account_id == system.id
        parent = status&.in_reply_to_id && Status.find_by(id: status.in_reply_to_id)
        return !(parent && basic_commands.include?(command_of(parent.text)))
      end

      command = status && command_of(status.text)
      return true if command.present? && !basic_commands.include?(command) && status.mentions.any? { |mention| mention.account_id == system.id }

      status.present? && game_conversation?(status)
    end

    # 컨텐츠 명령어 툿이 있는 대화인가: 그 대화에서 캐릭터들이 나눈 말도 컨텐츠 안에서만 보인다 (Notification.without_game 의 SQL 과 같은 판단)
    def game_conversation?(status)
      return false if status.conversation_id.nil?

      basic = basic_commands
      Status.where(conversation_id: status.conversation_id).joins(:mentions).where(mentions: { account_id: account.id }).any? do |toot|
        command = command_of(toot.text)
        command.present? && basic.exclude?(command)
      end
    end

    # 게임 명령어로 처리할 툿 (Game::MentionWorker)
    def command_toot?(status)
      mentioned_in?(status)
    end
  end
end
