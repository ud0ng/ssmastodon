# frozen_string_literal: true

# 대기방·진행 중 채팅: 웹 메시지(GameMessage) 중 참가자가 쓴 채팅은 kind 'chat', 쓴 사람은 author_id.
class AddChatToGameMessages < ActiveRecord::Migration[8.0]
  def change
    add_column :game_messages, :kind, :string, null: false, default: 'system', if_not_exists: true
    add_column :game_messages, :author_id, :bigint, if_not_exists: true
  end
end
