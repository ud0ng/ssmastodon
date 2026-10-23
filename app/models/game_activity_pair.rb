# frozen_string_literal: true

# 캐릭터×상대 캐릭터×날짜 툿 활동 한 줄 (답 툿·DM). 날짜는 한국 시간 기준.
class GameActivityPair < ApplicationRecord
  COLUMNS = %i(reply_posts reply_chars reply_media reply_turns dms dm_chars).freeze

  belongs_to :account
  belongs_to :other_account, class_name: 'Account'
end
