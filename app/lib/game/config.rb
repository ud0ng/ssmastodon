# frozen_string_literal: true

# 게임 설정 (관리 > 게임 설정). 항목마다 기본값이 있고, 운영진이 바꾼 값만 game_configs 에 저장한다.
#
# 항목 종류: string(한 줄), integer, boolean, lines(줄마다 하나 → 배열), text(여러 줄 문구)
# 문구에는 %{이름} 자리표시와 {이가}{을를}{은는}{과와}{으로로}{아야} 조사를 쓸 수 있다.
module Game
  class Config
    Field = Struct.new(:key, :type, :default, :label, :hint, :group, keyword_init: true)

    TYPES = %i(string integer boolean lines text).freeze

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
        SCHEMAS.fetch(key) { Game::Kinds.fetch(key).schema }
      end

      def keys
        SCHEMAS.keys + Game::Kinds.keys
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
        else value.to_s.strip
        end
      end
    end

    # 게임 공통 (명령어·시간·점수 규칙·공통 문구)
    COMMON = [
      Field.new(key: 'system_username', type: :string, default: 'system', group: 'account',
                label: '시스템 계정 아이디', hint: '게임을 진행하는 계정. 이 계정을 멘션한 툿의 [명령어]를 처리합니다.'),

      Field.new(key: 'cmd_accept', type: :string, default: '수락', group: 'commands', label: '수락'),
      Field.new(key: 'cmd_decline', type: :string, default: '거절', group: 'commands', label: '거절'),
      Field.new(key: 'cmd_forfeit', type: :string, default: '기권', group: 'commands', label: '기권'),
      Field.new(key: 'cmd_points', type: :string, default: '점수', group: 'commands', label: '기숙사 점수'),
      Field.new(key: 'cmd_record', type: :string, default: '내전적', group: 'commands', label: '내 전적'),

      Field.new(key: 'invite_minutes', type: :integer, default: 10, group: 'time', label: '수락 대기 (분)', hint: '응답이 없으면 신청 취소'),
      Field.new(key: 'turn_minutes', type: :integer, default: 5, group: 'time', label: '한 턴 대기 (분)', hint: '시간이 지나면 그 턴 패배 처리'),

      Field.new(key: 'one_game_per_person', type: :boolean, default: true, group: 'rules', label: '한 사람당 진행 중인 게임 1개'),
      Field.new(key: 'daily_pair_limit', type: :integer, default: 3, group: 'rules', label: '같은 상대 하루 점수 지급 횟수', hint: '0 = 제한 없음'),
      Field.new(key: 'same_house_percent', type: :integer, default: 50, group: 'rules', label: '같은 기숙사끼리 점수 (%)'),

      Field.new(key: 'msg_invite', type: :text, group: 'messages', label: '신청',
                default: "%{opponent}, %{player}{이가} %{game}{을를} 신청했습니다!\n[%{accept}] 또는 [%{decline}]로 답해 주세요. (%{minutes}분 안에)"),
      Field.new(key: 'msg_declined', type: :text, group: 'messages', label: '거절', default: '%{player}{이가} 신청을 거절했습니다.'),
      Field.new(key: 'msg_expired', type: :text, group: 'messages', label: '수락 시간 초과', default: '%{minutes}분 동안 응답이 없어 %{game} 신청이 취소되었습니다.'),
      Field.new(key: 'msg_forfeit', type: :text, group: 'messages', label: '기권', default: '%{player}{이가} 기권했습니다. %{winner}의 승리!'),
      Field.new(key: 'msg_busy', type: :text, group: 'messages', label: '이미 진행 중', default: '%{player}{은는} 이미 진행 중인 게임이 있습니다.'),
      Field.new(key: 'msg_one_opponent', type: :text, group: 'messages', label: '상대가 여러 명', default: '%{game}{은는} 1:1로만 할 수 있습니다. 상대를 한 명만 태그해 주세요.'),
      Field.new(key: 'msg_no_opponent', type: :text, group: 'messages', label: '상대 없음', default: '%{game}{을를} 함께할 상대를 태그해 주세요.'),
      Field.new(key: 'msg_disabled', type: :text, group: 'messages', label: '꺼진 게임', default: '%{game}{은는} 지금 열려 있지 않습니다.'),
      Field.new(key: 'msg_points', type: :text, group: 'messages', label: '점수 지급', default: '%{emoji} %{house} +%{amount}점! (%{player})'),
      Field.new(key: 'msg_no_house', type: :text, group: 'messages', label: '기숙사 없음', default: '%{player}{은는} 아직 기숙사가 없어 점수를 받지 못했습니다.'),
      Field.new(key: 'msg_board', type: :text, group: 'messages', label: '[점수] 머리말', default: '🏆 기숙사 점수'),
      Field.new(key: 'msg_record', type: :text, group: 'messages', label: '[내전적]', default: '%{player}의 전적: %{win}승 %{lose}패 %{draw}무'),
    ].freeze

    SCHEMAS = { 'common' => COMMON }.freeze
  end
end
