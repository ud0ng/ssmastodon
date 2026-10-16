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

    # 게임 명령어로 처리할 툿 (Game::MentionWorker)
    def command_toot?(status)
      mentioned_in?(status)
    end
  end
end
