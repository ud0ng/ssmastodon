# frozen_string_literal: true

module Game
  # 상태 수치 수식 (캐릭터 관리 > 스탯). {{스탯이름}} 에 캐릭터의 스탯 값을 넣어 계산한다.
  #   {{힘}}*5    {{힘}}5 (숫자를 바로 붙이면 곱)    ({{힘}}+{{민첩}})/2    10+{{지능}}*2
  # 지원: 숫자, + - * /, 괄호, {{스탯}}. eval 을 쓰지 않고 직접 해석한다.
  module Formula
    class Error < StandardError; end

    TOKEN = /\{\{\s*([^{}]+?)\s*\}\}|\d+(?:\.\d+)?|[()+\-*\/]/

    module_function

    # 쓰인 스탯 이름들
    def names(formula)
      formula.to_s.scan(/\{\{\s*([^{}]+?)\s*\}\}/).flatten.uniq
    end

    # 계산 (값이 없는 스탯은 0). 정수로 반올림해서 돌려준다.
    def evaluate(formula, values = {})
      tokens = tokenize(formula, values)
      raise Error, 'empty' if tokens.empty?

      parser = Parser.new(tokens)
      result = parser.expression
      raise Error, 'unexpected' unless parser.done?

      raise Error, 'not finite' unless result.finite?

      result.round
    end

    # 문법만 확인한다 (저장할 때). 스탯 이름이 실제로 있는지는 names 로 따로.
    def valid?(formula)
      evaluate(formula, Hash.new(1))
      true
    rescue Error
      false
    end

    def tokenize(formula, values)
      source = formula.to_s.strip
      raise Error, 'empty' if source.empty?

      tokens = []
      position = 0
      while position < source.length
        if source[position].match?(/\s/)
          position += 1
          next
        end

        match = TOKEN.match(source, position)
        raise Error, "unexpected #{source[position]}" unless match&.begin(0) == position

        text = match[0]
        token = if match[1]
                  Float(values[match[1]].to_s, exception: false) || 0.0
                elsif text.match?(/\A\d/)
                  Float(text)
                else
                  text
                end
        # 값이 바로 이어지면 곱 ({{힘}}5, 2{{힘}}, 3(1+2), ){{힘}})
        tokens << '*' if implicit_multiplication?(tokens.last, token)
        tokens << token
        position = match.end(0)
      end
      tokens
    end

    def value?(token)
      token.is_a?(Float) || token == '('
    end

    def implicit_multiplication?(previous, token)
      return false if previous.nil?

      (previous.is_a?(Float) || previous == ')') && value?(token)
    end

    # 숫자/괄호/단항 부호를 지원하는 재귀 하강 해석기
    class Parser
      def initialize(tokens)
        @tokens = tokens
        @position = 0
      end

      def done?
        @position >= @tokens.size
      end

      def expression
        left = term
        while %w(+ -).include?(peek)
          operator = advance
          right = term
          left = operator == '+' ? left + right : left - right
        end
        left
      end

      private

      def term
        left = factor
        while %w(* /).include?(peek)
          operator = advance
          right = factor
          left = operator == '*' ? left * right : left / right
        end
        left
      end

      def factor
        token = advance
        case token
        when Float then token
        when '-' then -factor
        when '+' then factor
        when '('
          value = expression
          raise Error, 'missing )' unless advance == ')'

          value
        else raise Error, "unexpected #{token.inspect}"
        end
      end

      def peek
        @tokens[@position]
      end

      def advance
        token = @tokens[@position]
        @position += 1
        token
      end
    end
  end
end
