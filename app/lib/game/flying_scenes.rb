# frozen_string_literal: true

module Game
  # 비행 대결이 끝난 뒤 '오늘의 MVP': 라운드 기록(history)에서 가장 바보 같았던 탈락 장면을 골라 순위를 매긴다.
  # 장면 종류: 단체 추락(같은 길에 3명 이상) · 빈 길이 있었는데(충돌했지만 아무도 안 고른 길이 있었음) · 멍때리다 추락(고르지 못함)
  # · 또 너야?(같은 두 사람이 두 번 이상 부딪힘) · 이륙 직후 추락(1라운드 탈락). 웹은 장면의 라운드를 다시 틀어 보여 준다.
  module FlyingScenes
    LIMIT = 5

    module_function

    # history: 라운드 기록(문자열 키), players: GamePlayer 목록 → [{ kind, round, lane, seats, title, text, score }] 점수 높은 순
    def call(history, players)
      names = players.to_h { |player| [player.seat.to_s, player.name.to_s] }
      scenes = []
      pairs = Hash.new { |hash, key| hash[key] = [] }

      Array(history).each do |entry|
        results = entry['results'] || {}
        choices = entry['choices'] || {}
        round = entry['round'].to_i
        crashed = entry['alive_before'].to_a.select { |seat| results[seat] == 'crash' }.group_by { |seat| choices[seat] }
        empty = (1..entry['lanes'].to_i).count { |lane| choices.values.exclude?(lane) }

        crashed.each do |lane, seats|
          list = people(seats, names)
          if seats.size >= 3
            scenes << scene('pileup', round, lane, seats, '단체 추락 사고', "#{list}#{ga(list)} 같은 길로 몰려 한꺼번에 추락했습니다!", 100 + (20 * seats.size))
          elsif empty.positive?
            scenes << scene('empty_lane', round, lane, seats, '빈 길이 있었는데!', "텅 빈 길이 #{empty}개나 있었는데 #{list}#{ga(list)} 하필 같은 길로 날다 부딪혔습니다.", 50 + (15 * empty) + (10 * seats.size))
          end
          scenes << scene('takeoff', round, lane, seats, '이륙 직후 추락', "#{list}#{ga(list)} 출발하자마자 부딪혀 떨어졌습니다.", 30 + (5 * seats.size)) if round == 1 && seats.size == 2 && empty.zero?
          pairs[seats.sort] << round if seats.size == 2
        end

        idle = entry['alive_before'].to_a.select { |seat| results[seat] == 'idle' }
        next if idle.empty?

        list = people(idle, names)
        scenes << scene('idle', round, nil, idle, '멍때리다 추락', "#{list}#{ga(list)} 고민만 하다 길을 고르지 못하고 그대로 떨어졌습니다.", 60 + (5 * idle.size))
      end

      pairs.each do |seats, rounds|
        next if rounds.size < 2

        list = people(seats, names)
        scenes << scene('rematch', rounds.last, nil, seats, '또 너야?', "#{list}#{ga(list)} #{rounds.size}번이나 같은 길에서 마주쳐 부딪혔습니다.", 70 + (10 * rounds.size))
      end

      scenes.sort_by { |each| -each['score'] }.first(LIMIT)
    end

    def scene(kind, round, lane, seats, title, text, score)
      { 'kind' => kind, 'round' => round, 'lane' => lane, 'seats' => seats.map(&:to_i).sort, 'title' => title, 'text' => text, 'score' => score }
    end

    def people(seats, names)
      seats.map { |seat| names[seat.to_s] }.join(', ')
    end

    # 이/가
    def ga(list)
      Game::Text.particle(list.to_s[-1], '이가')
    end
  end
end
