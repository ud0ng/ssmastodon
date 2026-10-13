# frozen_string_literal: true

module Game
  module Lessons
    # 마법 수업 과목의 공통 부분. state['mode'] = study(자습, 혼자) / class(수업, 여럿).
    # 하위 클래스는 start!(참가자 확정 뒤) / handle / timeout! 에서 grade! 로 등급을 주고 finish_lesson! 으로 끝낸다.
    class Base < Game::Kinds::Base
      MODES = [%w(both 자습·수업), %w(study 자습만), %w(class 수업만)].freeze

      def self.lesson_fields(name:, modes: 'both', min_players: 1)
        [
          F.new(key: 'enabled', type: :boolean, default: true, group: 'basic', label: '해금', hint: '끄면 이 과목을 열 수 없습니다'),
          F.new(key: 'name', type: :string, default: name, group: 'basic', label: '과목 이름', hint: '[자습/과목 이름] [수업/과목 이름]'),
          F.new(key: 'modes', type: :select, default: modes, choices: MODES, group: 'basic', label: '열 수 있는 방식'),
          F.new(key: 'min_players', type: :integer, default: min_players, group: 'basic', label: '수업 최소 인원'),
        ]
      end

      class << self
        def lesson?
          true
        end

        def allows?(mode)
          [mode, 'both'].include?(config['modes'])
        end
      end

      # 수업 참가 모집이 끝났을 때 (Game::TimeoutWorker)
      def recruitment_over!
        lessons = Game::Lessons.config
        min = [config['min_players'].to_i, 1].max
        if players.size < min
          session.update!(status: 'cancelled', finished_at: Time.now.utc, deadline_at: nil)
          post(render(lessons['msg_class_cancel'], subject: subject, min: min))
          return
        end

        session.update!(status: 'active', deadline_at: nil)
        post(render(lessons['msg_class_start'], subject: subject, names: players.map(&:name).join(', ')))
        start!
      end

      # 수업 중 [기권] = 나가기 (가장 낮은 등급)
      def forfeit!(player)
        grade!(player, fallback_grade) unless graded?(player)
        finish_lesson! if everyone_graded?
      end

      protected

      def subject
        self.class.display_name
      end

      def mode
        state['mode']
      end

      def class?
        mode == 'class'
      end

      def grades
        state['grades'] ||= {}
      end

      # 등급 매기기. sort: 같은 등급끼리 순위 (작을수록 위, 예: 반응 시간)
      def grade!(player, grade, detail: nil, sort: nil)
        grades[player.seat.to_s] = { 'grade' => grade, 'detail' => detail, 'sort' => sort }
        session.save!
      end

      def graded?(player)
        grades.key?(player.seat.to_s)
      end

      def everyone_graded?
        players.all? { |player| graded?(player) }
      end

      # 끝까지 하지 않은 사람의 등급
      def fallback_grade
        'P'
      end

      # 성적 발표: 등급 순(같으면 sort 순), 성적표 기록, 소속 점수. intro: 성적 앞에 붙일 연출 문구
      def finish_lesson!(intro = nil)
        players.each { |player| grade!(player, fallback_grade) unless graded?(player) }
        ranked = players.sort_by do |player|
          result = grades[player.seat.to_s]
          [GameGrade.rank_of(result['grade']), result['sort'] || 0]
        end

        lessons = Game::Lessons.config
        point_lines = []
        lines = ranked.each_with_index.map do |player, index|
          result = grades[player.seat.to_s]
          rank = class? ? index + 1 : nil
          GameGrade.create!(account: player.account, session: session, subject: self.class.key, grade: result['grade'], mode: mode, rank: rank, detail: result.except('grade'))
          player.update!(result: index.zero? && class? ? 'win' : nil)
          point_lines << Game::Points.give(session, player, Game::Lessons.points_for(result['grade'], mode, rank), reason: "lesson:#{self.class.key}")
          render(lessons['msg_grade_line'], rank: rank ? "#{rank}. " : '', player: player.name, grade: result['grade'],
                                            grade_name: Game::Lessons::GRADE_NAMES[result['grade']], detail: result['detail'].present? ? " · #{result['detail']}" : '')
        end

        session.update!(status: 'finished', finished_at: Time.now.utc, deadline_at: nil)
        post([intro, render(lessons['msg_grades'], subject: subject, mode: Game::Lessons.mode_name(mode), lines: lines.join("\n")), *point_lines].compact.join("\n\n"))
      end

      # 그 사람의 툿에만 답장 (수업 중 각자 진행할 때 다른 사람에게 알림이 가지 않게)
      def reply_to(player, status, text)
        Game::Poster.post(text, mentions: [player.account], thread: status, visibility: session.visibility)
      end

      def wait_seconds!(seconds)
        Game::Engine.set_deadline_in!(session, seconds.to_i.clamp(1, 24 * 3600).seconds)
      end
    end
  end
end
