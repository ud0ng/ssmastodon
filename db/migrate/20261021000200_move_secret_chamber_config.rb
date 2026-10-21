# frozen_string_literal: true

# 비밀의 방이 서버 이벤트에서 웹 전용 컨텐츠(미로·도둑 지도와 같은 구조)로 바뀌었다.
# 예전 설정의 참가 모집 시간·최소·최대 인원은 이벤트 설정 칸(event_*)으로 옮기고, 쓰지 않게 된 '열 수 있는 사람'은 지운다.
class MoveSecretChamberConfig < ActiveRecord::Migration[8.0]
  class Config < ActiveRecord::Base
    self.table_name = 'game_configs'
  end

  MOVES = { 'join_minutes' => 'event_join_minutes', 'min_players' => 'event_min_players', 'max_players' => 'event_max_players' }.freeze

  def up
    Config.reset_column_information
    config = Config.find_by(key: 'secret_chamber')
    return if config.nil?

    data = config.data.to_h.dup
    MOVES.each { |from, to| data[to] = data.delete(from) if data.key?(from) && !data.key?(to) }
    data.delete('openers')
    config.update_columns(data: data)
  end

  def down; end
end
