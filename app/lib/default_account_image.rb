# frozen_string_literal: true

# 프로필 사진·헤더를 올리지 않은 계정에 보이는 이미지 (서버 설정 > 커뮤니티 테마).
# Paperclip 의 default_url 에서 부른다 (config/application.rb). 정하지 않았으면 nil → 마스토돈 기본 이미지.
module DefaultAccountImage
  def self.url(kind)
    upload = InstancePresenter.new.public_send(:"default_#{kind}")
    upload&.file&.url
  rescue ActiveRecord::ActiveRecordError, Redis::BaseError
    nil
  end
end
