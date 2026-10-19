# frozen_string_literal: true

module Admin
  # 관리 화면 효과 고치기 폼의 끝나는 때: permanent=1 이면 영구, 아니면 datetime-local 값 (한국 시각). 못 읽으면 nil
  module GameFxTime
    module_function

    def parse(params)
      return GameCounterRule::PERMANENT_YEARS.years.from_now if params[:permanent] == '1'

      ActiveSupport::TimeZone['Asia/Seoul'].parse(params[:until].to_s)
    end
  end
end
