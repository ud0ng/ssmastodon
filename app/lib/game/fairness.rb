# frozen_string_literal: true

module Game
  # 편애·차별 보기 (캐릭터 관리 > 활동 > 캐릭터 > 상대 캐릭터별).
  # 한 캐릭터(A)가 상대(B)를 대하는 방식을 A 자신의 평균과 견준다. 지수는 모두 1.0 = A의 평균대로, 1보다 크면 더 챙기고 작으면 덜 챙긴다.
  #   관심: B를 찾아간 몫 ÷ 공평한 몫(1 ÷ 상대가 될 수 있는 캐릭터 수). 한 번도 안 찾아간 캐릭터는 0
  #   정성: B에게 쓴 툿당 글자 수 ÷ A의 전체 툿당 글자 수
  #   응답: (1 - B에게의 스루율) ÷ (1 - A의 전체 스루율). B를 남보다 자주 지나치면 1보다 작다
  #   종합: 세 지수를 곱한 값 (정성·응답을 셀 수 없으면 1로 둔다). 순위는 종합이 높은 순
  # 답 툿 수는 타래에 따라 달라서 쓰지 않고 답 횟수(찾아간 횟수)와 스루를 기준으로 한다. 근거(답 횟수 + 스루)가 FEW 보다 적으면 표본이 적다.
  module Fairness
    FEW = 5

    Score = Struct.new(:interest, :care, :response, :overall, :basis, keyword_init: true) do
      def few?
        basis < FEW
      end
    end

    module_function

    # row: A → B (PairTotals), total: A → 모두의 합계, people: A의 상대가 될 수 있는 캐릭터 수
    def score(row, total, people)
      interest = people.positive? && total.reply_turns.to_i.positive? ? row.reply_turns.to_i * people / total.reply_turns.to_f : nil
      care = ratio(row.avg_chars, total.avg_chars)
      base = total.skip_rate && (100 - total.skip_rate)
      response = row.skip_rate && base.to_f.positive? ? (100 - row.skip_rate) / base : nil
      overall = interest && (interest * (care || 1.0) * (response || 1.0))
      Score.new(interest: interest&.round(2), care: care&.round(2), response: response&.round(2), overall: overall&.round(2), basis: row.reply_turns.to_i + row.skipped.to_i)
    end

    def ratio(value, average)
      value && average.to_f.positive? ? value / average.to_f : nil
    end

    # entries [[key, PairTotals, Score]] → key => 순위 (1부터: 종합 높은 순, 같으면 스루가 적은 쪽, 그다음 넣은 순서)
    def ranks(entries)
      ordered = entries.each_with_index.sort_by { |(_, row, score), index| [-(score.overall || -1), row.skipped.to_i, index] }
      ordered.each_with_index.to_h { |((key, _, _), _), rank| [key, rank + 1] }
    end
  end
end
