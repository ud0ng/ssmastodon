# frozen_string_literal: true

# 마법 수업·자습을 없앴다: 아직 열려 있는 수업·자습 판은 취소한다 (끝난 판·점수·보상은 기록으로 남긴다)
class CancelLessonSessions < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def up
    safety_assured do
      execute <<~SQL.squish
        UPDATE game_sessions SET status = 'cancelled', finished_at = NOW(), deadline_at = NULL, updated_at = NOW()
        WHERE status IN ('pending', 'active')
          AND (kind IN ('levitation', 'transfiguration', 'practice') OR state->>'mode' IN ('study', 'class'))
      SQL
    end
  end

  def down; end
end
