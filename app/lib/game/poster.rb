# frozen_string_literal: true

module Game
  # 시스템 계정으로 툿을 올린다. 공개 범위는 게임을 신청한 툿을 따른다 (팔로워 공개 / DM).
  module Poster
    module_function

    # mentions: 멘션할 계정들 (알림이 가도록), thread: 답장할 툿
    # from: 시스템 계정 대신 이 계정으로 올린다 (호울러는 상점 봇 계정으로). notice: true 면 웹 타임라인에서도 숨기지 않는 안내 툿으로 표시한다 (GameNotice)
    def post(text, mentions:, thread:, visibility:, notice: false, from: nil)
      system = from || Game::System.account
      return if system.nil?

      prefix = mentions.uniq.reject { |account| account.id == system.id }.map { |account| "@#{account.acct}" }.join(' ')
      media_ids = avatar_media(system, text)
      status = PostStatusService.new.call(
        system,
        text: [prefix.presence, text.gsub(Game::Text::AVATAR_PATTERN, '').strip].compact.join("\n"),
        thread: thread,
        visibility: visibility,
        media_ids: media_ids.presence,
        with_rate_limit: false
      )
      GameNotice.find_or_create_by!(status_id: status.id) if notice && status
      redistribute_after_commit(status)
      status
    end

    # 컨텐츠는 판을 잠근 트랜잭션 안에서 툿을 올린다. 그러면 PostStatusService 가 넣은 DistributionWorker 가
    # 커밋 전에 돌아 툿을 못 찾고 조용히 끝나서 멘션 알림·홈 타임라인이 빠진다.
    # 커밋된 뒤 한 번 더 넣는다 (알림·피드는 중복을 막으니 두 번 돌아도 괜찮다).
    def redistribute_after_commit(status)
      return if status.nil? || !ActiveRecord::Base.connection.transaction_open?

      ActiveRecord.after_all_transactions_commit { DistributionWorker.perform_async(status.id) }
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
      status = post(text, mentions: mentions || default_mentions(session), thread: thread, visibility: session.visibility)
      return if status.nil?

      session.update!(last_status_id: status.id)
      record_card(session, status, kind)
      status
    end

    # 보통은 참가자 모두. 운영진이 연 모집(아직 아무 툿도 없는 이벤트)은 아무도 태그하지 않는다 (모집 알림은 웹 이벤트 메뉴 배지·소리로 간다).
    def default_mentions(session)
      return session.players.map(&:account) unless session.root_status_id.nil? && session.status == 'pending' && session.state['mode'] == 'event'

      []
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
