# frozen_string_literal: true

module Game
  module Lessons
    # 마법 연습 (자습): 여러 턴에 걸쳐 집중력을 쌓아 목표치에 닿으면 성공 → 주문 레벨업 (최대 5).
    # 매 턴 [연습] → 집중력 +(15~30), 방해 이벤트 -(0~20). 최대 8턴.
    # 수호령 주문을 처음 성공하면 수호령이 정해진다.
    class Practice < Base
      KEY = 'practice'

      FIELDS = (lesson_fields(name: '마법 연습', modes: 'study') + [
        F.new(key: 'cmd_practice', type: :string, default: '연습', group: 'commands', label: '연습 명령어', hint: '뒤에 짧은 문장을 붙여도 된다'),
        F.new(key: 'spells', type: :lines, group: 'spells', label: '연습할 주문 (줄마다 하나, 첫 줄이 기본)', hint: '[자습/마법 연습/주문 이름]',
              default: ['익스펙토 패트로눔', '루모스', '아씨오', '리디큘러스']),
        F.new(key: 'patronus_spell', type: :string, default: '익스펙토 패트로눔', group: 'spells', label: '수호령 주문'),
        F.new(key: 'patronuses', type: :lines, group: 'spells', label: '수호령 (줄마다 하나)',
              default: %w(수달 수사슴 암사슴 고양이 테리어 백조 말 늑대 산토끼 독수리 여우 부엉이)),
        F.new(key: 'max_level', type: :integer, default: 5, group: 'rules', label: '최대 레벨'),
        F.new(key: 'target', type: :integer, default: 100, group: 'rules', label: '목표 집중력'),
        F.new(key: 'max_turns', type: :integer, default: 8, group: 'rules', label: '최대 턴'),
        F.new(key: 'gain_min', type: :integer, default: 15, group: 'rules', label: '연습 집중력 최소'),
        F.new(key: 'gain_max', type: :integer, default: 30, group: 'rules', label: '연습 집중력 최대'),
        F.new(key: 'loss_min', type: :integer, default: 0, group: 'rules', label: '방해 최소'),
        F.new(key: 'loss_max', type: :integer, default: 20, group: 'rules', label: '방해 최대'),
        F.new(key: 'gains', type: :lines, group: 'flavors', label: '연습 문구 (줄마다 하나)',
              default: ['✨ 은빛 연기가 피어오른다!', '✨ 지팡이 끝이 따뜻해진다.', '✨ 행복한 기억이 또렷해진다.', '✨ 주문의 리듬이 손에 익는다.']),
        F.new(key: 'distractions', type: :lines, group: 'flavors', label: '방해 문구 (줄마다 하나)',
              default: ['🖤 디멘터가 다가온다…', '🦉 부엉이가 창문을 두드린다.', '👻 피브스가 분필을 던진다!', '📚 책이 와르르 무너진다.']),
        F.new(key: 'msg_start', type: :text, group: 'messages', label: '시작',
              default: '🪄 %{spell} 연습 (지금 Lv.%{level}). 집중력 0에서 %{target}까지, 최대 %{turns}턴. [%{practice}]로 답해 주세요.'),
        F.new(key: 'msg_turn', type: :text, group: 'messages', label: '턴', default: "%{turn}턴\n%{gain} 집중력 %{before} → %{middle}\n%{distraction} 집중력 %{middle} → %{after}"),
        F.new(key: 'msg_success', type: :text, group: 'messages', label: '성공', default: '🌟 %{spell} 성공! Lv.%{level}'),
        F.new(key: 'msg_patronus', type: :text, group: 'messages', label: '수호령',
              default: "🦌 은빛 %{patronus}{이가} 지팡이 끝에서 뛰쳐나와 디멘터를 몰아냈다!\n%{player}의 수호령: %{patronus}"),
        F.new(key: 'msg_fail', type: :text, group: 'messages', label: '실패', default: '💨 %{turns}턴 안에 주문을 완성하지 못했다. (집중력 %{focus})'),
      ]).freeze

      def start!
        spells = config['spells'].presence || ['루모스']
        spell = spells.find { |name| name.delete(' ') == state['args']&.first.to_s.delete(' ') } || spells.first
        state.merge!('spell' => spell, 'focus' => 0)
        session.update!(turn: 1)
        post(render(config['msg_start'], spell: spell, level: level, target: target, turns: max_turns, practice: config['cmd_practice']))
        wait_for_turn!
      end

      def handle(player, command, _args, _status)
        return false unless command == config['cmd_practice']

        before = state['focus']
        middle = [before + roll('gain'), target].min
        loss = middle >= target ? 0 : roll('loss')
        after = [middle - loss, 0].max
        state['focus'] = after
        turn_text = render(config['msg_turn'], turn: session.turn, before: before, middle: middle, after: after,
                                               gain: config['gains'].sample.to_s, distraction: loss.zero? ? '🍃 조용하다.' : config['distractions'].sample.to_s)

        if after >= target
          succeed!(player, turn_text)
        elsif session.turn >= max_turns
          grade!(player, 'P', detail: "집중력 #{after}")
          finish_lesson!("#{turn_text}\n\n#{render(config['msg_fail'], turns: max_turns, focus: after)}")
        else
          post(turn_text)
          session.update!(turn: session.turn + 1)
          wait_for_turn!
        end
        true
      end

      def timeout!
        finish_lesson!
      end

      private

      def target
        [config['target'].to_i, 1].max
      end

      def max_turns
        config['max_turns'].to_i.clamp(1, 30)
      end

      def roll(kind)
        low = config["#{kind}_min"].to_i
        high = [config["#{kind}_max"].to_i, low].max
        rand(low..high)
      end

      def character
        players.first.character
      end

      def level
        (character.progress['spells'] || {})[state['spell']].to_i
      end

      def succeed!(player, turn_text)
        progress = character.progress.deep_dup
        progress['spells'] ||= {}
        new_level = [progress['spells'][state['spell']].to_i + 1, config['max_level'].to_i].min
        progress['spells'][state['spell']] = new_level
        lines = [turn_text, render(config['msg_success'], spell: state['spell'], level: new_level)]

        if state['spell'] == config['patronus_spell'] && progress['patronus'].blank?
          progress['patronus'] = config['patronuses'].sample.to_s
          lines << render(config['msg_patronus'], patronus: progress['patronus'], player: player)
        end
        character.update!(progress: progress)

        grade = if session.turn <= 5
                  'O'
                else
                  (session.turn <= 6 ? 'E' : 'A')
                end
        grade!(player, grade, detail: "#{session.turn}턴 · Lv.#{new_level}")
        finish_lesson!(lines.join("\n\n"))
      end
    end
  end
end
