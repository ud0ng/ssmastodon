# frozen_string_literal: true

# 컨텐츠 해금(컨텐츠 설정 > 설정 > 공통룰)이 꺼져 있으면 웹 컨텐츠 API 를 막는다. 운영진(Game::Staff.web?)은 항상 쓴다.
module Api::GameGate
  extend ActiveSupport::Concern

  # 쓰는 컨트롤러에서 before_action :require_user! 다음에 before_action :require_contents_open! 을 건다
  private

  def require_contents_open!
    return if Game::Config.for('common')['contents_open'] || Game::Staff.web?(current_user)

    render json: { error: '지금은 컨텐츠가 열려 있지 않습니다.' }, status: 403
  end

  # 이벤트 해금(이벤트 설정 > 설정)이 꺼져 있으면 이벤트(여럿이 하는 컨텐츠) API 를 막는다. 운영진은 항상 쓴다.
  def require_events_open!(kind)
    return if Game::Events::Settings.unlocked? || Game::Staff.web?(current_user) || !Game::Kinds.group_games.include?(kind)

    render json: { error: '지금은 이벤트가 열려 있지 않습니다.' }, status: 403
  end
end
