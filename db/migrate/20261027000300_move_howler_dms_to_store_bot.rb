# frozen_string_literal: true

# 20261027000200 에서 빠진 호울러 소문 DM 을 상점 봇 계정으로 옮긴다.
# 시스템이 올린 DM 은 맨 앞에 받는 사람 태그가 붙어("@ron\\n연회장 문구\\n\\n소문 내용") 문구로 시작하는 글만 찾던 앞 마이그레이션이 DM 을 하나도 못 찾았다.
# 맨 앞 태그 줄을 빼고 아이템에 지금 정해 둔 호울러 문구로 시작하는 시스템 계정의 DM 을 봇 계정으로 옮긴다: 툿, 멘션 알림의 보낸 사람, DM 방(시스템 방 → 봇 방), 툿 개수.
# 봇 계정이 없으면 아무것도 하지 않는다.
class MoveHowlerDmsToStoreBot < ActiveRecord::Migration[8.0]
  TAG_LINE = /\A(?:@\S+[ ]*)+\n/

  def up
    system = Game::System.account
    bot = Game::Gift.bot_accounts.first
    return if system.nil? || bot.nil? || system.id == bot.id

    texts = GameShopItem.all.filter_map { |item| Game::ItemEffects.rumor_text(item.effects_list).presence }.uniq
    return if texts.empty?

    candidates = Status.unscoped.where(account_id: system.id, local: true, visibility: :direct, reblog_of_id: nil)
                       .where(texts.map { 'statuses.text LIKE ?' }.join(' OR '), *texts.map { |text| "%#{Status.sanitize_sql_like(text)}%" })
    moved = candidates.select { |status| howler_dm?(status.text, texts) }
    return if moved.empty?

    moved_ids = moved.map(&:id)
    Status.unscoped.where(id: moved_ids).update_all(account_id: bot.id)
    Notification.where(activity_type: 'Mention', activity_id: Mention.where(status_id: moved_ids).select(:id), from_account_id: system.id).update_all(from_account_id: bot.id)
    AccountStat.where(account_id: system.id).update_all(['statuses_count = GREATEST(statuses_count - ?, 0)', moved_ids.size])
    AccountStat.where(account_id: bot.id).update_all(['statuses_count = statuses_count + ?', moved_ids.size])

    move_direct_messages(moved_ids.map { |id| Status.unscoped.find(id) }, bot)
  end

  def down
    # 되돌리지 않는다 (옮긴 호울러만 따로 가려낼 수 없다)
  end

  private

  # 맨 앞 태그 줄을 빼면 호울러 문구로 시작하고, 문구 바로 뒤가 글 끝이거나 빈 줄(소문 내용이 이어짐)인 글
  def howler_dm?(text, texts)
    body = text.to_s.sub(TAG_LINE, '')
    texts.any? { |howler| body == howler || body.start_with?("#{howler}\n\n") }
  end

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
