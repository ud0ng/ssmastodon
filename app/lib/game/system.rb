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

    # 사람이 시스템 계정을 멘션한 툿인가
    def mentioned_in?(status)
      system = account
      return false if system.nil? || status.account_id == system.id || !status.local?

      status.mentions.any? { |mention| mention.account_id == system.id && !mention.silent? }
    end
  end
end
