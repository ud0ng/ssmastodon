# frozen_string_literal: true

module Game
  # 도둑 지도가 끝난 뒤 '오늘의 MVP': 판 기록에서 활약한 장면을 골라 점수순으로.
  # 장면: 체포왕(가장 많이 붙잡은 사감) · 목표 사냥꾼(목표 장소를 가장 많이 다녀온 학생) · 구출 영웅(사감실에 뛰어들어 구한 학생)
  # · 비밀 통로 달인(비밀 통로를 두 번 넘게 쓴 학생) · 끝까지 못 잡은 학생(한 번도 안 잡힌 학생) · 또 잡혔어요?(구출 뒤 또 잡혀 탈락)
  # round 는 그 장면의 턴: 웹은 승리 화면 다음에 장면 카드와 함께 그 턴을 지도 위에서 다시 틀어 준다 (비행 대결처럼).
  module MaraudersScenes
    LIMIT = 5

    module_function

    # state: 판 상태(문자열 키), players: GamePlayer 목록, student_seats: 학생 자리 번호(문자열)
    # → [{ kind, round, seats, title, text, score }] 점수 높은 순
    def call(state, players, student_seats)
      names = players.to_h { |player| [player.seat.to_s, player.name.to_s] }
      arrests = Array(state['history']).flat_map { |entry| Array(entry['arrests']).map { |arrest| arrest.merge('turn' => entry['turn']) } }
      last_turn = state['finished_turn'] || Array(state['history']).last&.dig('turn') || 1
      scenes = []

      arrests.group_by { |arrest| arrest['by'].to_s }.each do |seat, list|
        scenes << scene('arrest_king', list.last['turn'], [seat], '체포왕', "#{names[seat]}#{ga(names[seat])} 학생을 #{list.size}번 붙잡았습니다.", 40 * list.size)
      end

      (state['goals_by'] || {}).each do |seat, count|
        scenes << scene('goal_runner', state.dig('goals_by_turn', seat), [seat], '목표 사냥꾼', "#{names[seat]}#{ga(names[seat])} 목표 장소 #{count}곳을 다녀왔습니다.", 40 * count.to_i)
      end

      (state['rescues_by'] || {}).each do |seat, count|
        scenes << scene('hero', state.dig('rescues_by_turn', seat), [seat], '구출 영웅', "#{names[seat]}#{ga(names[seat])} 사감실에 뛰어들어 #{count}명을 구해 냈습니다.", 45 * count.to_i)
      end

      (state['secret_by'] || {}).each do |seat, count|
        next if count.to_i < 2

        scenes << scene('secret_master', state.dig('secret_by_turn', seat), [seat], '비밀 통로 달인', "#{names[seat]}#{ga(names[seat])} 비밀 통로를 #{count}번이나 빠져나갔습니다.", 20 * count.to_i)
      end

      caught = arrests.map { |arrest| arrest['seat'].to_s }
      student_seats.each do |seat|
        next if caught.include?(seat)

        scenes << scene('ghost', last_turn, [seat], '끝까지 못 잡은 학생', "#{names[seat]}#{ga(names[seat])} 끝까지 한 번도 붙잡히지 않았습니다.", 30)
      end

      arrests.select { |arrest| arrest['out'] }.each do |arrest|
        seat = arrest['seat'].to_s
        scenes << scene('caught_twice', arrest['turn'], [seat, arrest['by'].to_s], '또 잡혔어요?', "#{names[seat]}#{ga(names[seat])} 구출되자마자 또 붙잡혀 탈락했습니다.", 25)
      end

      scenes.sort_by { |each| -each['score'] }.first(LIMIT)
    end

    def scene(kind, round, seats, title, text, score)
      { 'kind' => kind, 'round' => (round || 1).to_i, 'seats' => seats.map(&:to_i).sort, 'title' => title, 'text' => text, 'score' => score }
    end

    # 이/가
    def ga(name)
      Game::Text.particle(name.to_s[-1], '이가')
    end
  end
end
