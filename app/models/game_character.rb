# frozen_string_literal: true

# 캐릭터 명단: 서버원 한 명당 하나 (회원 목록에서 만들고 관리 화면에서 고친다)
class GameCharacter < ApplicationRecord
  belongs_to :account
  belongs_to :house, class_name: 'GameHouse', foreign_key: :game_house_id, optional: true, inverse_of: :characters

  validates :name, length: { maximum: 50 }
  validates :note, length: { maximum: 2_000 }
  validates :grade, numericality: { only_integer: true, in: 1..7 }, allow_nil: true

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

  def display_name
    name.presence || account.display_name.presence || account.username
  end

  # 개인 값을 "체력=10" 줄로
  def stats_text
    stats.map { |key, value| "#{key}=#{value}" }.join("\n")
  end

  def stats_text=(text)
    self.stats = text.to_s.lines.filter_map do |line|
      key, value = line.split('=', 2).map(&:strip)
      [key, value.to_s] if key.present?
    end.to_h
  end
end
