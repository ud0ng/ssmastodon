# frozen_string_literal: true

# 컨텐츠 기능 스위치(Game::Switch::ENABLED)를 서버에서 꺼 두어도 컨텐츠 테스트는 켜진 상태로 돈다.
# 꺼진 상태를 보는 테스트(spec/requests/game_switch_spec.rb)는 그 안에서 다시 false 로 바꾼다.
RSpec.configure do |config|
  config.before { stub_const('Game::Switch::ENABLED', true) }
end
