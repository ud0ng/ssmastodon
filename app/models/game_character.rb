# frozen_string_literal: true

# 캐릭터 명단: 서버원 한 명당 하나 (회원 목록에서 만들고 관리 화면에서 고친다)
class GameCharacter < ApplicationRecord
  belongs_to :account
  belongs_to :house, class_name: 'GameHouse', foreign_key: :game_house_id, optional: true, inverse_of: :characters
  belongs_to :faction, class_name: 'GameHouse', foreign_key: :game_faction_id, optional: true, inverse_of: :faction_characters

  validates :name, length: { maximum: 50 }
  validates :note, length: { maximum: 2_000 }
  validates :grade, numericality: { only_integer: true, in: 1..7 }, allow_nil: true
  validates :money, numericality: { only_integer: true }

  # 게임에 낄 수 있는 서버원 (시스템 계정·정지된 계정 제외)
  def self.eligible_accounts
    Account.local.without_instance_actor.without_suspended.joins(:user).merge(User.approved.confirmed)
           .where.not(id: Game::System.account&.id)
  end

  def self.for(account)
    find_or_create_by!(account: account)
  rescue ActiveRecord::RecordNotUnique
    find_by!(account: account)
  end

  # 회원 목록에서 아직 없는 사람을 추가한다
  def self.sync!
    existing = pluck(:account_id)
    eligible_accounts.where.not(id: existing).find_each { |account| create!(account: account) }
  end

  # 점수를 모으는 소속 (공통 설정의 점수 단위에 따라 기숙사 또는 진영)
  def group
    GameHouse.faction_mode? ? faction : house
  end

  def group_id
    GameHouse.faction_mode? ? game_faction_id : game_house_id
  end

  def display_name
    name.presence || account.display_name.presence || account.username
  end

  # 개인 값을 "체력=10" 줄로
  def stats_text
    stats.map { |key, value| "#{key}=#{value}" }.join("\n")
  end

  def stats_text=(text)
    self.stats = self.class.parse_pairs(text)
  end

  # 항목 설정의 전투 스탯 말고 더 적은 값만 (편집 화면의 '추가 값')
  def extra_stats_text(field_names)
    stats.except(*field_names).map { |key, value| "#{key}=#{value}" }.join("\n")
  end

  def self.parse_pairs(text)
    text.to_s.lines.filter_map do |line|
      key, value = line.split('=', 2).map(&:strip)
      [key, value.to_s] if key.present?
    end.to_h
  end

  # 정보 항목 값 (항목 설정의 select/text/number, 항목 id 로 저장)
  def profile_value(field)
    profile[field.id.to_s]
  end

  # 인벤토리: [{ name, count, note }] ↔ "이름|개수|메모" 줄
  def inventory_text
    Array(inventory).map { |item| [item['name'], item['count'], item['note'].presence].compact.join('|') }.join("\n")
  end

  def inventory_text=(text)
    self.inventory = text.to_s.lines.filter_map do |line|
      name, count, note = line.split('|', 3).map(&:strip)
      next if name.blank?

      { 'name' => name, 'count' => [count.to_i, 1].max, 'note' => note.to_s }
    end
  end

  # 받은 아이템을 더한다 (이름이 같으면 개수만)
  def add_items(items)
    list = Array(inventory).map(&:dup)
    items.each do |item|
      existing = list.find { |entry| entry['name'] == item['name'] }
      if existing
        existing['count'] = existing['count'].to_i + item['count'].to_i
      else
        list << { 'name' => item['name'], 'count' => item['count'].to_i, 'note' => '' }
      end
    end
    self.inventory = list
  end

  def item_count
    Array(inventory).sum { |item| item['count'].to_i }
  end
end
