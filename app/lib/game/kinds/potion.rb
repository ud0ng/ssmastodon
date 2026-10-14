# frozen_string_literal: true

module Game
  module Kinds
    # 물약: 시스템이 낸 재료 중 정해진 순서(3~4개)를 먼저 맞히는 추리 (숫자야구).
    # 각자 DM 으로 [조합] 재료1 재료2 재료3 (번호도 됨) → DM 으로 힌트(정답·순서 틀림),
    # 두 사람 다 시도하면(또는 시간이 지나면) 공개 스레드에 턴 결과. 먼저 맞힌 쪽 승리, 최대 횟수 넘기면 솥 폭발(무승부).
    class Potion < Base
      KEY = 'potion'

      FIELDS = (base_fields(name: '물약', command: '물약', points_win: 10, points_draw: 3) + [
        F.new(key: 'cmd_brew', type: :string, default: '조합', group: 'commands', label: '조합 명령어', hint: '[조합] 재료 재료 재료 또는 [조합] 1 5 3'),
        F.new(key: 'ingredient_count', type: :integer, default: 9, group: 'rules', label: '보여 줄 재료 수'),
        F.new(key: 'answer_min', type: :integer, default: 3, group: 'rules', label: '정답 재료 수 (최소)'),
        F.new(key: 'answer_max', type: :integer, default: 4, group: 'rules', label: '정답 재료 수 (최대)'),
        F.new(key: 'max_tries', type: :integer, default: 6, group: 'rules', label: '최대 시도'),
        F.new(key: 'potions', type: :lines, group: 'flavors', label: '물약 이름 (줄마다 하나)',
              default: %w(폴리주스\ 마법약 펠릭스\ 펠리시스 아모르텐시아 망각의\ 물약 부풀리기\ 용액 꿈없는\ 잠의\ 물약 진실의\ 약 기운\ 돋우는\ 물약)),
        F.new(key: 'ingredients', type: :lines, group: 'flavors', label: '재료 (줄마다 하나)',
              default: %w(박쥐\ 비장 용의\ 피 유니콘\ 털 레이스윙\ 파리 두꺼비\ 알 쐐기풀 베조아르 아스포델 쥐오줌풀\ 뿌리 고슴도치\ 가시 말린\ 나방 은빛\ 이슬)),
        F.new(key: 'msg_start', type: :text, group: 'messages', label: '시작',
              default: "🧪 %{game}: 「%{potion}」\n\n재료: %{ingredients}\n\n이 중 %{size}가지를 정해진 순서로 넣어야 합니다. 각자 시스템 계정에게 DM으로 [%{brew}] 재료 재료 … (번호도 됨)을 보내 주세요. 최대 %{tries}번."),
        F.new(key: 'msg_dm_start', type: :text, group: 'messages', label: 'DM: 시작 안내',
              default: "🧪 「%{potion}」\n재료: %{ingredients}\n\n%{size}가지를 순서대로 골라 여기로 답해 주세요. 예: [%{brew}] 1 5 3"),
        F.new(key: 'msg_hint', type: :text, group: 'messages', label: 'DM: 힌트', default: "%{try}번째 시도: %{guess}\n정답 %{strike}개 · 순서가 틀린 재료 %{ball}개 (남은 시도 %{left}번)"),
        F.new(key: 'msg_bad_guess', type: :text, group: 'messages', label: 'DM: 잘못된 조합',
              default: '재료 %{size}가지를 겹치지 않게 골라 주세요. 예: [%{brew}] %{example}'),
        F.new(key: 'msg_waiting', type: :text, group: 'messages', label: 'DM: 이번 턴 이미 시도', default: '이번 턴은 이미 시도했습니다. 상대를 기다립니다.'),
        F.new(key: 'msg_turn', type: :text, group: 'messages', label: '턴 결과', default: "%{turn}턴\n\n%{lines}"),
        F.new(key: 'msg_line', type: :text, group: 'messages', label: '턴 결과 한 줄', default: '%{player}: 정답 %{strike} · 순서 틀림 %{ball}'),
        F.new(key: 'msg_skip', type: :text, group: 'messages', label: '턴 결과: 시도 안 함', default: '%{player}: 솥만 젓고 있었다…'),
        F.new(key: 'msg_solved', type: :text, group: 'messages', label: '정답', default: '✨ %{player}의 솥에서 「%{potion}」{이가} 완성되었습니다! 정답: %{answer}'),
        F.new(key: 'msg_both_solved', type: :text, group: 'messages', label: '동시에 정답', default: '✨ 두 사람이 같은 턴에 「%{potion}」{을를} 완성했습니다! 무승부. 정답: %{answer}'),
        F.new(key: 'msg_explode', type: :text, group: 'messages', label: '솥 폭발', default: '💥 솥이 폭발했습니다! 아무도 맞히지 못해 무승부. 정답: %{answer}'),
      ]).freeze

      def self.continues_on_timeout?
        true
      end

      def start!
        ingredients = config['ingredients'].presence || ['재료']
        shown = ingredients.sample(config['ingredient_count'].to_i.clamp(3, ingredients.size))
        low = config['answer_min'].to_i.clamp(1, shown.size)
        size = rand(low..config['answer_max'].to_i.clamp(low, shown.size))
        state.merge!(
          'potion' => (config['potions'].presence || ['물약']).sample,
          'shown' => shown,
          'answer' => shown.sample(size),
          'tries' => {}, 'guesses' => {}, 'solved' => []
        )
        session.update!(turn: 1)
        post(render(config['msg_start'], potion: state['potion'], ingredients: numbered, size: size, brew: config['cmd_brew'], tries: max_tries))
        # 폰에서는 이 DM 에 바로 답하면 된다
        players.each { |player| dm(player, render(config['msg_dm_start'], potion: state['potion'], ingredients: numbered, size: size, brew: config['cmd_brew'])) }
        wait_for_turn!
      end

      def handle(player, command, args, status)
        return false unless command == config['cmd_brew']
        return true unless require_dm!(player, status)

        seat = player.seat.to_s
        if state['guesses'].key?(seat)
          dm(player, render(config['msg_waiting']))
          return true
        end

        guess = parse_guess(args, status.text)
        if guess.nil?
          dm(player, render(config['msg_bad_guess'], size: answer.size, brew: config['cmd_brew'], example: answer.size.times.map { |index| index + 1 }.join(' ')))
          return true
        end

        strike, ball = score(guess)
        state['tries'][seat] = state['tries'][seat].to_i + 1
        state['guesses'][seat] = { 'strike' => strike, 'ball' => ball }
        state['solved'] << seat if strike == answer.size
        session.save!
        dm(player, render(config['msg_hint'], try: state['tries'][seat], guess: guess.join(' → '), strike: strike, ball: ball, left: max_tries - state['tries'][seat]))
        end_turn! if state['guesses'].size == players.size
        true
      end

      # 시간이 지나면 이번 턴을 마감 (시도 안 한 사람은 건너뜀)
      def timeout!
        end_turn!
      end

      # 정답은 끝난 뒤에만. 이번 턴 결과(맞은 자리 수·자리만 틀린 수)는 공개된 것.
      def card_data
        finished = session.status == 'finished'
        {
          'potion' => state['potion'],
          'ingredients' => state['shown'] || [],
          'answer_size' => (state['answer'] || []).size,
          'answer' => finished ? state['answer'] : nil,
          'tries' => state['tries'] || {},
          'max_tries' => max_tries,
          'guesses' => (state['guesses'] || {}).transform_values { |result| result.slice('strike', 'ball') },
          'solved' => state['solved'] || [],
          'brew' => config['cmd_brew'],
        }
      end

      private

      def answer
        state['answer']
      end

      def max_tries
        config['max_tries'].to_i.clamp(1, 20)
      end

      def numbered
        state['shown'].each_with_index.map { |name, index| "#{index + 1}. #{name}" }.join(' · ')
      end

      # [조합/재료/재료] 또는 [조합] 뒤의 재료들. 번호(1~9)나 재료 이름
      def parse_guess(args, text)
        words = args.presence || text.to_s.split(Game::Engine::COMMAND, 2).last.to_s.gsub(/@\S+/, '').split(/[\s,→>]+/).compact_blank
        picked = words.map do |word|
          index = Integer(word, exception: false)
          index ? state['shown'][index - 1] : state['shown'].find { |name| name.delete(' ') == word.delete(' ') }
        end
        return if picked.size != answer.size || picked.any?(&:nil?) || picked.uniq.size != picked.size

        picked
      end

      def score(guess)
        strike = guess.each_with_index.count { |name, index| answer[index] == name }
        ball = guess.count { |name| answer.include?(name) } - strike
        [strike, ball]
      end

      def end_turn!
        lines = players.map do |player|
          result = state['guesses'][player.seat.to_s]
          result ? render(config['msg_line'], player: player, **result.transform_keys(&:to_sym)) : render(config['msg_skip'], player: player)
        end
        turn_text = render(config['msg_turn'], turn: session.turn, lines: lines.join("\n"))
        answer_text = answer.join(' → ')
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
          session.update!(turn: session.turn + 1)
          wait_for_turn!
        end
      end
    end
  end
end
