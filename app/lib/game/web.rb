# frozen_string_literal: true

module Game
  # 웹 전용 컨텐츠 (트라이위저드 미로, 도둑 지도). 진행은 웹 컨텐츠 화면에서 한다.
  module Web
    module_function

    # 웹 컨텐츠 화면 주소 (툿에 붙인다)
    def session_url(session)
      protocol = Rails.configuration.x.use_https ? 'https' : 'http'
      "#{protocol}://#{Rails.configuration.x.web_domain}/system/sessions/#{session.id}"
    end
  end
end
