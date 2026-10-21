# frozen_string_literal: true

# 비행 대결 이벤트 최대 인원을 20명으로 (예전에 저장된 10명 이하 값만 올린다).
class RaiseFlyingEventMaxPlayers < ActiveRecord::Migration[8.0]
  def up
    return if Rails.env.test? # 시험 DB 에는 넣지 않는다

    stored = Game::Config.for('flying')['event_max_players'].to_i
    Game::Config.merge!('flying', 'event_max_players' => '20') if stored.positive? && stored < 20
  end

  def down; end
end
