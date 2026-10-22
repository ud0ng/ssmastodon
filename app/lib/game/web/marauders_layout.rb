# frozen_string_literal: true

module Game
  module Web
    # 도둑 지도의 호그와트 지도 만들기. 방·복도·움직이는 계단·탑·비밀 통로를 인원에 맞춰 만든다.
    #
    #   방은 (x, y) 칸에 놓인다. y 는 아래에서 위로 (0 = 지하, 1 = 1층 …), 탑은 성 위로 솟은 열이다.
    #   복도: 같은 층에서 옆 방끼리 (일부는 막혀 있다)   계단: 위아래 방끼리, 일부는 움직이는 계단 (A 상태 ↔ B 상태로 번갈아 열린다)
    #   인원이 많을수록 층·열·탑이 늘어난다 (TIERS).
    module MaraudersLayout
      # 전체 인원 → 학생 팀 인원 (전체의 약 1/3, 표 그대로)
      STUDENTS = { 3 => 1, 4 => 1, 5 => 1, 6 => 2, 7 => 2, 8 => 3, 9 => 3, 10 => 3, 11 => 4, 12 => 4, 13 => 4, 14 => 5, 15 => 5,
                   16 => 6, 17 => 6, 18 => 6, 19 => 7, 20 => 7, 21 => 7, 22 => 7, 23 => 8, 24 => 8 }.freeze

      # 인원 구간별 지도: 방 수 / 열 × 층 / 팀 목표 장소 / 최대 턴
      TIERS = [
        { up_to: 5, rooms: 25, cols: 5, floors: 4, targets: 3, turns: 20, towers: [3, 2] },
        { up_to: 10, rooms: 35, cols: 6, floors: 5, targets: 4, turns: 20, towers: [3, 2] },
        { up_to: 15, rooms: 45, cols: 7, floors: 5, targets: 6, turns: 24, towers: [4, 3, 3] },
        { up_to: 20, rooms: 55, cols: 8, floors: 6, targets: 8, turns: 24, towers: [4, 3] },
        { up_to: 24, rooms: 60, cols: 8, floors: 6, targets: 9, turns: 26, towers: [4, 4, 4] },
      ].freeze

      OFFICE = '사감실'
      TOWER_NAMES = %w(천문탑 북쪽탑 남쪽탑 시계탑).freeze

      # 팀이 들러야 하는 목표 장소 후보 (이름이 있는 특별한 방)
      GOALS = ['금서 구역', '부엌', '필요의 방', '천문탑 꼭대기', '대연회장', '도서관', '마법약 교실', '비밀의 방 입구', '그리핀도르 휴게실', '슬리데린 휴게실',
               '래번클로 휴게실', '후플푸프 휴게실', '해그리드 오두막', '온실', '점술 교실', '트로피실'].freeze

      # 나머지 방 이름
      PLACES = ['현관 홀', '대계단', '안뜰', '지하 통로', '지하 감옥', '의무실', '변신술 교실', '방어술 교실', '약초학 교실', '천문학 교실', '주문 교실', '마법 생물 교실',
                '고대 룬 교실', '올빼미장', '교무실', '맥고나걸 교수실', '덤블도어 교수실', '스네이프 교수실', '시계탑 복도', '종탑', '석상 복도', '초상화 갤러리',
                '뚱뚱한 아줌마 초상화 앞', '우는 소녀의 화장실', '지하 저장고', '연회 준비실', '마법사 체스 방', '움직이는 계단 홀', '유령 복도', '갑옷 복도',
                '퀴디치 탈의실', '정문', '금지된 숲 입구', '호수 선착장', '마법약 재료실', '박물관 복도', '고서 보관실', '빗자루 창고', '기숙사 복도', '그림 속 방',
                '마법 사진 복도', '천문대 계단', '서쪽 회랑', '동쪽 회랑', '북쪽 회랑', '남쪽 회랑', '지하 계단참', '지하 연회장 뒷문', '다락방', '창고', '유리 온실',
                '정원 사잇길', '호박밭 길목', '분수대 광장', '석조 다리', '돌 아치 길', '비밀 서재', '거울의 방', '난로 앞 응접실', '조용한 교실'].freeze

      module_function

      def student_count(total)
        STUDENTS.fetch(total.to_i.clamp(3, 24))
      end

      def tier(total)
        TIERS.find { |entry| total.to_i <= entry[:up_to] } || TIERS.last
      end

      # 지도를 만들어 돌려준다: { rooms:, corridors:, stairs: { 'a' => [...], 'b' => [...] }, office:, tower_cols:, cols:, floors: }
      # 두 계단 상태(A·B) 모두에서 모든 방이 이어지도록 될 때까지 다시 만든다
      def build(total, random: Random.new)
        spec = tier(total)
        100.times do
          layout = attempt(spec, random)
          return layout if layout && connected?(layout, 'a') && connected?(layout, 'b')
        end
        attempt(spec, random, blocked: false) # 막힌 길 없이 (그래도 이어지게)
      end

      def attempt(spec, random, blocked: true)
        cols = spec[:cols]
        floors = spec[:floors]
        rooms = []
        index = {}
        floors.times { |y| cols.times { |x| index[[x, y]] = rooms.size; rooms << { 'id' => rooms.size, 'x' => x, 'y' => y, 'kind' => 'room' } } }

        # 탑: 성 가장자리와 가운데 열 위로 솟아 있다 (방 수가 모자라거나 남지 않게 spec[:towers] 높이대로)
        tower_cols = tower_columns(cols, spec[:towers].size)
        spec[:towers].each_with_index do |height, order|
          x = tower_cols[order]
          height.times do |step|
            y = floors + step
            index[[x, y]] = rooms.size
            rooms << { 'id' => rooms.size, 'x' => x, 'y' => y, 'kind' => 'tower', 'tower' => order }
          end
        end

        horizontal = rooms.flat_map { |room| index[[room['x'] + 1, room['y']]] && room['y'] < floors ? [[room['id'], index[[room['x'] + 1, room['y']]]]] : [] }
        vertical = rooms.flat_map { |room| index[[room['x'], room['y'] + 1]] ? [[room['id'], index[[room['x'], room['y'] + 1]]]] : [] }

        shut = blocked ? horizontal.sample((horizontal.size * 0.08).round, random: random) : []
        corridors = horizontal - shut

        # 움직이는 계단: 성 안(층 사이)의 세로 연결 중 일부. A 상태·B 상태에서 번갈아 열린다 (탑 계단은 늘 열려 있다)
        inner = vertical.select { |a, b| rooms[b]['y'] < floors && rooms[a]['kind'] == 'room' }
        moving = inner.sample([spec[:rooms] / 10, 2].max * 2, random: random)
        half = moving.size / 2
        stairs = { 'a' => moving.first(half), 'b' => moving.drop(half) }
        fixed_vertical = vertical - moving

        office = index[[cols / 2, 1]]
        names!(rooms, office, random)
        { 'rooms' => rooms, 'corridors' => corridors, 'fixed_stairs' => fixed_vertical, 'stairs' => stairs, 'office' => office,
          'cols' => cols, 'floors' => floors, 'tower_cols' => tower_cols }
      end

      def tower_columns(cols, count)
        [0, cols - 1, cols / 2, [cols / 2 + 2, cols - 2].min].first(count)
      end

      # 방 이름: 목표 후보는 이름 있는 방으로, 탑 꼭대기와 탑 방은 탑 이름, 나머지는 장소 목록에서 섞어서
      def names!(rooms, office, random)
        goals = GOALS.dup
        places = PLACES.shuffle(random: random)
        towers = rooms.select { |room| room['kind'] == 'tower' }.group_by { |room| room['tower'] }
        rooms[office]['name'] = OFFICE
        rooms[office]['kind'] = 'office'
        towers.each do |order, list|
          list.sort_by { |room| room['y'] }.each_with_index do |room, step|
            top = step == list.size - 1
            room['name'] = top && order.zero? ? '천문탑 꼭대기' : "#{TOWER_NAMES[order]} #{top ? '꼭대기' : "#{step + 1}층"}"
            goals.delete('천문탑 꼭대기') if top && order.zero?
          end
        end
        rest = rooms.reject { |room| room['name'] }
        goal_rooms = rest.sample([goals.size, rest.size / 2].min, random: random)
        goal_rooms.zip(goals.shuffle(random: random)).each { |room, name| room['name'] = name }
        rooms.reject { |room| room['name'] }.each { |room| room['name'] = places.shift || "복도 #{room['id']}" }
      end

      # 지금 계단 상태('a' / 'b')의 모든 연결 (복도 + 늘 열린 계단 + 그 상태에서 열린 움직이는 계단)
      def edges(layout, phase)
        layout['corridors'] + layout['fixed_stairs'] + layout['stairs'].fetch(phase)
      end

      def connected?(layout, phase)
        links = edges(layout, phase)
        seen = [0]
        queue = [0]
        until queue.empty?
          room = queue.shift
          links.each do |a, b|
            other = (a == room && b) || (b == room && a)
            next if !other || seen.include?(other)

            seen << other
            queue << other
          end
        end
        seen.size == layout['rooms'].size
      end

      def neighbors(links, room)
        links.filter_map { |a, b| (a == room && b) || (b == room && a) || nil }.uniq
      end

      # 방 사이 최단 칸 수 (links 기준), 없으면 무한
      def distance(links, from, to)
        dist = { from => 0 }
        queue = [from]
        until queue.empty?
          room = queue.shift
          return dist[room] if room == to

          neighbors(links, room).each do |other|
            next if dist.key?(other)

            dist[other] = dist[room] + 1
            queue << other
          end
        end
        Float::INFINITY
      end

      # 이 방에서 steps 칸 안(자기 포함)에 있는 방들
      def within(links, from, steps)
        dist = { from => 0 }
        queue = [from]
        until queue.empty?
          room = queue.shift
          next if dist[room] >= steps

          neighbors(links, room).each do |other|
            next if dist.key?(other)

            dist[other] = dist[room] + 1
            queue << other
          end
        end
        dist.keys
      end

      # 구역 이름·범위: 탑 방은 그 탑, 성 안은 층
      def zone(layout, room_id)
        room = layout['rooms'][room_id]
        if room['kind'] == 'tower'
          { 'kind' => 'tower', 'x' => layout['tower_cols'][room['tower']], 'name' => TOWER_NAMES[room['tower']] }
        else
          { 'kind' => 'floor', 'y' => room['y'], 'name' => room['y'].zero? ? '지하' : "#{room['y']}층" }
        end
      end

      # 멀리 떨어진 두 방을 잇는 비밀 통로 후보 중 count 개를 연다 (복도로 이어진 거리 5칸 이상)
      def secret_passages(layout, count, random: Random.new)
        links = edges(layout, 'a')
        rooms = layout['rooms'].size
        candidates = (0...rooms).to_a.combination(2).select { |a, b| layout['rooms'][a]['kind'] != 'office' && layout['rooms'][b]['kind'] != 'office' && distance(links, a, b) >= 5 }
        candidates.sample(count, random: random)
      end
    end
  end
end
