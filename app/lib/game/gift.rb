# frozen_string_literal: true

module Game
  # 웹 선물·아이템 사용 알림.
  #   announce  쓴 사람이 직접 보내는 툿: 받는 사람과 상점 봇(상점 계정)을 멘션하고 명령어 모양(［양도/아이템/캐릭터］)을 넣는다.
  #             앱에서도 받은 사람이 알림으로 보고, 봇·운영진이 기록으로 볼 수 있다. 명령어 괄호는 전각(［ ］)이라
  #             상점 봇이나 시스템이 다시 처리하지 않는다 (웹이 이미 처리했다). 호울러처럼 비밀이면 봇에게만 DM.
  #   notify    시스템 계정이 받는 사람에게만 DM (from 이 없을 때)
  # 알림이 실패해도 선물·사용은 그대로.
  # 문구는 컨텐츠 설정 > 명령어 > 일반 문구 · 선물 알림 (msg_gift_item / msg_gift_money / msg_item_use).
  module Gift
    module_function

    def notify(template, receiver, from: nil, **values)
      text = Game::Text.render(template, **values)
      return Game::Poster.post(text, mentions: [receiver], thread: nil, visibility: 'direct') if from.nil?

      announce(from, command: nil, text: text, receivers: [receiver])
    end

    # command: ['양도', '사과: 2', '캐릭터명'] → ［양도/사과: 2/캐릭터명］
    def announce(from, command:, text: nil, receivers: [], system: false, visibility: 'direct')
      accounts = [*receivers, (Game::System.account if system), *bot_accounts].compact.uniq(&:id)
      return nil if accounts.empty? && visibility == 'direct'

      mentions = accounts.map { |account| "@#{account.username}" }.join(' ')
      line = command.present? ? command_text(command) : nil
      body = [[mentions, line].compact_blank.join(' '), text.to_s.gsub(Game::Text::AVATAR_PATTERN, '').strip].compact_blank.join("\n")
      PostStatusService.new.call(from, text: body, visibility: visibility)
    rescue => e
      Rails.logger.warn { "gift announce failed: #{e.class} #{e.message}" }
      nil
    end

    def command_text(parts)
      "［#{Array(parts).join('/')}］"
    end

    # 상점 봇(컨텐츠 설정 > 설정 > 상점 계정 아이디)
    def bot_accounts
      names = Game::Config.for('common')['bot_usernames'].to_s.split(/[,\s]+/).map { |name| name.delete_prefix('@') }.compact_blank
      names.empty? ? [] : Account.local.where(username: names).to_a
    end
  end
end
