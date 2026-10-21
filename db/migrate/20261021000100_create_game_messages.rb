# frozen_string_literal: true

# 웹 전용 컨텐츠(미로·도둑 지도·비밀의 방)는 시작한 뒤의 진행·결과를 툿으로 올리지 않고 웹 화면에만 보여 준다.
# 그 메시지가 여기 쌓인다. account_id 가 있으면 그 사람에게만 보이는 비밀 안내(예전 시스템 DM), 없으면 판 전체 메시지(카드 포함).
class CreateGameMessages < ActiveRecord::Migration[8.0]
  def change
    create_table :game_messages, if_not_exists: true do |t|
      t.references :game_session, null: false, foreign_key: { on_delete: :cascade }
      t.references :account, null: true, foreign_key: { on_delete: :cascade }
      t.text :text, null: false, default: ''
      t.jsonb :payload, null: false, default: {}
      t.timestamps
    end
  end
end
