# frozen_string_literal: true

module Game
  module Lessons
    # 변신술: 과제를 받고 집중도([약][중][강])를 골라 3번 시도. 가장 좋은 결과로 등급.
    #   첫 시도 완벽 O · 2~3번째 완벽 E · 어중간만 A · 실패만 P
    # 수업에서는 모두 같은 과제를 받고 각자 시도한다 (답장은 본인에게만).
    class Transfiguration < Base
      KEY = 'transfiguration'

      LEVELS = %w(low mid high).freeze
      RESULTS = %w(perfect half fail).freeze

      FIELDS = (lesson_fields(name: '변신술') + [
        F.new(key: 'tries', type: :integer, default: 3, group: 'rules', label: '시도 횟수'),
        F.new(key: 'cmd_low', type: :string, default: '약', group: 'commands', label: '집중도 약'),
        F.new(key: 'cmd_mid', type: :string, default: '중', group: 'commands', label: '집중도 중'),
        F.new(key: 'cmd_high', type: :string, default: '강', group: 'commands', label: '집중도 강'),
        *{ 'low' => ['약', 20, 60], 'mid' => ['중', 40, 40], 'high' => ['강', 60, 10] }.flat_map { |level, (name, perfect, half)|
          [
            F.new(key: "#{level}_perfect", type: :integer, default: perfect, group: 'rules', label: "#{name} 완벽 (%)"),
            F.new(key: "#{level}_half", type: :integer, default: half, group: 'rules', label: "#{name} 어중간 (%)", hint: '나머지는 실패'),
          ]
        },
        F.new(key: 'tasks', type: :lines, group: 'flavors', label: '과제 (줄마다: 과제|어중간 결과, 어중간 결과…)',
              default: [
                '🐀 쥐를 찻잔으로|털 달린 찻잔, 꼬리가 남은 찻잔, 찍찍거리는 찻잔',
                '🦔 고슴도치를 바늘꽂이로|가시가 꿈틀대는 바늘꽂이, 코를 킁킁대는 바늘꽂이',
                '🐦 새를 물병으로|날개 달린 물병, 짹짹거리는 물병',
                '🪲 딱정벌레를 단추로|다리가 남은 단추, 기어 다니는 단추',
              ]),
        F.new(key: 'msg_task', type: :text, group: 'messages', label: '과제',
              default: "✨ 과제: %{task}\n집중도를 골라 주세요: [%{low}] [%{mid}] [%{high}] (기회 %{tries}번)"),
        F.new(key: 'msg_perfect', type: :text, group: 'messages', label: '완벽', default: '%{try}번째 — 완벽한 변신! %{target_name}{이가} 되었다.'),
        F.new(key: 'msg_half', type: :text, group: 'messages', label: '어중간', default: '%{try}번째 — 음… %{half}.'),
        F.new(key: 'msg_fail', type: :text, group: 'messages', label: '실패', default: '%{try}번째 — 아무 일도 일어나지 않았다.'),
      ]).freeze

      def start!
        task = (config['tasks'].presence || ['🐀 쥐를 찻잔으로|털 달린 찻잔']).sample
        state.merge!('task' => task, 'attempts' => {})
        post(render(config['msg_task'], task: task_name, tries: tries, **commands))
        class? ? Game::Engine.set_deadline!(session, Game::Lessons.config['class_minutes']) : wait_for_turn!
      end

      def handle(player, command, _args, status)
        level = LEVELS.find { |key| config["cmd_#{key}"] == command }
        return false if level.nil?
        return true if graded?(player)

        attempts = (state['attempts'][player.seat.to_s] ||= [])
        result = roll(level)
        attempts << result
        line = render(config["msg_#{result}"], try: attempts.size, target_name: target_name, half: half_results.sample)

        if result == 'perfect' || attempts.size >= tries
          grade!(player, grade_from(attempts), detail: line_detail(attempts))
          if everyone_graded?
            finish_lesson!(class? ? nil : line)
          elsif class?
            reply_to(player, status, line)
          end
        else
          session.save!
          class? ? reply_to(player, status, line) : post(line)
          wait_for_turn! unless class?
        end
        true
      end

      # 시간이 지나면 그때까지의 결과로 등급
      def timeout!
        players.each do |player|
          attempts = state['attempts'][player.seat.to_s]
          grade!(player, grade_from(attempts), detail: line_detail(attempts)) if attempts.present? && !graded?(player)
        end
        finish_lesson!
      end

      private

      def tries
        config['tries'].to_i.clamp(1, 10)
      end

      def commands
        LEVELS.to_h { |key| [key.to_sym, config["cmd_#{key}"]] }
      end

      def task_name
        state['task'].split('|').first.strip
      end

      # "쥐를 찻잔으로" → "찻잔"
      def target_name
        task_name.split.last.to_s.sub(/으?로\z/, '')
      end

      def half_results
        list = state['task'].split('|', 2).last.to_s.split(',').map(&:strip).compact_blank
        list.presence || ['어딘가 이상한 결과']
      end

      def roll(level)
        dice = rand(100)
        perfect = config["#{level}_perfect"].to_i
        return 'perfect' if dice < perfect
        return 'half' if dice < perfect + config["#{level}_half"].to_i

        'fail'
      end

      def grade_from(attempts)
        index = attempts.index('perfect')
        return 'O' if index&.zero?
        return 'E' if index
        return 'A' if attempts.include?('half')

        'P'
      end

      def line_detail(attempts)
        attempts.map { |result| { 'perfect' => '완벽', 'half' => '어중간', 'fail' => '실패' }[result] }.join('·')
      end
    end
  end
end
