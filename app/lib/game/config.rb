# frozen_string_literal: true

# 게임 설정 (관리 > 게임 설정). 항목마다 기본값이 있고, 운영진이 바꾼 값만 game_configs 에 저장한다.
#
# 항목 종류: string(한 줄), integer, boolean, lines(줄마다 하나 → 배열), text(여러 줄 문구), select(choices 중 하나)
# 문구에는 %{이름} 자리표시와 {이가}{을를}{은는}{과와}{으로로}{아야} 조사를 쓸 수 있다.
module Game
  class Config
    Field = Struct.new(:key, :type, :default, :label, :hint, :group, :choices, keyword_init: true) do
      # 문구 기본값은 한글 명령어로 ({계정명} 등, Game::Text)
      def default
        %i(text string).include?(type) ? Game::Text.koreanize(self[:default]) : self[:default]
      end

      # 관리 화면에서 이 문구에 쓸 수 있는 명령어
      def tokens
        type == :text ? Game::Text.tokens_for(default) : []
      end
    end

    TYPES = %i(string integer boolean lines text select).freeze

    class << self
      # key 의 설정 (기본값 + 저장된 값), 문자열 키 Hash
      def for(key)
        fields = schema(key)
        stored = GameConfig.find_by(key: key)&.data || {}
        fields.to_h { |field| [field.key, stored.key?(field.key) ? stored[field.key] : field.default] }
      end

      def [](key)
        self.for(key)
      end

      def schema(key)
        return Game::Lessons::FIELDS if key == 'lessons'

        SCHEMAS.fetch(key) { Game::Kinds.fetch(key).schema }
      end

      def keys
        SCHEMAS.keys + ['lessons'] + Game::Kinds.keys
      end

      # 관리 화면에서 받은 값 저장 (기본값과 같은 값은 지운다)
      def update!(key, params)
        data = schema(key).each_with_object({}) do |field, result|
          next unless params.key?(field.key)

          value = coerce(field, params[field.key])
          result[field.key] = value unless value == field.default
        end
        GameConfig.find_or_initialize_by(key: key).update!(data: data)
      end

      private

      def coerce(field, value)
        case field.type
        when :integer then value.to_s.strip.empty? ? field.default : value.to_i
        when :boolean then ActiveModel::Type::Boolean.new.cast(value) || false
        when :lines then value.to_s.lines.map(&:strip).compact_blank
        when :select then field.choices.to_h.key?(value.to_s) ? value.to_s : field.default
        else value.to_s.strip
        end
      end
    end

    # 게임 공통 (명령어·시간·점수 규칙·공통 문구)
    COMMON = [
      Field.new(key: 'system_username', type: :string, default: 'system', group: 'account',
                label: '시스템 계정 아이디', hint: '컨텐츠를 진행하는 계정. 이 계정을 멘션한 툿의 [명령어]를 처리합니다.'),

      Field.new(key: 'house_term', type: :string, default: '기숙사', group: 'account',
                label: '소속 이름', hint: '점수를 모으는 단위. 학생 기간은 기숙사, 성인 기간은 진영처럼 바꿔 쓸 수 있습니다.'),
      Field.new(key: 'currency_name', type: :string, default: '갈레온', group: 'account',
                label: '돈 이름', hint: '캐릭터 명단의 돈 단위 (예: 갈레온)'),

      Field.new(key: 'scoring_mode', type: :select, default: 'points', group: 'scoring',
                choices: [['points', '점수제 (컨텐츠마다 이기면 점수)'], ['tournament', '토너먼트제 (대진표 경기의 승수가 가장 많은 소속만 우승 점수)']],
                label: '점수 방식', hint: '토너먼트제에서는 평소 컨텐츠를 해도 점수가 없습니다. 대진표는 토너먼트 탭에서 만듭니다.'),

      Field.new(key: 'cmd_accept', type: :string, default: '수락', group: 'commands', label: '수락'),
      Field.new(key: 'cmd_decline', type: :string, default: '거절', group: 'commands', label: '거절'),
      Field.new(key: 'cmd_forfeit', type: :string, default: '기권', group: 'commands', label: '기권'),
      Field.new(key: 'cmd_points', type: :string, default: '점수', group: 'commands', label: '점수 보기'),
      Field.new(key: 'cmd_record', type: :string, default: '내전적', group: 'commands', label: '내 전적'),

      Field.new(key: 'invite_minutes', type: :integer, default: 10, group: 'time', label: '수락 대기 (분)', hint: '응답이 없으면 신청 취소'),
      Field.new(key: 'turn_minutes', type: :integer, default: 5, group: 'time', label: '한 턴 대기 (분)', hint: '시간이 지나면 그 턴 패배 처리'),

      Field.new(key: 'one_game_per_person', type: :boolean, default: true, group: 'rules', label: '한 사람당 진행 중인 컨텐츠 1개'),
      Field.new(key: 'daily_pair_limit', type: :integer, default: 3, group: 'rules', label: '같은 상대 하루 점수 지급 횟수', hint: '0 = 제한 없음'),
      Field.new(key: 'same_house_percent', type: :integer, default: 50, group: 'rules', label: '같은 소속끼리 점수 (%)'),

      Field.new(key: 'msg_invite', type: :text, group: 'messages', label: '신청',
                default: "%{opponent}, %{player}{이가} %{game}{을를} 신청했습니다!\n[%{accept}] 또는 [%{decline}]로 답해 주세요. (%{minutes}분 안에)"),
      Field.new(key: 'msg_declined', type: :text, group: 'messages', label: '거절', default: '%{player}{이가} 신청을 거절했습니다.'),
      Field.new(key: 'msg_expired', type: :text, group: 'messages', label: '수락 시간 초과', default: '%{minutes}분 동안 응답이 없어 %{game} 신청이 취소되었습니다.'),
      Field.new(key: 'msg_forfeit', type: :text, group: 'messages', label: '기권', default: '%{player}{이가} 기권했습니다. %{winner}의 승리!'),
      Field.new(key: 'msg_busy', type: :text, group: 'messages', label: '이미 진행 중', default: '%{player}{은는} 이미 진행 중인 컨텐츠가 있습니다.'),
      Field.new(key: 'msg_one_opponent', type: :text, group: 'messages', label: '상대가 여러 명', default: '%{game}{은는} 1:1로만 할 수 있습니다. 상대를 한 명만 태그해 주세요.'),
      Field.new(key: 'msg_many_opponents', type: :text, group: 'messages', label: '상대가 너무 많음', default: '%{game}에는 상대를 %{max}명까지 태그할 수 있습니다.'),
      Field.new(key: 'msg_no_opponent', type: :text, group: 'messages', label: '상대 없음', default: '%{game}{을를} 함께할 상대를 태그해 주세요.'),
      Field.new(key: 'msg_disabled', type: :text, group: 'messages', label: '꺼진 컨텐츠', default: '%{game}{은는} 지금 열려 있지 않습니다.'),
      Field.new(key: 'msg_event_not_opener', type: :text, group: 'messages', label: '이벤트를 열 수 없음', default: '%{game}{은는} 운영진만 열 수 있습니다.'),
      Field.new(key: 'msg_event_running', type: :text, group: 'messages', label: '이벤트 진행 중', default: '%{game}{이가} 이미 열려 있습니다.'),
      Field.new(key: 'msg_secret_in_dm', type: :text, group: 'messages', label: '비밀 선택은 DM으로',
                default: '선택은 상대가 보지 못하게 시스템 계정에게 DM으로 보내 주세요.'),
      Field.new(key: 'msg_points', type: :text, group: 'messages', label: '점수 지급', default: '%{emoji} %{house} +%{amount}점! (%{player})'),

      Field.new(key: 'weekly_enabled', type: :boolean, default: true, group: 'summary', label: '주간 결산 툿', hint: '정한 요일·시각에 이번 주 소속 점수 변화와 최다 승리를 올린다'),
      Field.new(key: 'weekly_wday', type: :select, default: '0', group: 'summary', label: '주간 결산 요일',
                choices: [%w(0 일요일), %w(1 월요일), %w(2 화요일), %w(3 수요일), %w(4 목요일), %w(5 금요일), %w(6 토요일)]),
      Field.new(key: 'weekly_hour', type: :integer, default: 21, group: 'summary', label: '주간 결산 시각 (0~23시, 한국 시간)'),
      Field.new(key: 'msg_weekly', type: :text, group: 'summary', label: '주간 결산',
                default: "📜 이번 주 결산 (%{range})

%{houses}

이번 주 컨텐츠 %{games}판
최다 승리: %{winners}"),
      Field.new(key: 'msg_term', type: :text, group: 'summary', label: '학기 마감',
                default: "🏰 학기 마감!

%{houses}

우승 %{term}: %{emoji} %{house}

과목별 수석
%{toppers}"),
      Field.new(key: 'msg_reward', type: :text, group: 'messages', label: '보상 지급', default: '💰 %{player} 보상: %{rewards}'),
      Field.new(key: 'msg_no_house', type: :text, group: 'messages', label: '소속 없음', default: '%{player}{은는} 아직 %{term}{이가} 없어 점수를 받지 못했습니다.'),
      Field.new(key: 'msg_board', type: :text, group: 'messages', label: '[점수] 머리말', default: '🏆 %{term} 점수'),
      Field.new(key: 'round_final', type: :string, default: '결승', group: 'tournament', label: '결승 이름'),
      Field.new(key: 'round_semifinal', type: :string, default: '준결승', group: 'tournament', label: '준결승 이름'),
      Field.new(key: 'round_of', type: :string, default: '%{count}강', group: 'tournament', label: '그 앞 라운드 이름', hint: '%{count} = 남은 인원'),
      Field.new(key: 'msg_tournament_open', type: :text, group: 'tournament', label: '경기 시작',
                default: "🏆 %{tournament} %{round} %{number}경기
%{player_a} vs %{player_b} — %{game}

지금 시작합니다!"),
      Field.new(key: 'msg_tournament_judging', type: :text, group: 'tournament', label: '운영진 판정 대기',
                default: '⏸ 경기가 멈췄습니다 (%{reason}). 운영진 판정을 기다립니다.'),
      Field.new(key: 'msg_tournament_decided', type: :text, group: 'tournament', label: '운영진 판정', default: '⚖️ 운영진 판정: %{winner}의 승리!'),
      Field.new(key: 'msg_tournament_champion', type: :text, group: 'tournament', label: '우승',
                default: "🏆 %{tournament} 종료!

%{tally}

우승: %{emoji} %{house} (+%{reward}점)"),
      Field.new(key: 'msg_record', type: :text, group: 'messages', label: '[내전적]', default: '%{player}의 전적: %{win}승 %{lose}패 %{draw}무'),
    ].freeze

    SCHEMAS = { 'common' => COMMON }.freeze
  end
end
