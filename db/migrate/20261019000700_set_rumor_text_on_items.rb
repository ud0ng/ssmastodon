# frozen_string_literal: true

# 소문내기(호울러): 사용할 때 쓰던 소문 내용을 아이템 효과의 문구로 옮긴다.
# 사용하면 시스템 계정이 그 문구를 팔로워 공개 툿으로 알린다. 문구가 없던 소문내기 효과에 기본 문구를 넣고, 호울러의 예전 설명도 바꾼다.
class SetRumorTextOnItems < ActiveRecord::Migration[8.0]
  class Item < ActiveRecord::Base
    self.table_name = 'game_shop_items'
  end

  DEFAULT_TEXT = '연회장 내에 호울러가 울려퍼집니다!'
  OLD = "러닝 중 소문 내기 가능 (무시하면 기숙사 점수가 차감(-10)). 조율 없이 소문 낼 정도의 개그성만 허용\n사용하면 내용 입력창이 뜨고(모바일은 시스템 계정에 DM 으로 [사용/호울러/내용]), 입력한 내용이 모든 인원에게 DM 소문으로 발송됩니다. 보낸 사람은 알 수 없습니다."
  NEW = "러닝 중 소문 내기 가능 (무시하면 기숙사 점수가 차감(-10)). 조율 없이 소문 낼 정도의 개그성만 허용\n사용하면 연회장 내에 호울러가 울려퍼지고, 시스템 계정이 정해진 문구를 팔로워 공개 툿으로 알립니다. 보낸 사람은 알 수 없습니다."

  def up
    Item.reset_column_information
    Item.find_each do |item|
      effects = Array(item.item_effects)
      changed = false
      effects = effects.map do |effect|
        next effect unless effect['type'] == 'special' && effect['kind'] == 'rumor' && effect['text'].blank?

        changed = true
        effect.merge('text' => DEFAULT_TEXT)
      end
      item.update_columns(item_effects: effects) if changed
    end
    Item.where(name: '호울러', effect: OLD).update_all(effect: NEW)
  end

  def down; end
end
