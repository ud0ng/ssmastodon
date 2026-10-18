# frozen_string_literal: true

# 기본 스탯(힘·민첩·체력)은 처음 설치할 때 한 번만 넣는다. 예전에는 스탯이 하나도 없으면 매번 다시 넣어서, 다 지워도 계속 떠 있었다.
# 이미 캐릭터가 있는 서버는 기본 스탯을 넣은 적이 있으니 '넣었음' 표시를 남긴다 (새로 설치한 서버는 표시가 없어 처음 한 번 들어간다).
class MarkCharacterStatsSeeded < ActiveRecord::Migration[8.0]
  def up
    return if Rails.env.test?
    return unless GameCharacter.exists?

    GameConfig.find_or_create_by!(key: GameCharacterField::SEEDED_KEY) { |config| config.data = { 'seeded' => true } }
  end

  def down; end
end
