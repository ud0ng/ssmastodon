# frozen_string_literal: true

# 마니또: 그 상대에게 단어를 쓴 마지막 툿 (들킴 알림을 그 툿에 답멘으로 달 때 기록을 다시 찾지 않게)
class AddLastStatusIdToGameManitoWords < ActiveRecord::Migration[8.0]
  def change
    add_column :game_manito_words, :last_status_id, :bigint
  end
end
