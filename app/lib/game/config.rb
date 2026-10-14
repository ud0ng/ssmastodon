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
        values = fields.to_h { |field| [field.key, stored.key?(field.key) ? stored[field.key] : field.default] }
        # 문구의 {소속 이름}: 지금 점수 단위의 이름
        values['house_term'] = values['group_mode'] == 'faction' ? values['faction_label'] : values['house_label'] if key == 'common'
        values
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

      # 일부 값만 바꾼다 (나머지 저장된 값은 그대로)
      def merge!(key, params)
        stored = GameConfig.find_by(key: key)&.data || {}
        update!(key, stored.merge(params.to_h.transform_keys(&:to_s)))
      end

      private

      def coerce(field, value)
        case field.type
        when :integer then value.to_s.strip.empty? ? field.default : value.to_i
        when :boolean then ActiveModel::Type::Boolean.new.cast(value) || false
        when :lines then (value.is_a?(Array) ? value : value.to_s.lines).map { |line| line.to_s.strip }.compact_blank
        when :select then field.choices.to_h.key?(value.to_s) ? value.to_s : field.default
        else value.to_s.strip
        end
      end
    end

    # 게임 공통 (명령어·시간·점수 규칙·공통 문구)
    COMMON = [
      Field.new(key: 'system_username', type: :string, default: 'system', group: 'account',
                label: '시스템 계정 아이디', hint: '컨텐츠를 진행하는 계정. 이 계정을 멘션한 툿의 [명령어]를 처리합니다.'),

      Field.new(key: 'group_mode', type: :select, default: 'house', group: 'scoring',
                choices: [['house', '기숙사'], ['faction', '진영']],
                label: '점수 기준 소속', hint: '점수·토너먼트·모래시계·결산에 쓸 소속. 바꿔도 다른 쪽 점수는 그대로 남습니다. 목록은 캐릭터 관리 > 소속 탭.'),
      Field.new(key: 'house_label', type: :string, default: '기숙사', group: 'scoring', label: '기숙사 부르는 이름'),
      Field.new(key: 'faction_label', type: :string, default: '진영', group: 'scoring', label: '진영 부르는 이름'),
      Field.new(key: 'currency_name', type: :string, default: '갈레온', group: 'account',
                label: '재화 이름', hint: '돈 단위 (예: 갈레온). 컨텐츠 보상·자동봇 상점이 같이 씁니다'),
      Field.new(key: 'bot_usernames', type: :string, default: '', group: 'account',
                label: '자동봇 계정 아이디', hint: '이 계정의 토큰으로 자동봇이 캐릭터·재화·상점을 읽고 씁니다 (쉼표로 여러 개)'),

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
      Field.new(key: 'msg_points', type: :text, group: 'messages', label: '점수 지급', default: '%{house} +%{amount}점! (%{player})'),

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

우승 %{term}: %{house}

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

우승: %{house} (+%{reward}점)"),
      Field.new(key: 'msg_record', type: :text, group: 'messages', label: '[내전적]', default: '%{player}의 전적: %{win}승 %{lose}패 %{draw}무'),
    ].freeze

    # 재화 (컨텐츠 설정 > 상점). 자동봇이 /api/v1/bot/config 로 읽는다 — 예전 자동봇 시트 '설정'·'도움말'의 재화 부분
    CURRENCY = [
      Field.new(key: 'transfer_enabled', type: :boolean, default: true, group: 'currency', label: '양도', hint: '[양도/n재화/캐릭터명] [양도/아이템/캐릭터명]'),
      Field.new(key: 'attendance_reward', type: :integer, default: 1, group: 'currency', label: '출석 보상', hint: '[출석] 한 번에 주는 재화 (0 = 출석 끔)'),
      Field.new(key: 'toot_reward_every', type: :integer, default: 0, group: 'currency', label: '툿 보상 기준', hint: '툿 N개마다 재화 지급 (0 = 끔)'),
      Field.new(key: 'toot_reward_amount', type: :integer, default: 1, group: 'currency', label: '툿 보상 재화', hint: '그때 주는 재화'),
      Field.new(key: 'help_lines', type: :lines, group: 'currency_help', label: '도움말',
                hint: '자동봇 [도움말]에 시트 도움말 뒤로 붙는 줄 (줄마다 [명령어] 설명)',
                default: [
                  '[가방] 현재 소지금과 소지품을 확인합니다.',
                  '[상점] 상점 목록을 출력합니다.',
                  '[구매/아이템명] 원하는 아이템을 구매합니다.',
                  '[설명/아이템명] 아이템의 설명을 출력합니다.',
                  '[소모/아이템명] 인벤토리에서 아이템을 소모합니다. (스탯 반영 X)',
                  '[상태 확인] 소지금, 소지품, 스탯을 확인합니다.',
                  '[사용/아이템명] 아이템을 사용합니다. (스탯 반영 O)',
                  '[양도/n재화/캐릭터명] 재화를 캐릭터에게 양도합니다.',
                  '[양도/아이템명/캐릭터명] 아이템을 캐릭터에게 양도합니다.',
                  '[출석] 하루 한 번 재화를 받습니다.',
                ]),
      Field.new(key: 'admin_help_lines', type: :lines, group: 'currency_help', label: '운영진 명령어 도움말',
                hint: '운영진이 [도움말]을 부르면 더 붙는 줄',
                default: [
                  '[소지금 추가/10/캐릭터명] [소지금 차감/10/전원] 소지금을 바꿉니다.',
                  '[아이템 추가/사과: 2/캐릭터명] [아이템 차감/사과: 1/캐릭터명] 소지품을 바꿉니다.',
                  '[힘 변경/+3/캐릭터명] 스탯을 바꿉니다. (캐릭터 관리 > 스탯)',
                ]),
    ].freeze

    SCHEMAS = { 'common' => COMMON, 'currency' => CURRENCY }.freeze
  end
end
