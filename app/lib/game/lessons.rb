# frozen_string_literal: true

module Game
  # 마법 수업: 혼자 하는 [자습/과목], 반 전체가 함께하는 [수업/과목] → [참가].
  # 등급(O E A P D T)이 성적표에 쌓이고 소속 점수가 된다 (자습은 일부만, 수업 상위 몇 명은 보너스).
  # 과목은 Game::Kinds 에 함께 등록되고 Game::Lessons::Base 를 상속한다.
  module Lessons
    F = Game::Config::Field

    GRADE_NAMES = { 'O' => '뛰어남', 'E' => '기대 이상', 'A' => '합격', 'P' => '부족', 'D' => '형편없음', 'T' => '트롤' }.freeze

    FIELDS = [
      F.new(key: 'cmd_study', type: :string, default: '자습', group: 'commands', label: '자습', hint: '[자습/과목]'),
      F.new(key: 'cmd_class', type: :string, default: '수업', group: 'commands', label: '수업 열기', hint: '[수업/과목]'),
      F.new(key: 'cmd_join', type: :string, default: '참가', group: 'commands', label: '수업 참가'),
      F.new(key: 'cmd_report', type: :string, default: '성적표', group: 'commands', label: '성적표'),

      F.new(key: 'join_minutes', type: :integer, default: 5, group: 'time', label: '수업 참가 모집 (분)'),
      F.new(key: 'class_minutes', type: :integer, default: 30, group: 'time', label: '수업 시간 (분)', hint: '변신술처럼 각자 진행하는 수업의 마감'),
      F.new(key: 'study_daily_limit', type: :integer, default: 1, group: 'rules', label: '과목당 하루 자습 횟수'),
      F.new(key: 'class_openers', type: :lines, default: [], group: 'rules', label: '수업을 열 수 있는 아이디 (줄마다 하나)', hint: '비워 두면 누구나'),

      *GRADE_NAMES.keys.map { |grade| F.new(key: "points_#{grade}", type: :integer, default: { 'O' => 15, 'E' => 10, 'A' => 5 }.fetch(grade, 0), group: 'points', label: "#{grade} (#{GRADE_NAMES[grade]}) 점수") },
      F.new(key: 'study_percent', type: :integer, default: 50, group: 'points', label: '자습 점수 (%)'),
      F.new(key: 'class_bonus', type: :integer, default: 5, group: 'points', label: '수업 상위 보너스'),
      F.new(key: 'class_bonus_count', type: :integer, default: 3, group: 'points', label: '보너스 받는 상위 인원'),

      F.new(key: 'msg_class_open', type: :text, group: 'messages', label: '수업 모집',
            default: "📚 %{subject} 수업이 열립니다!\n%{minutes}분 안에 이 툿에 [%{join}]으로 답하면 함께합니다."),
      F.new(key: 'msg_class_start', type: :text, group: 'messages', label: '수업 시작', default: '📚 %{subject} 수업을 시작합니다. 참가자: %{names}'),
      F.new(key: 'msg_class_cancel', type: :text, group: 'messages', label: '수업 취소', default: '참가자가 모자라 %{subject} 수업이 취소되었습니다. (최소 %{min}명)'),
      F.new(key: 'msg_study_limit', type: :text, group: 'messages', label: '자습 횟수 초과', default: '%{subject} 자습은 하루 %{limit}번까지입니다.'),
      F.new(key: 'msg_locked', type: :text, group: 'messages', label: '잠긴 과목', default: '%{subject}{은는} 아직 열리지 않은 과목입니다.'),
      F.new(key: 'msg_unknown_subject', type: :text, group: 'messages', label: '없는 과목', default: '그런 과목은 없습니다. 과목: %{subjects}'),
      F.new(key: 'msg_not_opener', type: :text, group: 'messages', label: '수업 권한 없음', default: '수업은 교수만 열 수 있습니다. 혼자 연습하려면 [%{study}/%{subject}]'),
      F.new(key: 'msg_class_only', type: :text, group: 'messages', label: '수업 전용 과목', default: '%{subject}{은는} 수업으로만 열립니다.'),
      F.new(key: 'msg_study_only', type: :text, group: 'messages', label: '자습 전용 과목', default: '%{subject}{은는} 자습으로만 할 수 있습니다.'),
      F.new(key: 'msg_grades', type: :text, group: 'messages', label: '성적 발표', default: "📜 %{subject} %{mode} 성적\n\n%{lines}"),
      F.new(key: 'msg_grade_line', type: :text, group: 'messages', label: '성적 한 줄', default: '%{rank}%{player} — %{grade} (%{grade_name})%{detail}'),
      F.new(key: 'msg_report', type: :text, group: 'messages', label: '[성적표]', default: "📜 %{player}의 성적표\n\n%{lines}%{extra}\n\n이번 학기 기여: %{points}점"),
    ].freeze

    module_function

    def config
      Game::Config.for('lessons')
    end

    def all
      Game::Kinds.all.select(&:lesson?)
    end

    def by_subject(name)
      all.find { |kind| kind.config['name'] == name || kind.config['name'].delete(' ') == name.to_s.delete(' ') }
    end

    def subjects
      all.select(&:enabled?).map(&:display_name).join(', ')
    end

    def mode_name(mode)
      mode == 'class' ? '수업' : '자습'
    end

    def can_open_class?(account)
      openers = config['class_openers'].map { |name| name.delete_prefix('@') }
      openers.empty? || openers.include?(account.username)
    end

    def studied_today(account, kind)
      GamePlayer.joins(:session)
                .where(account: account, game_sessions: { kind: kind.key })
                .where("game_sessions.state->>'mode' = 'study'")
                .where(game_sessions: { created_at: Time.now.in_time_zone('Asia/Seoul').beginning_of_day.. })
                .count
    end

    # 등급 점수 (자습은 일부, 수업 상위는 보너스)
    def points_for(grade, mode, rank)
      cfg = config
      points = cfg["points_#{grade}"].to_i
      points = (points * cfg['study_percent'].to_i / 100.0).round if mode == 'study'
      points += cfg['class_bonus'].to_i if mode == 'class' && rank && rank <= cfg['class_bonus_count'].to_i && GameGrade.rank_of(grade) <= GameGrade.rank_of('A')
      points
    end

    # [성적표]: 과목별 가장 좋은 등급, 주문 레벨, 수호령, 이번 학기 기여 점수
    def report(account)
      character = GameCharacter.for(account)
      grades = GameGrade.where(account: account).group_by(&:subject)
      lines = all.filter_map do |kind|
        best = GameGrade.best(grades.fetch(kind.key, []).map(&:grade))
        best && "#{kind.display_name}: #{best} (#{GRADE_NAMES[best]})"
      end
      lines = ['아직 받은 성적이 없습니다.'] if lines.empty?

      extra = []
      levels = character.progress['spells'] || {}
      extra << "주문 숙련: #{levels.map { |spell, level| "#{spell} Lv.#{level}" }.join(', ')}" if levels.any?
      extra << "수호령: #{character.progress['patronus']}" if character.progress['patronus'].present?
      Game::Text.render(config['msg_report'], player: account, lines: lines.join("\n"),
                                              extra: extra.any? ? "\n\n#{extra.join("\n")}" : '',
                                              points: GameHousePoint.where(account: account).sum(:amount))
    end
  end
end
