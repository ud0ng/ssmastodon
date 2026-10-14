# frozen_string_literal: true

# 게임 설정 (관리 > 게임 설정). key: common / 게임 종류, data: 기본값과 다른 값만
class GameConfig < ApplicationRecord
  validates :key, presence: true, uniqueness: true
end
