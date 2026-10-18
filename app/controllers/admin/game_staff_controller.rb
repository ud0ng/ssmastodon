# frozen_string_literal: true

module Admin
  # 서버 설정 > 운영 > 운영진 계정: 공지·스토리·시스템 같은 운영진 계정을 정한다.
  # 이 계정들은 캐릭터가 아니라서(소속·재화·인벤토리·전적 없음) 캐릭터 명단·보상·멘션 대상에서 빠지고,
  # 자동봇의 운영진 명령어를 쓸 수 있다. 값은 컨텐츠 설정(currency)의 admin_usernames 에 저장한다.
  class GameStaffController < BaseController
    def update
      authorize :settings, :update?

      names = Array(params[:usernames]).flat_map { |item| item.to_s.split(/[\s,]+/) }.map { |item| item.strip.delete_prefix('@') }.compact_blank.uniq
      Game::Config.merge!('currency', 'admin_usernames' => names)
      GameCharacter.sync! # 운영진이 된 계정의 캐릭터는 지우고, 빠진 계정은 다시 명단에 넣는다
      redirect_to admin_settings_registrations_path, notice: t('generic.changes_saved_msg')
    end
  end
end
