# frozen_string_literal: true

module Game
  module Kinds
    # 마법약: 시스템이 낸 재료(0번부터) 중 정해진 순서(3~4개)를 먼저 맞히는 추리 (숫자야구).
    # 0번 재료는 첫 번째 자리에 놓을 수 없다.
    # 각자 DM 으로 [조합] 재료 번호 … → DM 으로 힌트(P 완벽·T 조금 노력),
    # 두 사람 다 시도하면(또는 시간이 지나면) 공개 스레드에 라운드 결과를 함께 알린다 (마법결투처럼 동시에 공개).
    # P(Perfect) = 재료와 순서가 맞음, T(Try) = 재료는 맞지만 순서가 틀림.
    # 아이템 (한 판에 사람마다 같은 개수, 설정에서 정한다):
    #   방어권  — 이번 라운드에 공개되는 내 결과 중 하나를 상대에게 가린다.
    #   재시도권 — 이번 라운드에 두 번 조합할 수 있다.
    # 먼저 맞힌 쪽 승리, 최대 라운드를 넘기면 솥 폭발(무승부).
    class Potion < Base
      KEY = 'potion'
      ITEMS = %w(shield retry).freeze
      # 버튼에 마우스를 올리면 보이는 아이템 효과
      ITEM_HINTS = {
        'shield' => '방어권: 이번 라운드에 공개되는 내 결과 중 하나를 상대에게 가립니다.',
        'retry' => '재시도권: 이번 라운드에 재료를 한 번 더 조합할 수 있습니다.',
      }.freeze

      FIELDS = (base_fields(name: '마법약', command: '마법약', points_win: 10, points_draw: 3) + [
        F.new(key: 'cmd_brew', type: :string, default: '조합', group: 'commands', label: '조합 명령어', hint: '[조합] 재료 번호 … 예: [조합] 1 5 3 또는 [조합] 153 (0번은 첫 자리 불가)'),
        F.new(key: 'cmd_shield', type: :string, default: '방어권', group: 'commands', label: '방어권 명령어', hint: '이번 라운드 공개 결과 중 하나를 가린다'),
        F.new(key: 'cmd_retry', type: :string, default: '재시도권', group: 'commands', label: '재시도권 명령어', hint: '이번 라운드에 두 번 조합할 수 있다'),
        F.new(key: 'ingredient_count', type: :integer, default: 10, group: 'rules', label: '보여 줄 재료 수 (0번부터)'),
        F.new(key: 'answer_min', type: :integer, default: 3, group: 'rules', label: '정답 재료 수 (최소)'),
        F.new(key: 'answer_max', type: :integer, default: 4, group: 'rules', label: '정답 재료 수 (최대)'),
        F.new(key: 'max_tries', type: :integer, default: 6, group: 'rules', label: '최대 라운드'),
        F.new(key: 'shield_count', type: :integer, default: 1, group: 'rules', label: '방어권 개수', hint: '한 판마다 사람마다 같은 개수를 가진다'),
        F.new(key: 'retry_count', type: :integer, default: 1, group: 'rules', label: '재시도권 개수', hint: '한 판마다 사람마다 같은 개수를 가진다'),
        F.new(key: 'potions', type: :lines, group: 'flavors', label: '마법약 이름 (줄마다 하나)',
              default: %w(폴리주스\ 마법약 펠릭스\ 펠리시스 아모르텐시아 망각의\ 마법약 부풀리기\ 용액 꿈없는\ 잠의\ 마법약 진실의\ 약 기운\ 돋우는\ 마법약)),
        F.new(key: 'ingredients', type: :lines, group: 'flavors', label: '재료 (줄마다 하나)',
              default: %w(박쥐\ 비장 용의\ 피 유니콘\ 털 레이스윙\ 파리 두꺼비\ 알 쐐기풀 베조아르 아스포델 쥐오줌풀\ 뿌리 고슴도치\ 가시 말린\ 나방 은빛\ 이슬)),
        F.new(key: 'msg_start', type: :text, group: 'messages', label: '시작',
              default: "%{game}: 「%{potion}」\n\n재료: %{ingredients}\n\n이 중 %{size}가지를 정해진 순서로 넣어야 합니다. 0번 재료는 첫 번째 자리에 놓을 수 없습니다. 각자 [%{brew}] 버튼을 눌러 DM으로 재료 번호를 보내 주세요. 두 사람이 모두 보내면 결과를 함께 알립니다. 최대 %{tries}라운드. ([P] 재료와 순서가 맞음 · [T] 재료는 맞지만 순서가 틀림)\n아이템: [%{shield}] 내 결과 중 하나를 가림 · [%{retry}] 이번 라운드에 두 번 조합"),
        F.new(key: 'msg_dm_start', type: :text, group: 'messages', label: 'DM: 시작 안내',
              default: "「%{potion}」\n재료: %{ingredients}\n\n%{size}가지를 순서대로 골라 여기로 답해 주세요. 예: [%{brew}] 1 5 3 (0번은 첫 자리 불가)"),
        F.new(key: 'msg_hint', type: :text, group: 'messages', label: 'DM: 힌트', default: "%{try}번째 시도: %{guess}\n[P ×%{strike}] [T ×%{ball}]"),
        F.new(key: 'msg_again', type: :text, group: 'messages', label: 'DM: 한 번 더 (재시도권)', default: '재시도권으로 이번 라운드에 한 번 더 조합할 수 있습니다. [%{brew}] 재료 번호'),
        F.new(key: 'msg_bad_guess', type: :text, group: 'messages', label: 'DM: 잘못된 조합',
              default: '재료 %{size}가지를 겹치지 않게 골라 주세요. 0번 재료는 첫 번째 자리에 놓을 수 없습니다. 예: [%{brew}] %{example}'),
        F.new(key: 'msg_waiting', type: :text, group: 'messages', label: 'DM: 이번 라운드 이미 시도', default: '이번 라운드는 이미 조합했습니다. 상대를 기다립니다.'),
        F.new(key: 'msg_shield_on', type: :text, group: 'messages', label: 'DM: 방어권 사용', default: '방어권을 썼습니다. 이번 라운드 공개 결과 중 하나를 가립니다.'),
        F.new(key: 'msg_retry_on', type: :text, group: 'messages', label: 'DM: 재시도권 사용', default: '재시도권을 썼습니다. 이번 라운드에 두 번 조합할 수 있습니다.'),
        F.new(key: 'msg_no_item', type: :text, group: 'messages', label: 'DM: 아이템 못 씀', default: '%{item}{은는} 남아 있지 않거나 지금은 쓸 수 없습니다. (조합하기 전에, 라운드마다 한 번)'),
        F.new(key: 'msg_turn', type: :text, group: 'messages', label: '라운드 결과', default: "%{turn}라운드\n\n%{lines}"),
        F.new(key: 'msg_line', type: :text, group: 'messages', label: '라운드 결과 한 줄 ([P ×정답 수] [T ×순서 틀림 수])', default: '%{player}: [P ×%{strike}] [T ×%{ball}]'),
        F.new(key: 'msg_shield_used', type: :text, group: 'messages', label: '결과 일부를 가렸을 때', default: '(방어권으로 결과 하나를 가렸습니다)'),
        F.new(key: 'msg_skip', type: :text, group: 'messages', label: '라운드 결과: 시도 안 함', default: '%{player}: 마법약을 젓고만 있었다…'),
        F.new(key: 'msg_solved', type: :text, group: 'messages', label: '정답', default: '%{player}의 솥에서 「%{potion}」{이가} 완성되었습니다! 정답: %{answer}'),
        F.new(key: 'msg_both_solved', type: :text, group: 'messages', label: '동시에 정답', default: '두 사람이 같은 라운드에 「%{potion}」{을를} 완성했습니다! 무승부. 정답: %{answer}'),
        F.new(key: 'msg_explode', type: :text, group: 'messages', label: '솥 폭발', default: '솥이 폭발했습니다! 아무도 맞히지 못해 무승부. 정답: %{answer}'),
      ]).freeze

      def self.continues_on_timeout?
        true
      end

      def start!
        ingredients = config['ingredients'].presence || ['재료']
        shown = ingredients.sample(config['ingredient_count'].to_i.clamp(4, ingredients.size))
        low = config['answer_min'].to_i.clamp(1, shown.size - 1)
        size = rand(low..config['answer_max'].to_i.clamp(low, shown.size - 1))
        # 0번(맨 앞) 재료는 첫 번째 자리에 놓을 수 없다
        first = shown.drop(1).sample
        answer = [first, *(shown - [first]).sample(size - 1)]
        items = ITEMS.to_h { |key| [key, config["#{key}_count"].to_i.clamp(0, 9)] }
        state.merge!(
          'potion' => (config['potions'].presence || ['마법약']).sample,
          'shown' => shown,
          'answer' => answer,
          'tries' => {}, 'guesses' => {}, 'allowed' => {}, 'shield' => {}, 'solved' => [],
          'items' => players.to_h { |player| [player.seat.to_s, items.dup] }
        )
        session.update!(turn: 1)
        names = { brew: config['cmd_brew'], shield: config['cmd_shield'], retry: config['cmd_retry'] }
        post(render(config['msg_start'], potion: state['potion'], ingredients: numbered, size: size, tries: max_tries, **names))
        # 폰에서는 이 DM 에 바로 답하면 된다
        players.each { |player| dm(player, render(config['msg_dm_start'], potion: state['potion'], ingredients: numbered, size: size, brew: config['cmd_brew'])) }
        wait_for_turn!
      end

      def handle(player, command, args, status)
        case command
        when config['cmd_brew'] then brew(player, args, status)
        when config['cmd_shield'] then use_item(player, 'shield', status)
        when config['cmd_retry'] then use_item(player, 'retry', status)
        else false
        end
      end

      # 시간이 지나면 이번 라운드를 마감 (시도 안 한 사람은 건너뜀)
      def timeout!
        end_turn!
      end

      def max_turns
        max_tries
      end

      # 조합·아이템은 DM 으로: 이번 라운드를 아직 끝내지 않은 사람에게 [조합] 버튼, 쓸 수 있는 아이템 버튼은 다음 줄
      def card_actions
        waiting = players.map(&:seat).reject { |seat| done?(seat.to_s) }
        actions = waiting.empty? ? [] : [Game::Card.action(config['cmd_brew'], seats: waiting, dm: true)]
        ITEMS.each do |key|
          seats = waiting.select { |seat| item_usable?(seat.to_s, key) }
          actions << Game::Card.action(config["cmd_#{key}"], seats: seats, dm: true, style: 'secondary', row: 2, hint: ITEM_HINTS[key]) if seats.any?
        end
        actions
      end

      # 정답은 끝난 뒤에만. 이번 라운드의 시도 결과는 두 사람이 모두 낸 뒤 공개 툿으로만 알린다 (먼저 낸 사람의 결과가 보이지 않게).
      def card_data
        finished = session.status == 'finished'
        {
          'potion' => state['potion'],
          'ingredients' => state['shown'] || [],
          'answer_size' => (state['answer'] || []).size,
          'answer' => finished ? state['answer'] : nil,
          'answer_numbers' => finished ? (state['answer'] || []).map { |name| state['shown'].index(name) } : nil,
          'tries' => state['tries'] || {},
          'max_tries' => max_tries,
          'solved' => state['solved'] || [],
          'brew' => config['cmd_brew'],
          # 사람마다 남은 아이템 (방어권·재시도권)과 처음 개수
          'items' => state['items'] || {},
          'item_max' => ITEMS.to_h { |key| [key, config["#{key}_count"].to_i.clamp(0, 9)] },
        }
      end

      private

      def answer
        state['answer']
      end

      def max_tries
        config['max_tries'].to_i.clamp(1, 20)
      end

      # 0번부터 번호를 붙여 보여 준다
      def numbered
        state['shown'].each_with_index.map { |name, index| "#{index}. #{name}" }.join(' · ')
      end

      def allowed(seat)
        state.dig('allowed', seat) || 1
      end

      # 이번 라운드에 더 조합할 게 없다: 맞혔거나 허용 횟수를 다 썼다
      def done?(seat)
        state['solved'].include?(seat) || state.dig('guesses', seat).to_a.size >= allowed(seat)
      end

      def item_usable?(seat, key)
        return false unless state.dig('items', seat, key).to_i.positive?
        return false if state.dig('guesses', seat).present? || state['solved'].include?(seat)

        key == 'shield' ? !state.dig('shield', seat) : state.dig('allowed', seat) != 2
      end

      def brew(player, args, status)
        return true unless require_dm!(player, status)

        seat = player.seat.to_s
        if done?(seat)
          dm(player, render(config['msg_waiting']))
          return true
        end

        guess = parse_guess(args, status.text)
        if guess.nil?
          dm(player, render(config['msg_bad_guess'], size: answer.size, brew: config['cmd_brew'], example: answer.size.times.map { |index| index + 1 }.join(' ')))
          return true
        end

        strike, ball = score(guess)
        (state['guesses'][seat] ||= []) << { 'strike' => strike, 'ball' => ball }
        state['tries'][seat] = state['tries'][seat].to_i + 1
        state['solved'] << seat if strike == answer.size
        session.save!
        dm(player, render(config['msg_hint'], try: state['tries'][seat], guess: guess.join(' → '), strike: strike, ball: ball))
        dm(player, render(config['msg_again'], brew: config['cmd_brew'])) unless done?(seat)
        end_turn! if players.all? { |each| done?(each.seat.to_s) }
        true
      end

      # [방어권] [재시도권]: 이번 라운드에 조합하기 전에 한 번
      def use_item(player, key, status)
        return true unless require_dm!(player, status)

        seat = player.seat.to_s
        unless item_usable?(seat, key)
          dm(player, render(config['msg_no_item'], item: config["cmd_#{key}"]))
          return true
        end

        state['items'][seat][key] -= 1
        if key == 'shield'
          state['shield'][seat] = true
        else
          state['allowed'][seat] = 2
        end
        session.save!
        dm(player, render(config["msg_#{key}_on"]))
        true
      end

      # [조합/재료/재료] 또는 [조합] 뒤의 재료들. 번호(0부터)나 재료 이름. 0번 재료는 첫 번째 자리에 못 온다.
      # 재료가 10개 이하면 번호를 붙여서 [조합] 123 처럼 보내도 한 자리씩 읽는다.
      def parse_guess(args, text)
        words = args.presence || text.to_s.split(Game::Engine::COMMAND, 2).last.to_s.gsub(/@\S+/, '').split(/[\s,→>]+/).compact_blank
        guess_from(words) || (state['shown'].size <= 10 ? guess_from(words.flat_map { |word| word.match?(/\A\d{2,}\z/) ? word.chars : [word] }) : nil)
      end

      def guess_from(words)
        picked = words.map do |word|
          index = Integer(word, exception: false)
          index ? (state['shown'][index] if index.between?(0, state['shown'].size - 1)) : state['shown'].find { |name| name.delete(' ') == word.delete(' ') }
        end
        return if picked.size != answer.size || picked.any?(&:nil?) || picked.uniq.size != picked.size
        return if picked.first == state['shown'].first

        picked
      end

      def score(guess)
        strike = guess.each_with_index.count { |name, index| answer[index] == name }
        ball = guess.count { |name| answer.include?(name) } - strike
        [strike, ball]
      end

      # 한 사람의 결과 줄들. 방어권을 썼으면 결과 숫자 하나를 ? 로 가린다.
      def result_lines(player)
        seat = player.seat.to_s
        results = state.dig('guesses', seat).to_a
        return render(config['msg_skip'], player: player) if results.empty?

        pairs = results.map { |result| [result['strike'].to_s, result['ball'].to_s] }
        pairs[rand(pairs.size)][rand(2)] = '?' if state.dig('shield', seat)
        lines = pairs.map { |strike, ball| render(config['msg_line'], player: player, strike: strike, ball: ball) }
        lines << render(config['msg_shield_used']) if state.dig('shield', seat)
        lines.join("\n")
      end

      def end_turn!
        turn_text = render(config['msg_turn'], turn: session.turn, lines: players.map { |player| result_lines(player) }.join("\n"))
        answer_text = answer.map { |name| state['shown'].index(name) }.join(' → ')
        solved = players.select { |player| state['solved'].include?(player.seat.to_s) }

        if solved.size > 1
          finish!(draw: true, message: "#{turn_text}\n\n#{render(config['msg_both_solved'], potion: state['potion'], answer: answer_text)}")
        elsif solved.size == 1
          finish!(winner: solved.first, message: "#{turn_text}\n\n#{render(config['msg_solved'], player: solved.first, potion: state['potion'], answer: answer_text)}")
        elsif session.turn >= max_tries
          finish!(draw: true, message: "#{turn_text}\n\n#{render(config['msg_explode'], answer: answer_text)}")
        else
          post(turn_text)
          state['guesses'] = {}
          state['allowed'] = {}
          state['shield'] = {}
          session.update!(turn: session.turn + 1)
          wait_for_turn!
        end
      end
    end
  end
end
