# frozen_string_literal: true

module Game
  # 시스템 계정으로 툿을 올린다. 공개 범위는 게임을 신청한 툿을 따른다 (팔로워 공개 / DM).
  module Poster
    module_function

    # mentions: 멘션할 계정들 (알림이 가도록), thread: 답장할 툿
    def post(text, mentions:, thread:, visibility:)
      system = Game::System.account
      return if system.nil?

      prefix = mentions.uniq.reject { |account| account.id == system.id }.map { |account| "@#{account.acct}" }.join(' ')
      PostStatusService.new.call(
        system,
        text: [prefix.presence, text].compact.join("\n"),
        thread: thread,
        visibility: visibility,
        with_rate_limit: false
      )
    end

    # 게임 판의 스레드에 이어서 올린다 (참가자 모두 멘션)
    def to_session(session, text, mentions: nil)
      thread = Status.find_by(id: session.last_status_id || session.root_status_id)
      status = post(text, mentions: mentions || session.players.map(&:account), thread: thread, visibility: session.visibility)
      session.update!(last_status_id: status.id) if status
      status
    end
  end
end
