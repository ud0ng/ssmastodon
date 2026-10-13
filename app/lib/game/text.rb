# frozen_string_literal: true

module Game
  # 설정 문구 채우기: %{이름} 자리표시 + 앞 글자 받침에 맞는 조사 {이가} {을를} {은는} {과와} {으로로} {아야}
  module Text
    PARTICLES = {
      '이가' => %w(이 가), '을를' => %w(을 를), '은는' => %w(은 는),
      '과와' => %w(과 와), '아야' => %w(아 야), '으로로' => %w(으로 로),
    }.freeze

    HANGUL = (0xAC00..0xD7A3)
    CLOSERS = /[\s」』)\]}>'"”’》〉]+\z/

    module_function

    def render(template, **values)
      text = template.to_s.gsub(/%\{(\w+)\}/) { values.fetch(Regexp.last_match(1).to_sym, '').to_s }
      text.gsub(/\{(#{PARTICLES.keys.join('|')})\}/) do
        # 닫는 괄호·따옴표 뒤면 그 안의 마지막 글자를 본다: 「진실의 약」{이가} → 「진실의 약」이
        match = Regexp.last_match
        before = match.pre_match.sub(CLOSERS, '')[-1].to_s
        particle(before, match[1])
      end
    end

    def particle(before, key)
      with_final, without_final = PARTICLES.fetch(key)
      code = before.ord if before.present?
      return "#{with_final}(#{without_final})" unless code && HANGUL.cover?(code)

      final = (code - HANGUL.first) % 28
      # '으로/로': ㄹ 받침은 '로'
      return without_final if key == '으로로' && final == 8

      final.zero? ? without_final : with_final
    end
  end
end
