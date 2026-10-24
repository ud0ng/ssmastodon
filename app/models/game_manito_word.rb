# frozen_string_literal: true

# 마니또 단어: 캐릭터(account, A)가 상대(target_account, B)에게 몰래 말해야 하는 단어들 (Game::Manito).
# uses 는 B를 태그한 툿에 단어를 넣은 횟수(툿 하나에 1회), last_status_id 는 그 마지막 툿(들킴 알림을 거기에 답멘으로),
# caught_at 은 B에게 들킨 때 (그 뒤로 B에게는 보상이 없다)
class GameManitoWord < ApplicationRecord
  belongs_to :account
  belongs_to :target_account, class_name: 'Account'

  # 단어 목록 비교용: 띄어쓰기 무시, 소문자
  def self.key(word)
    word.to_s.gsub(/\s+/, '').downcase
  end

  def caught?
    caught_at.present?
  end

  # 툿 글에 들어 있는 첫 단어 (없으면 nil)
  def match(text)
    body = self.class.key(text)
    Array(words).find { |word| (needle = self.class.key(word)).present? && body.include?(needle) }
  end

  def word?(guess)
    Array(words).any? { |word| self.class.key(word) == self.class.key(guess) && self.class.key(guess).present? }
  end
end
