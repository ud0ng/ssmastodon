# frozen_string_literal: true

# 마법 수업 성적 한 건 (자습/수업). 성적표는 과목별 가장 좋은 등급을 보여 준다.
class GameGrade < ApplicationRecord
  GRADES = %w(O E A P D T).freeze
  MODES = %w(study class).freeze

  belongs_to :account
  belongs_to :session, class_name: 'GameSession', foreign_key: :game_session_id, optional: true

  validates :grade, inclusion: { in: GRADES }
  validates :mode, inclusion: { in: MODES }

  # 등급이 좋은 순서 (O 가 가장 좋음)
  def self.rank_of(grade)
    GRADES.index(grade) || GRADES.size
  end

  def self.best(grades)
    grades.min_by { |grade| rank_of(grade) }
  end
end
