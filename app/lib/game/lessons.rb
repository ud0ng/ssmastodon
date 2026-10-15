# frozen_string_literal: true

module Game
  # 마법 수업: 혼자 하는 [자습/과목], 반 전체가 함께하는 [수업/과목] → [참가].
  # 등급(O E A P D T)이 성적표에 쌓이고 소속 점수가 된다 (자습은 일부만, 수업 상위 몇 명은 보너스).
  # 과목은 Game::Kinds 에 함께 등록되고 Game::Lessons::Base 를 상속한다.
  module Lessons
    F = Game::Config::Field

    GRADE_NAMES = { 'O' => '뛰어남', 'E' => '기대 이상', 'A' => '합격', 'P' => '부족', 'D' => '형편없음', 'T' => '트롤' }.freeze

    FIELDS = [
      # 명령어
      F.new(key: 'cmd_study', type: :string, default: '자습', group: 'commands', label: '자습', hint: '[자습/과목]'),
      F.new(key: 'cmd_class', type: :string, default: '수업', group: 'commands', label: '수업', hint: '[수업/과목] — 시스템 계정으로 직접 쓴 툿만 수업을 엽니다'),
      F.new(key: 'cmd_join', type: :string, default: '참가', group: 'commands', label: '참가'),
      F.new(key: 'cmd_report', type: :string, default: '성적표', group: 'commands', label: '성적'),

      # 기본룰
      F.new(key: 'join_minutes', type: :integer, default: 5, group: 'rules', label: '참가 모집 (분)'),
      F.new(key: 'class_minutes', type: :integer, default: 30, group: 'rules', label: '수업 시간 (분)', hint: '변신술처럼 각자 진행하는 수업의 마감'),
      F.new(key: 'study_daily_limit', type: :integer, default: 1, group: 'rules', label: '과목당 1일 자습 횟수'),

      # 등급별 소속 점수 · 그 사람에게 주는 재화 · 아이템 (자습·수업 같음)
      *GRADE_NAMES.keys.map { |grade| F.new(key: "points_#{grade}", type: :integer, default: { 'O' => 15, 'E' => 10, 'A' => 5 }.fetch(grade, 0), group: 'grades', label: "#{grade} (#{GRADE_NAMES[grade]}) 점수") },
      *GRADE_NAMES.keys.map { |grade| F.new(key: "reward_money_#{grade}", type: :integer, default: { 'O' => 10, 'E' => 6, 'A' => 3 }.fetch(grade, 0), group: 'grades', label: "#{grade} (#{GRADE_NAMES[grade]}) 재화") },
      *GRADE_NAMES.keys.map { |grade| F.new(key: "reward_items_#{grade}", type: :lines, default: grade == 'O' ? ['초콜릿 개구리|1|50'] : [], group: 'grades', label: "#{grade} (#{GRADE_NAMES[grade]}) 아이템", hint: Game::Rewards::ITEMS_HINT) },

      # 수업 상위 보너스: 등급 점수의 %만큼 더, 그 사람들에게 재화·아이템
      F.new(key: 'class_bonus_percent', type: :integer, default: 30, group: 'bonus', label: '상위 보너스 (%)', hint: '수업 상위 인원의 등급 점수에 이만큼 더합니다 (A 이상만)'),
      F.new(key: 'class_bonus_count', type: :integer, default: 3, group: 'bonus', label: '보너스 받는 상위 인원'),
      F.new(key: 'bonus_money', type: :integer, default: 5, group: 'bonus', label: '상위 인원 재화'),
      F.new(key: 'reward_items_bonus', type: :lines, default: [], group: 'bonus', label: '상위 인원 아이템', hint: Game::Rewards::ITEMS_HINT),

      F.new(key: 'msg_class_open', type: :text, group: 'messages', label: '수업 모집',
            default: "📚 %{subject} 수업이 열립니다!\n%{minutes}분 안에 이 툿에 [%{join}]으로 답하면 함께합니다."),
      F.new(key: 'msg_class_start', type: :text, group: 'messages', label: '수업 시작', default: '📚 %{subject} 수업을 시작합니다. 참가자: %{names}'),
      F.new(key: 'msg_class_cancel', type: :text, group: 'messages', label: '수업 취소', default: '참가자가 모자라 %{subject} 수업이 취소되었습니다. (최소 %{min}명)'),
      F.new(key: 'msg_study_limit', type: :text, group: 'messages', label: '자습 횟수 초과', default: '%{subject} 자습은 하루 %{limit}번까지입니다.'),
      F.new(key: 'msg_locked', type: :text, group: 'messages', label: '잠긴 과목', default: '%{subject}{은는} 아직 열리지 않은 과목입니다.'),
      F.new(key: 'msg_unknown_subject', type: :text, group: 'messages', label: '없는 과목', default: '그런 과목은 없습니다. 과목: %{subjects}'),
      F.new(key: 'msg_not_opener', type: :text, group: 'messages', label: '수업 권한 없음', default: '수업은 운영진이 시스템 계정으로 엽니다. 혼자 연습하려면 [%{study}/%{subject}]'),
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

    # 수업은 시스템 계정으로 직접 쓴 [수업/과목] 툿만 연다 (Game::System.class_toot?)
    def can_open_class?(account)
      account.present? && account.id == Game::System.account&.id
    end

    def studied_today(account, kind)
      GamePlayer.joins(:session)
                .where(account: account, game_sessions: { kind: kind.key })
                .where("game_sessions.state->>'mode' = 'study'")
                .where(game_sessions: { created_at: Time.now.in_time_zone('Asia/Seoul').beginning_of_day.. })
                .count
    end

    # 수업 상위 인원인가 (A 이상만)
    def top_rank?(grade, mode, rank, cfg = config)
      mode == 'class' && rank.present? && rank <= cfg['class_bonus_count'].to_i && GameGrade.rank_of(grade) <= GameGrade.rank_of('A')
    end

    # 등급 점수 (자습·수업 같음). 수업 상위 인원은 등급 점수의 상위 보너스(%)만큼 더
    def points_for(grade, mode, rank)
      cfg = config
      points = cfg["points_#{grade}"].to_i
      points += (points * cfg['class_bonus_percent'].to_i / 100.0).round if top_rank?(grade, mode, rank, cfg)
      points
    end

    # 그 사람에게 주는 재화·아이템: 등급 몫 + 수업 상위 인원 몫
    def rewards_for(grade, mode, rank)
      cfg = config
      money = cfg["reward_money_#{grade}"].to_i
      items = Game::Rewards.roll(cfg["reward_items_#{grade}"])
      if top_rank?(grade, mode, rank, cfg)
        money += cfg['bonus_money'].to_i
        items += Game::Rewards.roll(cfg['reward_items_bonus'])
      end
      { money: money, items: items }
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
