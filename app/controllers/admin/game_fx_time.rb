# frozen_string_literal: true

module Admin
  # 관리 화면 효과 고치기 폼의 끝나는 때: permanent=1 이면 영구, 아니면 datetime-local 값 (UTC — 화면 스크립트가 브라우저 시각 ↔ UTC 로 바꿔 보낸다). 못 읽으면 nil
  module GameFxTime
    module_function

    # 효과 붙이기 폼: 효과 + 지속시간(숫자 + 단위 minute/hour/day, 단위 forever 면 영구) → 효과 한 개
    def entry(effect, params)
      permanent = params[:unit] == 'forever'
      Game::Fx.entry(effect, Game::ItemEffects.minutes(params[:minutes], params[:unit]), permanent: permanent)
    end

    def parse(params)
      return GameCounterRule::PERMANENT_YEARS.years.from_now if params[:permanent] == '1'

      ActiveSupport::TimeZone['UTC'].parse(params[:until].to_s)
    end
  end
end
