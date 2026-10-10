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

  def validate(status)
    return unless status.local? && !status.reblog?

    status.errors.add(:text, I18n.t('statuses.over_character_limit', max: self.class.max_chars)) if too_long?(status)
  end

  private

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
