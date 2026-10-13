# frozen_string_literal: true

module Admin::GameHelper
  # 컨텐츠 관리 화면 문구: 소속 이름(기숙사/진영 등)을 %{term} 에 넣는다
  def game_t(key, **options)
    t(key, term: Game::Config.for('common')['house_term'], **options)
  end
end
