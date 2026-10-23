# frozen_string_literal: true

# 캐릭터×날짜 툿 활동 한 줄 (Game::ActivitySnapshot). 날짜는 한국 시간 기준.
class GameActivityDay < ApplicationRecord
  COLUMNS = %i(posts post_chars dms dm_chars public_posts public_chars reply_posts reply_chars reply_turns media skipped).freeze

  belongs_to :account
end
