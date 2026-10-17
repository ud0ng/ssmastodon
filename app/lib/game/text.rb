# frozen_string_literal: true

module Game
  # 설정 문구 채우기 (자동봇 시트처럼 한글 명령어).
  #
  #   {계정명} {계정아이디} {계정 아바타}       그 문구의 주인공 (예: 신청한 사람, 먹은 사람)
  #   {상대 계정명} {승자 계정아이디} {패자 계정 아바타} …   앞에 역할을 붙이면 그 사람
  #   {컨텐츠} {턴} {남은 개수} …               문구마다 쓸 수 있는 값 (관리 화면에 목록이 나온다)
  #   {이가} {을를} {은는} {과와} {으로로} {아야}  앞 글자 받침에 맞는 조사
  #
  # 예전 형식 %{player} 도 그대로 된다. {계정 아바타}는 그 사람 프로필 사진을 툿에 첨부한다 (Game::Poster).
  module Text
    PARTICLES = {
      '이가' => %w(이 가), '을를' => %w(을 를), '은는' => %w(은 는),
      '과와' => %w(과 와), '아야' => %w(아 야), '으로로' => %w(으로 로),
    }.freeze

    HANGUL = (0xAC00..0xD7A3)
    CLOSERS = /[\s」』)\]}>'"”’》〉]+\z/

    # 이름을 바꾸기 전 한글 토큰 (관리 화면에서 저장해 둔 문구가 계속 읽히게)
    LEGACY_LABELS = { potion: ['물약 이름'], tries: ['시도 횟수'] }.freeze

    # 사람이 들어가는 값: 역할 → 한글 앞말 ({앞말계정명} {앞말계정아이디} {앞말계정 아바타})
    ROLES = {
      player: '', opponent: '상대 ', winner: '승자 ', loser: '패자 ', next: '다음 차례 ',
      target: '대상 ', player_a: 'A ', player_b: 'B ',
    }.freeze

    # 값 → 한글 명령어
    LABELS = {
      game: '컨텐츠', subject: '과목', subjects: '과목 목록', tournament: '토너먼트', term: '소속 이름',
      house: '소속', emoji: '소속 이모지', amount: '점수', points: '점수', reward: '우승 점수',
      turn: '턴', turns: '턴 수', round: '라운드', rounds: '라운드 수', minutes: '분', seconds: '초', number: '경기 번호',
      lines: '결과 목록', board: '점수판', outcome: '결과', result: '이번 결과', tally: '승수', reason: '사유',
      players: '사람들', names: '참가자 명단', try: '시도 번호', tries: '최대 라운드', left: '남은 시도',
      target_name: '변신 결과물', score: '이번 점수', potion: '마법약 이름', strength: '강도', size: '재료 수',
      route: '경로', routes: '경로 목록', count: '개수', worst: '최악의 맛 수', remaining: '남은 개수',
      eaten: '먹은 젤리빈', flavor: '맛', max: '최대 개수', answer: '정답', guess: '조합', strike: '정답 수',
      ball: '순서 틀림 수', ingredients: '재료 목록', spell: '주문', level: '레벨', patronus: '수호령',
      focus: '집중력', before: '이전 집중력', middle: '중간 집중력', after: '이후 집중력', gain: '연습 문구',
      distraction: '방해 문구', hp: 'HP', hearts: '하트', damage: '피해', multiplier: '배수',
      choice_a: 'A 주문', choice_b: 'B 주문', spell_attack: '공격 주문 이름', spell_disarm: '무장해제 주문 이름',
      spell_defend: '방어 주문 이름', special_hint: '필살기 안내', seek_rate: '스니치 확률', task: '과제',
      half: '어중간 결과', grade: '등급', grade_name: '등급 이름', rank: '순위', detail: '세부', mode: '방식',
      min: '최소 인원', limit: '하루 횟수', extra: '추가 정보', example: '예시', win: '승리 수', lose: '패배 수', draw: '무승부 수',
      accept: '수락 명령어', decline: '거절 명령어', eat: '먹기 명령어', weak: '약 명령어', mid: '중 명령어',
      strong: '강 명령어', low: '약 명령어', high: '강 명령어', chase: '추격 명령어', beat: '몰이 명령어',
      seek: '수색 명령어', attack: '공격 명령어', disarm: '무장해제 명령어', defend: '방어 명령어',
      special: '필살 명령어', fly: '비행 명령어', brew: '조합 명령어', shield: '방어권 명령어', retry: '재시도권 명령어', cast: '주문 명령어', practice: '연습 명령어',
      study: '자습 명령어', join: '참가 명령어',
      day: '일차', traitor: '배신자 이름', traitors: '배신자 수', faction: '진영', role: '역할', roles: '역할 공개',
      mates: '동료 배신자', how: '할 일', accuse: '고발 명령어', petrify: '석화 명령어', investigate: '조사 명령어',
      protect: '보호 명령어', prophecy: '예언 명령어',
      room: '방', zone: '구역', targets: '목표 장소', student: '학생 이름', prefect: '사감 이름',
      link: '링크', creature: '마법 생물', item: '아이템', steps: '이동 칸 수', direction: '방향', text: '내용', phases: '페이즈 수', total: '총 시간',
      move: '이동 명령어', stay: '제자리 명령어', portkey: '포트키 명령어', lumos: '루모스 명령어', cooperate: '협력 명령어', hinder: '방해 명령어',
      teams: '팀 구성', rewards: '보상', money: '돈', currency: '돈 이름', items: '아이템 목록',
      range: '기간', season: '시즌', period: '시즌 기간', houses: '소속 점수', games: '판 수', winners: '최다 승리', toppers: '과목별 수석',
      **ROLES.transform_values { |prefix| "#{prefix}계정명" },
    }.freeze

    # {계정 아바타} 자리에 남기는 표시 (Game::Poster 가 빼고 사진을 첨부한다)
    AVATAR_MARK = "⁣avatar:%d⁣"
    AVATAR_PATTERN = /⁣avatar:(\d+)⁣/

    module_function

    def render(template, **values)
      tokens = {}
      values.each do |key, value|
        account = account_of(value)
        tokens[key] = account ? GameCharacter.for(account).display_name : value.to_s
        next unless account && ROLES.key?(key)

        prefix = ROLES[key]
        tokens[:"#{prefix}계정아이디"] = "@#{account.acct}"
        tokens[:"#{prefix}계정 아바타"] = format(AVATAR_MARK, account.id)
      end
      by_label = tokens.each_with_object({}) do |(key, value), labels|
        labels[LABELS[key] || key.to_s] = value
        LEGACY_LABELS.fetch(key, []).each { |legacy| labels[legacy] = value }
      end

      text = template.to_s.gsub(/%\{(\w+)\}/) { tokens.fetch(Regexp.last_match(1).to_sym, '') }
      text = text.gsub(/\{([^{}\n]{1,30})\}/) do
        name = Regexp.last_match(1)
        PARTICLES.key?(name) ? "{#{name}}" : by_label.fetch(name, "{#{name}}")
      end
      text.gsub(/\{(#{PARTICLES.keys.join('|')})\}/) do
        # 닫는 괄호·따옴표 뒤면 그 안의 마지막 글자를 본다: 「진실의 약」{이가} → 「진실의 약」이
        match = Regexp.last_match
        before = match.pre_match.gsub(AVATAR_PATTERN, '').sub(CLOSERS, '')[-1].to_s
        particle(before, match[1])
      end
    end

    # 기본 문구의 %{player} → {계정명} (관리 화면에서 한글로 보이게)
    def koreanize(template)
      template.to_s.gsub(/%\{(\w+)\}/) { "{#{LABELS[Regexp.last_match(1).to_sym] || Regexp.last_match(1)}}" }
    end

    # 이 문구에서 쓸 수 있는 명령어 (관리 화면 목록): 기본 문구에 있는 값 + 조사.
    # 사람은 {계정명} 만 보여 준다 (웹에서는 이름 옆에 아바타가 함께 보인다).
    # {계정아이디}·{계정 아바타} 는 저장해 둔 문구에서 계속 쓸 수 있다.
    def tokens_for(template)
      template.to_s.scan(/\{([^{}\n]{1,30})\}/).flatten.uniq - PARTICLES.keys
    end

    def account_of(value)
      case value
      when Account then value
      when GamePlayer then value.account
      end
    end

    def particle(before, key)
      with_final, without_final = PARTICLES.fetch(key)
      code = before.ord if before.present?
      return "#{with_final}(#{without_final})" unless code && HANGUL.cover?(code)

      final = (code - HANGUL.first) % 28
      # '으로/로': ㄹ 받침은 '로'
      return without_final if key == '으로로' && final == 8

      final.zero? ? without_final : with_final
    end
  end
end
