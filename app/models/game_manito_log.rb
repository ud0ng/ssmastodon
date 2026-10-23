# frozen_string_literal: true

# 마니또 기록 (Game::Manito)
#   use      A(account)가 B(other_account)를 태그한 툿에 단어를 넣음. rewarded 면 money·items·points 를 받았고, B에게 들키면 stolen_at
#   correct  B(account)가 A(other_account)의 단어를 맞힘. money·items·points 는 A에게서 빼앗아 받은 것
#   wrong    B(account)가 틀림. money 는 낸 벌금(음수)
class GameManitoLog < ApplicationRecord
  KINDS = %w(use correct wrong).freeze

  belongs_to :account
  belongs_to :other_account, class_name: 'Account'

  validates :kind, inclusion: { in: KINDS }

  scope :uses, -> { where(kind: 'use') }
  scope :guesses, -> { where(kind: %w(correct wrong)) }
  scope :today, -> { where(created_at: Time.now.in_time_zone(Game::Manito::ZONE).beginning_of_day..) }
end
