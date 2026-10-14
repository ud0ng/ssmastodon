# frozen_string_literal: true

# 토너먼트제: 사람으로 짠 대진표. 경기마다 이긴 사람의 소속이 1승, 승수가 가장 많은 소속이 우승
# (동률이면 결승 승자의 소속). status: draft(준비) → running(진행) → finished
class GameTournament < ApplicationRecord
  SIZES = [2, 4, 8, 16, 32].freeze
  STATUSES = %w(draft running finished).freeze

  has_many :matches, -> { order(:round, :position) }, class_name: 'GameTournamentMatch', dependent: :destroy, inverse_of: :tournament
  belongs_to :winner_house, class_name: 'GameHouse', optional: true

  validates :name, presence: true, length: { maximum: 100 }
  validates :size, inclusion: { in: SIZES }
  validates :status, inclusion: { in: STATUSES }
  validates :reward, numericality: { only_integer: true, greater_than_or_equal_to: 0 }

  after_create :build_matches!

  # 웹에 보여 줄 토너먼트: 진행 중인 것, 없으면 가장 최근에 끝난 것
  def self.current
    where(status: 'running').order(id: :desc).first || where(status: 'finished').order(finished_at: :desc).first
  end

  def rounds
    Math.log2(size).to_i
  end

  def final
    matches.find { |match| match.round == rounds }
  end

  def round_matches(round)
    matches.select { |match| match.round == round }
  end

  # 결승 / 준결승 / 8강 … (컨텐츠 설정 > 공통의 라운드 이름. 툿에도 쓰여서 화면 언어와 상관없이 같다)
  def round_name(round)
    common = Game::Config.for('common')
    return common['round_final'] if round == rounds
    return common['round_semifinal'] if round == rounds - 1

    Game::Text.render(common['round_of'], count: size / (2**(round - 1)))
  end

  # 소속별 이긴 경기 수 { GameHouse => 승수 }
  def house_wins
    matches.select { |match| match.status == 'done' && match.winner }
           .filter_map { |match| GameCharacter.for(match.winner).group }
           .tally
  end

  def participants
    matches.flat_map(&:players).uniq
  end

  private

  def build_matches!
    (1..rounds).each do |round|
      (size / (2**round)).times { |position| matches.create!(round: round, position: position) }
    end
  end
end
