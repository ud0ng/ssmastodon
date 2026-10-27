# frozen_string_literal: true

# 웹에서도 숨기지 않고 보여 주는 시스템 계정의 안내 툿 (호울러 연회장 문구·소문 DM 등). 컨텐츠 툿은 웹 타임라인·알림·채팅에서 숨기지만, 이 표에 있는 툿은 보인다.
class CreateGameNotices < ActiveRecord::Migration[8.0]
  def change
    create_table :game_notices, if_not_exists: true do |t|
      t.bigint :status_id, null: false
      t.timestamps
      t.index :status_id, unique: true
    end
  end
end
