# frozen_string_literal: true

module Game
  # 운영진이 끝난 판의 기록을 아예 지울 때: 판(참가자·카드)과 그 판의 툿(스레드의 시스템·참가자 툿, 비밀 DM)을 모두 지운다.
  # 재화·소속 점수 기록은 판과의 연결만 끊고 그대로 남긴다 (지급한 돈·점수가 같이 사라지면 안 된다).
  # 툿은 한 번에 많이 지우면 느려서 백그라운드(Game::StatusCleanupWorker)에서 지운다.
  module SessionPurge
    class Error < StandardError; end

    # 비밀 DM 은 같은 스레드에 다른 판의 DM 도 있으니, 이 판이 이어진 동안의 시스템·본인 DM 만
    DM_MARGIN = 5.minutes

    module_function

    def call(session)
      raise Error, '진행 중인 판은 지울 수 없습니다. 먼저 중지해 주세요.' if session.open?

      ids = status_ids(session)
      session.destroy!
      Game::StatusCleanupWorker.perform_async(ids) if ids.any?
      ids.size
    end

    def status_ids(session)
      system_id = Game::System.account&.id
      account_ids = [*session.players.map(&:account_id), system_id].compact
      ids = session.events.pluck(:status_id)

      root = Status.unscoped.find_by(id: session.root_status_id)
      ids += Status.unscoped.where(conversation_id: root.conversation_id, id: root.id.., account_id: account_ids).pluck(:id) if root

      since = session.created_at - DM_MARGIN
      till = (session.finished_at || session.updated_at) + DM_MARGIN
      session.players.each do |player|
        thread = Status.unscoped.find_by(id: player.state['dm_status_id'])
        next if thread.nil?

        ids += Status.unscoped.where(conversation_id: thread.conversation_id, visibility: :direct, account_id: [player.account_id, system_id].compact, created_at: since..till).pluck(:id)
      end
      ids.compact.uniq
    end
  end
end
