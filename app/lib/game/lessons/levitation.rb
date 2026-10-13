# frozen_string_literal: true

module Game
  module Lessons
    # 일반 마법 (윙가르디움 레비오사): 무작위 시점의 "지금!" 신호 뒤 빨리 [레비오사]를 외칠수록 높은 등급.
    # 신호 전에 외치면 T. 수업에서는 모두 같은 신호를 받고 반응 시간 순으로 순위를 매긴다.
    class Levitation < Base
      KEY = 'levitation'

      FIELDS = (lesson_fields(name: '일반 마법') + [
        F.new(key: 'cmd_cast', type: :string, default: '레비오사', group: 'commands', label: '주문 명령어'),
        F.new(key: 'signal_min', type: :integer, default: 10, group: 'rules', label: '신호까지 최소 (초)'),
        F.new(key: 'signal_max', type: :integer, default: 60, group: 'rules', label: '신호까지 최대 (초)'),
        F.new(key: 'seconds_O', type: :integer, default: 3, group: 'rules', label: 'O 반응 시간 (초 이내)'),
        F.new(key: 'seconds_E', type: :integer, default: 10, group: 'rules', label: 'E 반응 시간 (초 이내)'),
        F.new(key: 'seconds_A', type: :integer, default: 30, group: 'rules', label: 'A 반응 시간 (초 이내)'),
        F.new(key: 'seconds_P', type: :integer, default: 60, group: 'rules', label: 'P 반응 시간 (초 이내, 넘으면 D)'),
        F.new(key: 'msg_focus', type: :text, group: 'messages', label: '집중',
              default: '🪶 깃털을 바라보며 집중하세요… 신호가 오면 [%{cast}]!'),
        F.new(key: 'msg_signal', type: :text, group: 'messages', label: '신호', default: '✨ 지금!'),
        F.new(key: 'msg_success', type: :text, group: 'messages', label: '성공', default: '🪶 %{player}의 깃털이 천장까지 떠올랐다!'),
        F.new(key: 'msg_early', type: :text, group: 'messages', label: '신호 전',
              default: '🪶 %{player}의 깃털이 꿈쩍도 하지 않는다… 발음은 레비-오사입니다.'),
      ]).freeze

      def start!
        state['phase'] = 'focus'
        post(render(config['msg_focus'], cast: config['cmd_cast']))
        low = config['signal_min'].to_i.clamp(1, 600)
        wait_seconds!(rand(low..config['signal_max'].to_i.clamp(low, 600)))
      end

      def handle(player, command, _args, status)
        return false unless command == config['cmd_cast']
        return true if graded?(player)

        if state['phase'] == 'signal'
          seconds = [(status.created_at - Time.iso8601(state['signal_at'])).round(1), 0.0].max
          grade!(player, grade_for(seconds), detail: "반응 #{seconds}초", sort: seconds)
          intro = render(config['msg_success'], player: player)
        else
          grade!(player, 'T', detail: '신호 전', sort: 9999)
          intro = render(config['msg_early'], player: player)
        end

        if everyone_graded?
          finish_lesson!(class? ? nil : intro)
        elsif !class?
          post(intro)
        end
        true
      end

      # 신호 → 그다음 마감
      def timeout!
        if state['phase'] == 'focus'
          state['phase'] = 'signal'
          state['signal_at'] = Time.now.utc.iso8601(3)
          post(render(config['msg_signal']))
          wait_seconds!(config['seconds_P'].to_i + 5)
        else
          finish_lesson!
        end
      end

      protected

      def fallback_grade
        'D'
      end

      private

      def grade_for(seconds)
        %w(O E A P).find { |grade| seconds <= config["seconds_#{grade}"].to_f } || 'D'
      end
    end
  end
end
