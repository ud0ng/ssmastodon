# frozen_string_literal: true

module Game
  # 상점 아이템 [사용] 수치: 정수(5, -20) 또는 주사위(1d10, +1d3, -(1d6+3)). 자동봇 text.amount 와 같은 규칙.
  module Dice
    class Error < StandardError; end

    INTEGER = /\A\s*([+-]?\d+)\s*\z/
    DICE = /\A\s*(-)?\(?\s*(\d+)\s*[dD]\s*(\d+)\s*(?:([+-])\s*(\d+))?\s*\)?\s*\z/
    MAX_COUNT = 100
    MAX_SIDES = 1000

    module_function

    def amount(expression, random: Random)
      text = expression.to_s.strip
      return Regexp.last_match(1).to_i if text.match(INTEGER)

      sign = 1
      if text.start_with?('+')
        text = text[1..]
      elsif text.start_with?('-') && !text.start_with?('-(')
        sign = -1
        text = text[1..]
      end
      sign * roll(text, random: random)
    end

    def roll(text, random: Random)
      match = DICE.match(text)
      raise Error, text if match.nil?

      negative, count, sides, operator, modifier = match.captures
      count = count.to_i
      sides = sides.to_i
      raise Error, text unless (1..MAX_COUNT).cover?(count) && (1..MAX_SIDES).cover?(sides)

      total = Array.new(count) { random.rand(1..sides) }.sum
      total += operator == '-' ? -modifier.to_i : modifier.to_i if modifier
      negative ? -total : total
    end
  end
end
