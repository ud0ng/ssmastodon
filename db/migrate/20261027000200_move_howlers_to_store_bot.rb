# frozen_string_literal: true

# 호울러(연회장 문구 팔로워 공개 툿, 모든 캐릭터에게 간 소문 DM)를 올리는 계정이 시스템 계정에서 상점 봇 계정(컨텐츠 설정 > 상점 계정 아이디)으로 바뀌었다.
# 예전에 시스템 계정이 올린 호울러 툿의 보낸 계정을 봇 계정으로 옮긴다: 툿, 그 멘션 알림의 보낸 사람, DM 방(시스템 방 → 봇 방), 툿 개수.
# 아이템에 지금 정해 둔 호울러 문구와 똑같이 시작하는 툿만 옮기고 (문구를 그 뒤에 바꿨으면 못 찾는다), 봇 계정이 없으면 아무것도 하지 않는다.
class MoveHowlersToStoreBot < ActiveRecord::Migration[8.0]
  def up
    system = Game::System.account
    bot = Game::Gift.bot_accounts.first
    return if system.nil? || bot.nil? || system.id == bot.id

    texts = GameShopItem.all.filter_map { |item| Game::ItemEffects.rumor_text(item.effects_list).presence }.uniq
    return if texts.empty?

    own = Status.unscoped.where(account_id: system.id, local: true, reblog_of_id: nil)
    hall = own.where(visibility: :private, text: texts)
    dms = own.where(visibility: :direct).where(texts.map { 'statuses.text = ? OR statuses.text LIKE ?' }.join(' OR '),
                                               *texts.flat_map { |text| [text, "#{Status.sanitize_sql_like(text)}\n\n%"] })
    moved = hall.to_a + dms.to_a
    return if moved.empty?

    moved_ids = moved.map(&:id)
    Status.unscoped.where(id: moved_ids).update_all(account_id: bot.id)
    Notification.where(activity_type: 'Mention', activity_id: Mention.where(status_id: moved_ids).select(:id), from_account_id: system.id).update_all(from_account_id: bot.id)
    AccountStat.where(account_id: system.id).update_all(['statuses_count = GREATEST(statuses_count - ?, 0)', moved_ids.size])
    AccountStat.where(account_id: bot.id).update_all(['statuses_count = statuses_count + ?', moved_ids.size])

    move_direct_messages(moved.select(&:direct_visibility?).map { |status| Status.unscoped.find(status.id) }, bot)
  end

  def down
    # 되돌리지 않는다 (옮긴 호울러만 따로 가려낼 수 없다)
  end

  private

  # DM 은 시스템과의 방에서 봇과의 방으로 옮긴다 (방은 참가자 조합마다 하나). 대화(Conversation)도 새 방에 붙인다
  def move_direct_messages(statuses, bot)
    old_rooms = []
    statuses.each do |status|
      next if status.conversation_id.blank?

      old_rooms.concat(DmRoom.where(id: Conversation.where(id: status.conversation_id).where.not(dm_room_id: nil).select(:dm_room_id)).to_a)
      participants = DmRoom.participants_for(status)
      next if participants.size < 2

      room = DmRoom.find_or_create_for(participants, creator: bot)
      Conversation.where(id: status.conversation_id).update_all(dm_room_id: room.id)
      room.register_status!(status, resurrect: false)
    end
    old_rooms.uniq.each(&:rewind_last_status!)
  end
end
