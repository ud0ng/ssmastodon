# frozen_string_literal: true

module Game
  # 이벤트(비행 대결·미로·도둑 지도·비밀의 방) 알림: 툿이나 DM 없이 웹 화면의 이벤트 메뉴 알림 배지와 소리로만 알린다
  # (alert!: 모집은 모두에게, 초대는 초대받은 사람에게만). 운영진이 모집을 열 때의 팔로워 공개 모집 툿만 예외 (Recruiting#open!).
  module EventNotice
    extend Redisable

    module_function

    # 웹 화면에 '이벤트 알림이 생겼다'고 알린다: 받은 사람의 화면이 이벤트 메뉴 배지를 새로 읽고 소리를 낸다 (툿 없이)
    def alert!(account_ids)
      Array(account_ids).uniq.each { |id| redis.publish("timeline:#{id}", Oj.dump(event: :'game.alert', payload: '1')) }
    rescue Redis::BaseError => e
      Rails.logger.warn { "game.alert broadcast failed: #{e.message}" }
    end
  end
end
