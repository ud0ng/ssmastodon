# frozen_string_literal: true

# 누적 수치 기록 한 줄 (상점 설정 > 누적 수치 기록).
#   delta 현재 변동값 / raw 누적치(상성으로 깎기 전) / net 결과값(누적치에서 상성 누적치를 상쇄한 최종값)
class GameCounterLog < ApplicationRecord
  belongs_to :account
  belongs_to :counter, class_name: 'GameCounter', foreign_key: :game_counter_id, inverse_of: :logs
end
