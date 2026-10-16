# frozen_string_literal: true

module Game
  # 웹에서 '운영진': 컨텐츠 설정(관리 > 시스템)을 열 수 있는 사람 (manage_settings).
  # 컨텐츠·상점 해금이 꺼져 있어도, 꺼진 컨텐츠 카드도 운영진에게는 전부 보인다.
  module Staff
    module_function

    def web?(user)
      user.present? && user.can?(:manage_settings)
    end
  end
end
