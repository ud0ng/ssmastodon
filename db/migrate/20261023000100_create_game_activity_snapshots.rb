# frozen_string_literal: true

# 하루(한국 시간 00시 기준)마다 캐릭터의 툿 활동을 저장한다 (Game::ActivitySnapshot).
#   game_activity_days  캐릭터×날짜: 전체·DM·퍼블·답 툿 수와 글자 수, 답 횟수, 미디어 툿 수
#   game_activity_pairs 캐릭터×상대 캐릭터×날짜: 답 툿 수·글자 수·미디어·답 횟수, DM 툿 수·글자 수
# 오늘 것은 툿을 쓸 때마다 쌓고(Game::ActivitySnapshotWorker), 하루가 끝나면 그날 것을 툿에서 다시 계산해 맞춘다. 지난 날은 일괄로 올린다 (game:activity_backfill).
class CreateGameActivitySnapshots < ActiveRecord::Migration[8.0]
  def change
    create_table :game_activity_days, if_not_exists: true do |t|
      t.date :day, null: false
      t.bigint :account_id, null: false
      t.integer :posts, null: false, default: 0
      t.bigint :post_chars, null: false, default: 0
      t.integer :dms, null: false, default: 0
      t.bigint :dm_chars, null: false, default: 0
      t.integer :public_posts, null: false, default: 0
      t.bigint :public_chars, null: false, default: 0
      t.integer :reply_posts, null: false, default: 0
      t.bigint :reply_chars, null: false, default: 0
      t.integer :reply_turns, null: false, default: 0
      t.integer :media, null: false, default: 0
      t.timestamps
      t.index [:day, :account_id], unique: true
      t.index :account_id
    end

    create_table :game_activity_pairs, if_not_exists: true do |t|
      t.date :day, null: false
      t.bigint :account_id, null: false
      t.bigint :other_account_id, null: false
      t.integer :reply_posts, null: false, default: 0
      t.bigint :reply_chars, null: false, default: 0
      t.integer :reply_media, null: false, default: 0
      t.integer :reply_turns, null: false, default: 0
      t.integer :dms, null: false, default: 0
      t.bigint :dm_chars, null: false, default: 0
      t.timestamps
      t.index [:day, :account_id, :other_account_id], unique: true, name: 'index_game_activity_pairs_on_day_and_accounts'
      t.index [:account_id, :other_account_id]
    end
  end
end
