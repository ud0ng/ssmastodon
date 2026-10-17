# frozen_string_literal: true

module Game
  # 웹 선물·아이템 사용 알림.
  #   from 이 있으면 쓴 사람이 직접 보낸 DM 으로 남긴다: 상대 캐릭터와 상점 봇(상점 계정)을 멘션해서, 앱에서도 받은 사람이 알림으로 보고
  #   봇·운영진이 기록으로 볼 수 있다. (본문에 [명령어]가 없어서 봇이 다시 처리하지는 않는다)
  #   from 이 없으면 시스템 계정이 받는 사람에게만 DM. 알림이 실패해도 선물·사용은 그대로.
  # 문구는 컨텐츠 설정 > 명령어 > 일반 문구 · 선물 알림 (msg_gift_item / msg_gift_money / msg_item_use).
  module Gift
    module_function

    def notify(template, receiver, from: nil, **values)
      text = Game::Text.render(template, **values)
      return Game::Poster.post(text, mentions: [receiver], thread: nil, visibility: 'direct') if from.nil?

      mentions = [receiver, *bot_accounts].uniq.map { |account| "@#{account.username}" }.join(' ')
      PostStatusService.new.call(from, text: "#{mentions} #{text.gsub(Game::Text::AVATAR_PATTERN, '')}".strip, visibility: 'direct')
    rescue => e
      Rails.logger.warn { "gift notification failed: #{e.class} #{e.message}" }
      nil
    end

    # 상점 봇(컨텐츠 설정 > 설정 > 상점 계정 아이디)
    def bot_accounts
      names = Game::Config.for('common')['bot_usernames'].to_s.split(/[,\s]+/).map { |name| name.delete_prefix('@') }.compact_blank
      names.empty? ? [] : Account.local.where(username: names).to_a
    end
  end
end
