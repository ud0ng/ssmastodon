# frozen_string_literal: true

# 영어로 남은 툿 보상 내역을 한글로: "Post reward (400 characters)" → "툿 보상 (400자)", "(10 posts)" → "(10툿)"
class TranslateTootRewardReasons < ActiveRecord::Migration[8.0]
  def up
    return if Rails.env.test?

    execute <<~SQL.squish
      UPDATE game_rewards
      SET reason = regexp_replace(reason, '^Post reward \((\d+) characters?\)$', '툿 보상 (\1자)')
      WHERE reason ~ '^Post reward \(\d+ characters?\)$'
    SQL
    execute <<~SQL.squish
      UPDATE game_rewards
      SET reason = regexp_replace(reason, '^Post reward \((\d+) posts?\)$', '툿 보상 (\1툿)')
      WHERE reason ~ '^Post reward \(\d+ posts?\)$'
    SQL
  end

  def down; end
end
