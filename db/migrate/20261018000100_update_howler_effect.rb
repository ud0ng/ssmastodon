# frozen_string_literal: true

# 호울러 효과 설명에 '사용하면 모든 인원에게 DM 소문' 안내를 더한다 (예전 기본 문구 그대로인 것만)
class UpdateHowlerEffect < ActiveRecord::Migration[8.0]
  OLD = '러닝 중 소문 내기 가능 (무시하면 기숙사 점수가 차감(-10)). 조율 없이 소문 낼 정도의 개그성만 허용'
  NEW = "러닝 중 소문 내기 가능 (무시하면 기숙사 점수가 차감(-10)). 조율 없이 소문 낼 정도의 개그성만 허용\n사용하면 내용 입력창이 뜨고(모바일은 시스템 계정에 DM 으로 [사용/호울러/내용]), 입력한 내용이 모든 인원에게 DM 소문으로 발송됩니다. 보낸 사람은 알 수 없습니다."

  def up
    return if Rails.env.test?

    GameShopItem.unscoped.where(name: '호울러', effect: OLD).update_all(effect: NEW)
  end

  def down; end
end
