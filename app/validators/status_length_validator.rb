# frozen_string_literal: true

class StatusLengthValidator < ActiveModel::Validator
  DEFAULT_MAX_CHARS = 1000
  MAX_CHARS_RANGE = (100..10_000)
  URL_PLACEHOLDER_CHARS = 23
  URL_PLACEHOLDER = 'x' * 23

  # 관리자 설정(서버 설정 > 커뮤니티 옵션)의 최대 글자수. 범위를 벗어나면 기본값을 쓴다.
  def self.max_chars
    value = Setting.status_max_characters.to_i
    MAX_CHARS_RANGE.cover?(value) ? value : DEFAULT_MAX_CHARS
  end

  # 최소 글자수 (서버 설정 > 운영). 0이면 끈다. 멘션(@아이디)과 띄어쓰기는 세지 않는다
  MIN_CHARS_RANGE = (0..1_000)

  def self.min_chars
    value = Setting.status_min_characters.to_i
    MIN_CHARS_RANGE.cover?(value) ? value : 0
  end

  # 글자수·퍼블툿 제한을 받지 않는 운영 계정: 관리자, 컨텐츠 설정의 운영진 아이디, 시스템 계정
  def self.exempt_account?(account)
    return true if account.nil?
    return true if account.id == Game::System.account&.id
    return true if GameCharacter.staff_usernames.include?(account.username.downcase)

    Game::Staff.web?(account.user)
  end

  def validate(status)
    return unless status.local? && !status.reblog?

    status.errors.add(:text, I18n.t('statuses.over_character_limit', max: self.class.max_chars)) if too_long?(status)
    status.errors.add(:text, I18n.t('statuses.under_character_limit', min: self.class.min_chars)) if too_short?(status)
  end

  private

  # 최소 글자수: 운영 계정(관리자·컨텐츠 설정의 운영진 아이디·시스템 계정), 사진·투표가 붙은 툿,
  # 명령어 툿(시스템·봇 계정을 멘션한 [컨텐츠·이벤트 명령어] 툿, 또는 [명령어]만 쓴 툿)은 뺀다
  def too_short?(status)
    min = self.class.min_chars
    return false if min.zero? || exempt_from_minimum?(status.account)
    return false if excluded_by_kind?(status)
    # 새 툿이나 글을 고칠 때만 (예전 짧은 툿의 다른 값을 바꿀 때 막히지 않게)
    return false unless status.new_record? || status.text_changed? || status.spoiler_text_changed?
    return false if status.media_attachments.any? || status.poll.present?
    return false if command_to_bot?(status.text.to_s)

    text = without_mentions(status.text.to_s)
    return false if command_only?(text)

    countable_length([status.spoiler_text, text].join.gsub(/\s+/, '')) < min
  end

  # 서버 설정 > 운영: [퍼블툿 제외] 답 툿이 아닌 툿(DM 제외)은 안 받는다 / [디엠 제외] DM 툿은 안 받는다
  def excluded_by_kind?(status)
    return Setting.status_min_exclude_dm if status.direct_visibility?

    Setting.status_min_exclude_public && status.in_reply_to_id.blank?
  end

  # 시스템 계정(컨텐츠·이벤트 명령어)이나 봇 계정(상점봇 등)을 멘션하고 [명령어]가 들어 있는 툿
  def command_to_bot?(str)
    return false unless str.match?(Game::Engine::COMMAND)

    names = Extractor.extract_mentions_or_lists_with_indices(str).filter_map { |entity| entity[:screen_name]&.split('@')&.first&.downcase }.uniq
    return false if names.empty?

    bots = [Game::System.account&.username&.downcase, *GameCharacter.staff_usernames].compact
    return true if names.intersect?(bots)

    Account.local.bots.exists?(['lower(username) IN (?)', names])
  end

  def exempt_from_minimum?(account)
    self.class.exempt_account?(account)
  end

  # 멘션만 지운 글 (명령어 판단·글자수 세기)
  def without_mentions(str)
    return '' if str.blank?

    entities = Extractor.extract_mentions_or_lists_with_indices(str)
    rewrite_entities(str, entities) { '' }
  end

  # [고발] · [예언/호그와트] 처럼 대괄호 명령어만 있는 툿
  def command_only?(text)
    text.match?(/\A\s*(\[[^\[\]\n]+\]\s*)+\z/)
  end

  def too_long?(status)
    countable_length(combined_text(status)) > self.class.max_chars
  end

  def countable_length(str)
    str.each_grapheme_cluster.size
  end

  def combined_text(status)
    [status.spoiler_text, countable_text(status.text)].join
  end

  def countable_text(str)
    return '' if str.blank?

    # To ensure that we only give length concessions to entities that
    # will be correctly parsed during formatting, we go through full
    # entity extraction

    entities = Extractor.remove_overlapping_entities(Extractor.extract_urls_with_indices(str, extract_url_without_protocol: false) + Extractor.extract_mentions_or_lists_with_indices(str))

    rewrite_entities(str, entities) do |entity|
      if entity[:url]
        URL_PLACEHOLDER
      elsif entity[:screen_name]
        "@#{entity[:screen_name].split('@').first}"
      end
    end
  end

  def rewrite_entities(str, entities)
    entities.sort_by! { |entity| entity[:indices].first }
    result = +''

    last_index = entities.reduce(0) do |index, entity|
      result << str[index...entity[:indices].first]
      result << yield(entity)
      entity[:indices].last
    end

    result << str[last_index..]
    result
  end
end
