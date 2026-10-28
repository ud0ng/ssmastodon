# frozen_string_literal: true

# 컨텐츠 기능 전체 스위치. 관리 화면에는 없고 코드에서만 바꾼다 (ENABLED 를 false 로 바꿔 배포).
# 끄면 컨텐츠·이벤트·소속·재화·상점·RP(마니또)·시트 설정이 사용자 화면·관리 메뉴·주소·API·백그라운드 작업에서 모두 막힌다.
# 데이터는 지우지 않으니 다시 켜면 그대로 돌아온다. 컨텐츠 테이블이 없어도 안전하다.
module Game::Switch
  ENABLED = false

  module_function

  def on?
    ENABLED
  end

  # config/routes 에서 constraints(Game::Switch) { ... } 로 쓴다: 꺼져 있으면 그 주소는 없는 주소(404)
  def matches?(_request)
    on?
  end
end
