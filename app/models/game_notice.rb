# frozen_string_literal: true

# 웹에서도 보이게 하는 시스템 계정의 안내 툿 (호울러). 시스템 계정이 올린 컨텐츠 툿은 웹에서 숨기지만 이 표에 있는 툿은 그대로 보인다.
class GameNotice < ApplicationRecord
  belongs_to :status
end
