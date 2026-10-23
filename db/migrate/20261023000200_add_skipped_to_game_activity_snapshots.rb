# frozen_string_literal: true

# 스루 수: 상대 캐릭터가 이 캐릭터만 태그해서 쓴 툿(팔로워 공개·조용한 공개)에 이 캐릭터가 답 툿을 달지 않은 수 (Game::ActivitySnapshot)
# 기존 날짜는 game:activity_backfill 로 다시 올리면 채워진다.
class AddSkippedToGameActivitySnapshots < ActiveRecord::Migration[8.0]
  def change
    add_column :game_activity_days, :skipped, :integer, null: false, default: 0
    add_column :game_activity_pairs, :skipped, :integer, null: false, default: 0
  end
end
