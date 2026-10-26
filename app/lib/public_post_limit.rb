# frozen_string_literal: true

# 퍼블툿 제한 (서버 설정 > 운영 > 글쓰기): [간격]마다 [개수]개까지만 퍼블툿을 쓸 수 있다.
#   퍼블툿 = 답 툿이 아니고 DM 도 아닌 내 툿 (부스트 제외). 간격 0 이면 제한 없음. 간격 단위는 분·시간·일.
#   예: 3시간에 4개 → 지난 3시간 안에 퍼블툿을 4개 썼다면 5개째는 막히고, 가장 오래된 것이 3시간을 채울 때까지 남은 시간을 알려 준다.
#   운영 계정(관리자·컨텐츠 설정 운영진·시스템 계정)은 제한을 받지 않는다. 최소 글자수 제외 계정과 같다 (StatusLengthValidator.exempt_account?).
class PublicPostLimit
  UNITS = { 'minute' => 1.minute, 'hour' => 1.hour, 'day' => 1.day }.freeze

  class Error < Mastodon::ValidationError
    attr_reader :retry_after, :limit, :interval, :unit

    def initialize(message, retry_after:, limit:, interval:, unit:)
      super(message)
      @retry_after = retry_after
      @limit = limit
      @interval = interval
      @unit = unit
    end
  end

  class << self
    def interval
      Setting.status_public_limit_interval.to_i
    end

    def unit
      value = Setting.status_public_limit_unit.to_s
      UNITS.key?(value) ? value : 'hour'
    end

    def count
      Setting.status_public_limit_count.to_i
    end

    # 제한을 쓰는 중인가 (간격 0 이면 꺼짐)
    def enabled?
      interval.positive? && count.positive?
    end

    def window
      interval * UNITS.fetch(unit)
    end

    # 이 툿이 퍼블툿인가 (제한을 받는 종류)
    def public_post?(visibility, in_reply_to)
      in_reply_to.blank? && visibility.to_s != 'direct'
    end

    # 퍼블툿을 쓰기 전에 부른다. 제한에 걸리면 PublicPostLimit::Error (남은 초 포함)
    def check!(account, visibility:, in_reply_to:)
      return unless enabled?
      return unless public_post?(visibility, in_reply_to)
      return if account.nil? || StatusLengthValidator.exempt_account?(account)

      # 툿마다 전부 세지 않는다: 창 안 퍼블툿 중 가장 최근 [개수]개만 인덱스(계정, 툿 번호) 범위로 읽는다.
      # [개수]번째로 최근인 툿이 아직 창 안이면 막고, 그 툿이 창 밖으로 나갈 때까지가 남은 시간이다.
      now = Time.current
      times = account.statuses.where(in_reply_to_id: nil, reblog_of_id: nil).where.not(visibility: :direct)
                     .where('statuses.id > ?', Mastodon::Snowflake.id_at(now - window, with_random: false))
                     .reorder(id: :desc).limit(count).pluck(:created_at)
      return if times.size < count

      retry_after = [(times.last + window - now).ceil, 1].max
      raise Error.new(I18n.t('statuses.public_limit', count: count, interval: interval_text, remaining: remaining_text(retry_after)),
                      retry_after: retry_after, limit: count, interval: interval, unit: unit)
    end

    def interval_text
      I18n.t("statuses.public_limit_units.#{unit}", count: interval)
    end

    def remaining_text(seconds)
      hours, rest = seconds.divmod(3600)
      minutes, secs = rest.divmod(60)
      hours.positive? ? format('%<h>d:%<m>02d:%<s>02d', h: hours, m: minutes, s: secs) : format('%<m>02d:%<s>02d', m: minutes, s: secs)
    end
  end
end
