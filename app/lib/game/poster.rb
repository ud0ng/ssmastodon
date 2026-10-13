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
      media_ids = avatar_media(system, text)
      PostStatusService.new.call(
        system,
        text: [prefix.presence, text.gsub(Game::Text::AVATAR_PATTERN, '').strip].compact.join("\n"),
        thread: thread,
        visibility: visibility,
        media_ids: media_ids.presence,
        with_rate_limit: false
      )
    end

    MAX_MEDIA = 4

    # 문구의 {계정 아바타} → 그 사람 프로필 사진을 첨부 (최대 4장, 기본 사진이면 넘김)
    def avatar_media(system, text)
      ids = text.to_s.scan(Game::Text::AVATAR_PATTERN).flatten.uniq.first(MAX_MEDIA)
      Account.where(id: ids).filter_map do |account|
        next if account.avatar_file_name.blank?

        MediaAttachment.create!(account: system, file: account.avatar, description: "#{account.display_name.presence || account.username}의 프로필 사진").id
      rescue => e
        Rails.logger.warn { "Game::Poster avatar attach failed for #{account.id}: #{e.class} #{e.message}" }
        nil
      end
    end

    # 게임 판의 스레드에 이어서 올린다 (참가자 모두 멘션). kind: 지금 진행 중인 Kinds 객체 (카드용, 없으면 새로 만든다)
    def to_session(session, text, mentions: nil, kind: nil)
      thread = Status.find_by(id: session.last_status_id || session.root_status_id)
      status = post(text, mentions: mentions || session.players.map(&:account), thread: thread, visibility: session.visibility)
      return if status.nil?

      session.update!(last_status_id: status.id)
      record_card(session, status, kind)
      status
    end

    # PC 웹 카드용으로 그 순간의 상태를 남긴다 (Game::Card)
    def record_card(session, status, kind)
      GameEvent.create!(session: session, status: status, payload: Game::Card.build(session, kind))
    rescue => e
      Rails.logger.warn { "Game::Poster card failed for #{status.id}: #{e.class} #{e.message}" }
      nil
    end
  end
end
