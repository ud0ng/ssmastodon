# frozen_string_literal: true

# 게임 설정 (관리 > 게임 설정). 항목마다 기본값이 있고, 운영진이 바꾼 값만 game_configs 에 저장한다.
#
# 항목 종류: string(한 줄), integer, boolean, lines(줄마다 하나 → 배열), text(여러 줄 문구), select(choices 중 하나),
#           account(회원 아이디, 관리 화면에서 회원 목록 드롭다운)
# 문구에는 %{이름} 자리표시와 {이가}{을를}{은는}{과와}{으로로}{아야} 조사를 쓸 수 있다.
module Game
  class Config
    # columns: lines 를 '칸|칸' 표로 고칠 때 칸 이름 (도움말의 명령어|설명)
    # default 가 lambda 면 읽을 때마다 계산한다 (도움말 기본 줄은 지금 명령어 이름·켜진 컨텐츠로)
    Field = Struct.new(:key, :type, :default, :label, :hint, :group, :choices, :columns, keyword_init: true) do
      # 문구 기본값은 한글 명령어로 ({계정명} 등, Game::Text)
      def default
        value = self[:default].respond_to?(:call) ? self[:default].call : self[:default]
        %i(text string).include?(type) ? Game::Text.koreanize(value) : value
      end

      # 관리 화면에서 이 문구에 쓸 수 있는 명령어
      def tokens
        type == :text ? Game::Text.tokens_for(default) : []
      end
    end

    TYPES = %i(string integer boolean lines text select account accounts).freeze

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
        return Game::Help::FIELDS if key == 'help'

        SCHEMAS.fetch(key) { Game::Kinds.fetch(key).schema }
      end

      def keys
        SCHEMAS.keys + %w(help) + Game::Kinds.keys
      end

      # 관리 화면에서 묶어 보여 줄 칸: [[묶음 이름, 칸들], ...]
      # 공통 설정은 화면(page)마다 LAYOUT 에 적은 묶음만, 컨텐츠는 LAYOUT 뒤에 나머지 (컨텐츠의 points 는 설정 탭 표로).
      def sections(key, page = nil)
        fields = schema(key)
        layout = key == 'help' ? Game::Help::PAGES.fetch(page || 'shop_bot') : LAYOUT[page ? [key, page] : key]
        kind = Game::Kinds.registry[key]
        layout ||= LAYOUT[:content_subject] if kind
        return fields.group_by(&:group).to_a if layout.nil?

        placed = layout.filter_map do |name, groups|
          list = fields.select { |field| groups.include?(field.group) }
          [name, list] if list.any?
        end
        return placed if page

        rest = fields - placed.flat_map(&:last)
        placed + rest.group_by(&:group).to_a
      end

      # 한 턴 대기 시간 (초)
      def turn_seconds
        self.for('common')['turn_seconds'].to_i.clamp(10, 24 * 60 * 60)
      end

      # 문구에 넣는 턴 시간 ({초} {분})
      def turn_time
        seconds = turn_seconds
        { seconds: seconds, minutes: (seconds / 60.0).ceil }
      end

      # 관리 화면에서 받은 값 저장 (기본값과 같은 값은 지운다). 받지 않은 항목은 저장된 값을 그대로 둔다
      def update!(key, params)
        stored = GameConfig.find_by(key: key)&.data || {}
        data = schema(key).each_with_object({}) do |field, result|
          if params.key?(field.key)
            value = coerce(field, params[field.key])
            result[field.key] = value unless value == field.default
          elsif stored.key?(field.key)
            result[field.key] = stored[field.key]
          end
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
        when :account then value.to_s.strip.delete_prefix('@')
        when :accounts then Array(value).flat_map { |item| item.to_s.split(/[\s,]+/) }.map { |item| item.strip.delete_prefix('@') }.compact_blank.uniq
        # 폼으로 오는 줄바꿈(\r\n)을 \n 으로 맞춘다 — 안 그러면 기본값과 같은 문구도 '바뀐 값'으로 저장돼 기본 문구를 고쳐도 반영되지 않는다
        when :text then value.to_s.gsub("\r\n", "\n").tr("\r", "\n").strip
        else value.to_s.strip
        end
      end
    end

    # 게임 공통 설정. 관리 화면은 PAGES 대로 나눠 보여 준다 (컨텐츠 설정 > 설정 / 명령어, 캐릭터 관리 > 소속)
    COMMON = [
      # 봇 계정 설정
      Field.new(key: 'system_username', type: :account, default: 'system', group: 'bots',
                label: '시스템 계정 아이디', hint: '컨텐츠를 진행하는 계정. 이 계정을 멘션한 툿의 [명령어]를 처리합니다.'),
      Field.new(key: 'bot_usernames', type: :account, default: '', group: 'bots',
                label: '상점 계정 아이디', hint: '자동봇(상점·출석·조사) 계정. 이 계정의 토큰으로 캐릭터·재화·상점을 읽고 씁니다.'),

      # 재화 설정
      Field.new(key: 'currency_name', type: :string, default: '갈레온', group: 'currency',
                label: '재화 이름', hint: '돈 단위 (예: 갈레온). 컨텐츠 보상·상점·활동이 같이 씁니다'),
      Field.new(key: 'attendance_reward', type: :integer, default: 5, group: 'currency',
                label: '출석 보상', hint: '[출석] 명령어로 하루(00시 기준) 한 번 주는 재화 (0 = 출석 끔)'),
      Field.new(key: 'toot_reward_basis', type: :select, default: 'chars', group: 'currency',
                choices: [['toots', '툿 수'], ['chars', '글자 수']], label: '툿 보상 기준'),
      Field.new(key: 'toot_reward_public', type: :boolean, default: true, group: 'currency',
                label: '퍼블 툿 포함', hint: '끄면 답글만 셉니다. DM 은 세지 않습니다'),
      Field.new(key: 'toot_reward_every', type: :integer, default: 100, group: 'currency',
                label: '툿 보상 단위', hint: '툿 수 또는 글자 수가 이만큼 쌓일 때마다 지급 (0 = 끔)'),
      Field.new(key: 'toot_reward_amount', type: :integer, default: 1, group: 'currency',
                label: '툿 보상 재화', hint: '단위를 채울 때마다 자동으로 주는 재화'),

      # 공통룰 설정
      Field.new(key: 'contents_open', type: :boolean, default: true, group: 'rules',
                label: '컨텐츠 해금', hint: '끄면 사용자 화면에서 컨텐츠 메뉴가 사라집니다 (운영진은 항상 보입니다)'),
      Field.new(key: 'invite_minutes', type: :integer, default: 10, group: 'rules', label: '수락 대기 (분)', hint: '응답이 없으면 신청 취소'),
      Field.new(key: 'turn_seconds', type: :integer, default: 300, group: 'rules', label: '한 턴 대기 (초)', hint: '시간이 지나면 그 턴 패배 처리'),
      Field.new(key: 'one_game_per_person', type: :boolean, default: true, group: 'rules',
                label: '컨텐츠 동시 진행 막기', hint: '켜면 한 사람이 진행 중인 컨텐츠는 1개까지'),

      # 소속·점수 (캐릭터 관리 > 소속에서 고친다)
      Field.new(key: 'group_mode', type: :select, default: 'house', group: 'groups',
                choices: [['house', '기숙사'], ['faction', '진영']], label: '점수 기준 소속'),
      Field.new(key: 'scoring_mode', type: :select, default: 'points', group: 'groups',
                choices: [['points', '점수제'], ['games', '판수제']], label: '점수 방식',
                hint: '점수제: 컨텐츠마다 정한 승·무·패 점수의 총합으로 승부 / 판수제: 컨텐츠를 승리한 판 수로 승부'),
      Field.new(key: 'house_label', type: :string, default: '기숙사', group: 'groups', label: '기숙사 부르는 이름'),
      Field.new(key: 'faction_label', type: :string, default: '진영', group: 'groups', label: '진영 부르는 이름'),

      # 기본 명령어
      Field.new(key: 'cmd_accept', type: :string, default: '수락', group: 'commands', label: '수락'),
      Field.new(key: 'cmd_decline', type: :string, default: '거절', group: 'commands', label: '거절'),
      Field.new(key: 'cmd_cancel', type: :string, default: '신청취소', group: 'commands', label: '신청 취소', hint: '내가 한 신청을 상대가 수락하기 전에 취소'),
      Field.new(key: 'cmd_forfeit', type: :string, default: '기권', group: 'commands', label: '기권', hint: '웹에서는 항복 버튼으로 보냅니다'),
      Field.new(key: 'cmd_points', type: :string, default: '점수', group: 'commands', label: '소속 점수 보기'),
      Field.new(key: 'cmd_record', type: :string, default: '내전적', group: 'commands', label: '내 전적 보기'),

      # 일반 문구: 신청·진행
      Field.new(key: 'msg_invite', type: :text, group: 'messages_match', label: '신청',
                default: "%{player}{이가} %{opponent}에게 %{game}{을를} 신청했습니다.\n%{minutes}분 내로 [%{accept}] 또는 [%{decline}]로 답해 주세요."),
      Field.new(key: 'msg_declined', type: :text, group: 'messages_match', label: '거절', default: '%{player}{이가} 신청을 거절했습니다.'),
      Field.new(key: 'msg_cancelled', type: :text, group: 'messages_match', label: '신청 취소', default: '%{player}{이가} 신청을 취소했습니다.'),
      Field.new(key: 'msg_expired', type: :text, group: 'messages_match', label: '수락 시간 초과', default: "%{minutes}분 동안 응답이 없어 %{game}{이가} 취소되었습니다."),
      Field.new(key: 'msg_forfeit', type: :text, group: 'messages_match', label: '기권', default: "%{player}{이가} 기권했습니다.\n%{winner}의 승리입니다."),
      Field.new(key: 'msg_busy', type: :text, group: 'messages_match', label: '이미 진행 중', default: "%{player}{은는} 이미 진행 중인 컨텐츠가 있어 새로 시작할 수 없습니다."),
      Field.new(key: 'msg_busy_web', type: :text, group: 'messages_match', label: '이미 진행 중 (웹 시작하기)',
                hint: '동시 진행을 막았을 때 웹에서 [시작하기]를 누르면 바로 보여 주는 문구',
                default: '이미 진행 중인 컨텐츠가 있습니다. 끝난 뒤에 시작해 주세요.'),
      Field.new(key: 'msg_secret_in_dm', type: :text, group: 'messages_match', label: '비밀 선택은 DM으로',
                default: "선택은 상대가 보지 못하도록 시스템 계정에게 DM으로 보내 주세요."),

      # 일반 문구: 잘못 신청했을 때
      Field.new(key: 'msg_one_opponent', type: :text, group: 'messages_invalid', label: '상대가 여러 명', default: "%{game}{은는} 1:1로만 진행할 수 있습니다. 상대를 한 명만 태그해 주세요."),
      Field.new(key: 'msg_many_opponents', type: :text, group: 'messages_invalid', label: '상대가 너무 많음', default: '%{game}에는 상대를 %{max}명까지 태그할 수 있습니다.'),
      Field.new(key: 'msg_no_opponent', type: :text, group: 'messages_invalid', label: '상대 없음', default: '%{game}{을를} 함께할 상대를 태그해 주세요.'),
      Field.new(key: 'msg_disabled', type: :text, group: 'messages_invalid', label: '꺼진 컨텐츠', default: '%{game}{은는} 지금 열려 있지 않습니다.'),
      Field.new(key: 'msg_event_not_opener', type: :text, group: 'messages_invalid', label: '이벤트를 열 수 없음', default: '%{game}{은는} 운영진만 열 수 있습니다.'),
      Field.new(key: 'msg_event_running', type: :text, group: 'messages_invalid', label: '이벤트 진행 중', default: '%{game}{이가} 이미 열려 있습니다.'),

      # 일반 문구: 점수·보상·전적
      Field.new(key: 'msg_points', type: :text, group: 'messages_score', label: '점수 지급', default: "%{house}(%{player})가 +%{amount}점을 얻습니다!"),
      Field.new(key: 'msg_reward', type: :text, group: 'messages_score', label: '보상 지급', default: "%{player}{은는} %{rewards}{을를} 획득합니다."),
      Field.new(key: 'msg_no_house', type: :text, group: 'messages_score', label: '소속 없음', default: '%{player}{은는} 아직 %{term}{이가} 없어 점수를 받지 못했습니다.'),
      Field.new(key: 'msg_board', type: :text, group: 'messages_score', label: '[점수] 머리말', default: "%{term} 점수"),
      Field.new(key: 'msg_record', type: :text, group: 'messages_score', label: '[내전적]', default: '%{player}의 전적: %{win}승 %{lose}패 %{draw}무'),

      # 웹에서 선물했을 때 받는 사람에게 가는 DM (시스템 계정)
      Field.new(key: 'msg_gift_item', type: :text, group: 'messages_gift', label: '아이템 선물',
                default: "%{player}{이가} %{item} %{count}개{을를} 선물했습니다.\n인벤토리에서 확인해 보세요."),
      Field.new(key: 'msg_item_use', type: :text, group: 'messages_gift', label: '아이템 사용 (다른 캐릭터에게)',
                default: "%{player}{이가} %{target}에게 %{item}{을를} 사용했습니다.%{effect}"),
      Field.new(key: 'msg_gift_money', type: :text, group: 'messages_gift', label: '재화 선물',
                default: "%{player}{이가} %{money}%{currency}{을를} 선물했습니다."),

      # 시즌 문구 (캐릭터 관리 > 소속 > 시즌)
      Field.new(key: 'msg_season_interim', type: :text, group: 'season', label: '중간 결산',
                default: "%{season} 중간 결산\n\n%{houses}"),
      Field.new(key: 'msg_season_final', type: :text, group: 'season', label: '시즌 종료',
                default: "%{season} 종료\n\n%{houses}\n\n우승 %{term}: %{house}"),

      # 토너먼트 (관리 화면에서는 고치지 않는다)
      Field.new(key: 'round_final', type: :string, default: '결승', group: 'tournament', label: '결승 이름'),
      Field.new(key: 'round_semifinal', type: :string, default: '준결승', group: 'tournament', label: '준결승 이름'),
      Field.new(key: 'round_of', type: :string, default: '%{count}강', group: 'tournament', label: '그 앞 라운드 이름', hint: '%{count} = 남은 인원'),
      Field.new(key: 'msg_tournament_open', type: :text, group: 'tournament', label: '경기 시작',
                default: "%{tournament} %{round} %{number}경기\n%{player_a} vs %{player_b} — %{game}\n\n경기를 시작합니다."),
      Field.new(key: 'msg_tournament_judging', type: :text, group: 'tournament', label: '운영진 판정 대기',
                default: "경기가 중단되었습니다. (%{reason})\n운영진 판정을 기다립니다."),
      Field.new(key: 'msg_tournament_decided', type: :text, group: 'tournament', label: '운영진 판정', default: "운영진 판정: %{winner}의 승리입니다."),
      Field.new(key: 'msg_tournament_champion', type: :text, group: 'tournament', label: '우승',
                default: "%{tournament} 종료\n\n%{tally}\n\n우승: %{house} (+%{reward}점)"),
    ].freeze

    # 상점 (컨텐츠 설정 > 상점). 자동봇이 /api/v1/bot/config 로 읽는다 (명령어 이름·운영진·도움말)
    CURRENCY = [
      # 상점 해금: 끄면 웹 상점 메뉴·화면이 사라지고 웹·자동봇 구매를 받지 않는다 (인벤토리·사용·양도는 그대로)
      Field.new(key: 'shop_open', type: :boolean, default: true, group: 'shop_open', label: '상점 해금', hint: '끄면 사용자 화면에서 상점 메뉴가 사라지고 [상점]·[구매]를 받지 않습니다 (운영진은 웹에서 항상 보입니다)'),

      # 상점 명령어 (자동봇이 처리). 이름만 바꾸면 자동봇 도움말도 같이 바뀐다
      Field.new(key: 'cmd_bag', type: :string, default: '가방', group: 'shop_commands', label: '가방', hint: '소지금과 소지품'),
      Field.new(key: 'cmd_shop', type: :string, default: '상점', group: 'shop_commands', label: '상점', hint: '상점 목록'),
      Field.new(key: 'cmd_buy', type: :string, default: '구매', group: 'shop_commands', label: '구매', hint: '[구매/아이템명]'),
      Field.new(key: 'cmd_describe', type: :string, default: '설명', group: 'shop_commands', label: '설명', hint: '[설명/아이템명]'),
      Field.new(key: 'cmd_discard', type: :string, default: '버리기', group: 'shop_commands', label: '버리기', hint: '효과 없이 아이템 1개를 버린다'),
      Field.new(key: 'cmd_use', type: :string, default: '사용', group: 'shop_commands', label: '사용', hint: '아이템 효과(스탯)를 반영한다'),
      Field.new(key: 'cmd_status', type: :string, default: '상태 확인', group: 'shop_commands', label: '상태 확인', hint: '소지금·소지품·스탯'),
      Field.new(key: 'cmd_transfer', type: :string, default: '양도', group: 'shop_commands', label: '양도', hint: '[양도/n재화/캐릭터명] [양도/아이템/캐릭터명]'),
      Field.new(key: 'cmd_attendance', type: :string, default: '출석', group: 'shop_commands', label: '출석', hint: '보상은 설정 탭의 출석 보상'),
      Field.new(key: 'transfer_enabled', type: :boolean, default: true, group: 'shop_commands', label: '양도 켜기', hint: '끄면 [양도]를 받지 않습니다'),

      # 운영진 명령어 (운영진 계정만)
      Field.new(key: 'admin_usernames', type: :accounts, default: [], group: 'admin_commands', label: '운영진 계정',
                hint: '아래 명령어를 쓸 수 있는 계정. 자동봇 설정(ADMIN_IDS·시트)의 운영진도 그대로 쓸 수 있습니다'),
      Field.new(key: 'cmd_money_add', type: :string, default: '소지금 추가', group: 'admin_commands', label: '소지금 추가', hint: '[소지금 추가/10/캐릭터명]'),
      Field.new(key: 'cmd_money_sub', type: :string, default: '소지금 차감', group: 'admin_commands', label: '소지금 차감', hint: '[소지금 차감/10/전원]'),
      Field.new(key: 'cmd_item_add', type: :string, default: '아이템 추가', group: 'admin_commands', label: '아이템 추가', hint: '[아이템 추가/사과: 2/캐릭터명]'),
      Field.new(key: 'cmd_item_sub', type: :string, default: '아이템 차감', group: 'admin_commands', label: '아이템 차감', hint: '[아이템 차감/사과: 1/캐릭터명]'),
      Field.new(key: 'cmd_stat_change', type: :string, default: '변경', group: 'admin_commands', label: '스탯 변경', hint: '스탯 이름 뒤에 붙인다: [힘 변경/+3/캐릭터명]'),
    ].freeze

    # 자동봇 [상점 도움말] 줄: 명령어 이름은 위 설정으로 채운다 (%{cmd}, 양도는 %{currency}). [도움말] 은 분류 목록만 보여 준다
    SHOP_HELP = [
      ['cmd_bag', '[%{cmd}] 현재 소지금과 소지품을 확인합니다.'],
      ['cmd_shop', '[%{cmd}] 상점 목록을 출력합니다.'],
      ['cmd_buy', '[%{cmd}/아이템명] 원하는 아이템을 구매합니다.'],
      ['cmd_describe', '[%{cmd}/아이템명] 아이템의 설명을 출력합니다.'],
      ['cmd_discard', '[%{cmd}/아이템명] 인벤토리에서 아이템을 버립니다. (효과 없음)'],
      ['cmd_status', '[%{cmd}] 소지금, 소지품, 스탯을 확인합니다.'],
      ['cmd_use', '[%{cmd}/아이템명] 아이템을 사용합니다. (스탯 반영 O)'],
      ['cmd_transfer', '[%{cmd}/n%{currency}/캐릭터명] 재화를 캐릭터에게 양도합니다.'],
      ['cmd_transfer', '[%{cmd}/아이템명/캐릭터명] 아이템을 캐릭터에게 양도합니다.'],
      ['cmd_attendance', '[%{cmd}] 하루 한 번 재화를 받습니다.'],
    ].freeze

    # 자동봇 [운영진 도움말] 줄
    SHOP_ADMIN_HELP = [
      ['cmd_money_add', '[%{cmd}/10/캐릭터명] 소지금을 더합니다. (캐릭터명은 쉼표로 여러 명, 또는 전원)'],
      ['cmd_money_sub', '[%{cmd}/10/캐릭터명] 소지금을 뺍니다.'],
      ['cmd_item_add', '[%{cmd}/사과: 2/캐릭터명] 소지품을 더합니다.'],
      ['cmd_item_sub', '[%{cmd}/사과: 1/캐릭터명] 소지품을 뺍니다.'],
      ['cmd_stat_change', '[힘 %{cmd}/+3/캐릭터명] 스탯을 바꿉니다. (캐릭터 관리 > 스탯)'],
    ].freeze

    SCHEMAS = { 'common' => COMMON, 'currency' => CURRENCY }.freeze

    # 관리 화면 묶음: [[묶음 이름, group 들], ...]. 키는 설정 키 또는 [설정 키, 화면]
    LAYOUT = {
      ['common', 'settings'] => [
        ['bots', %w(bots)],
        ['currency', %w(currency)],
        ['rules', %w(rules)],
      ],
      ['common', 'commands'] => [
        ['commands', %w(commands)],
        ['messages_match', %w(messages_match)],
        ['messages_invalid', %w(messages_invalid)],
        ['messages_score', %w(messages_score)],
        ['messages_gift', %w(messages_gift)],
      ],
      ['common', 'season'] => [
        ['season', %w(season)],
      ],
      # 컨텐츠 > 각 컨텐츠: 기본 / 룰 설정 / 보상 설정 / 명령어 설정 / 문구 설정 (점수는 설정 탭의 표)
      content_subject: [
        ['basic', %w(basic)],
        ['subject_rules', %w(rules time flavors spells roles)],
        ['rewards', %w(rewards)],
        ['subject_commands', %w(commands)],
        ['subject_messages', %w(messages)],
      ],
    }.freeze

    # 관리 화면에서 이 칸부터 새 줄에 놓는다 (기본 명령어: 수락·거절·기권 / 소속 점수 보기·내 전적 보기)
    ROW_STARTS = %w(cmd_points).freeze

    # 공통 설정의 화면들 (컨텐츠 설정의 '설정' / '명령어' 탭)
    COMMON_PAGES = %w(settings commands).freeze
  end
end
