# frozen_string_literal: true

# Elasticsearch 없이 PostgreSQL 로 툿 본문을 검색한다. (서버 설정 > 커뮤니티 옵션)
# 소규모 폐쇄형 서버를 위한 방식이라 본문·CW 를 ILIKE 부분 일치로 찾는다.
#
# 검색 대상(볼 권한이 있는 툿만):
#   - 내 툿, 나를 멘션한 툿, 내가 좋아요·북마크한 툿
#   - 팔로우 중인 계정의 공개·조용한 공개·팔로워 공개 툿
#   - 검색 범위가 '서버 전체'면 모든 계정의 공개·조용한 공개 툿
#
# 지원하는 검색 문법: 단어, "구문", -제외, from:, before:, after:, during:,
# has:media/poll/embed, is:reply/sensitive, language:, in:library/public
class DatabaseStatusesSearchService < BaseService
  def call(query, account, options = {})
    @query   = query.to_s.strip
    @account = account
    @options = options
    @limit   = options[:limit].to_i
    @offset  = options[:offset].to_i

    return [] if @query.blank? || @account.nil?

    results = search_scope.preload(:account).reorder(id: :desc).limit(@limit).offset(@offset).to_a

    account_ids         = results.map(&:account_id)
    account_domains     = results.map(&:account_domain)
    preloaded_relations = @account.relations_map(account_ids, account_domains)

    results.reject { |status| StatusFilter.new(status, @account, preloaded_relations).filtered? }
  rescue Parslet::ParseFailed, Date::Error, ArgumentError => e
    Rails.logger.warn "Database search failed: #{e.message}"
    []
  end

  private

  def search_scope
    conditions = clauses # in: 플래그가 visible_scope 보다 먼저 읽혀야 한다

    scope = visible_scope.where(reblog_of_id: nil)
    scope = scope.where(account_id: @options[:account_id]) if @options[:account_id].present?
    scope = scope.where(statuses[:id].gt(@options[:min_id].to_i)) if @options[:min_id].present?
    scope = scope.where(statuses[:id].lt(@options[:max_id].to_i)) if @options[:max_id].present?

    conditions.each do |operator, condition|
      scope = operator == '-' ? scope.where(condition.not) : scope.where(condition)
    end

    scope
  end

  def visible_scope
    library = Status.where(account_id: @account.id)
                    .or(Status.where(id: Mention.where(account_id: @account.id).select(:status_id)))
                    .or(Status.where(id: Favourite.where(account_id: @account.id).select(:status_id)))
                    .or(Status.where(id: Bookmark.where(account_id: @account.id).select(:status_id)))

    return library if @in_flag == 'library'

    followed = Status.where(account_id: Follow.where(account_id: @account.id).select(:target_account_id), visibility: %i(public unlisted private))
    scope = library.or(followed)
    scope = scope.or(Status.where(visibility: %i(public unlisted))) if search_all?
    scope = scope.where(visibility: %i(public unlisted)) if @in_flag == 'public'
    scope
  end

  def search_all?
    Setting.status_search_scope == 'all'
  end

  # [[operator, Arel 조건], ...] — 조건이 없는 절(in:, 알 수 없는 has: 등)은 빠진다.
  def clauses
    @clauses ||= begin
      tree = SearchQueryParser.new.parse(@query)
      nodes = tree.is_a?(Hash) ? Array(tree[:query]) : []

      nodes.filter_map do |node|
        clause = node[:clause]
        next if clause.nil?

        operator = clause[:operator]&.to_s
        prefix   = clause[:prefix].is_a?(Hash) ? clause[:prefix][:term].to_s.downcase : nil
        term     = clause_term(clause)

        condition = prefix ? prefix_condition(prefix, term) : text_condition(term)
        [operator, condition] if condition
      end
    end
  end

  def clause_term(clause)
    if clause[:phrase]
      Array(clause[:phrase]).map { |part| part[:term].to_s }.join(' ')
    elsif clause[:shortcode]
      ":#{clause[:shortcode][:term]}:"
    else
      clause[:term].to_s
    end
  end

  def prefix_condition(prefix, term)
    case prefix
    when 'from'
      statuses[:account_id].eq(account_id_from_term(term))
    when 'before'
      statuses[:created_at].lt(time_from_term(term))
    when 'after'
      statuses[:created_at].gt(time_from_term(term).end_of_day)
    when 'during'
      time = time_from_term(term)
      statuses[:created_at].between(time..time.end_of_day)
    when 'language'
      statuses[:language].eq(term.downcase)
    when 'has'
      has_condition(term.downcase)
    when 'is'
      is_condition(term.downcase)
    when 'in'
      @in_flag = term.downcase
      nil
    else
      text_condition("#{prefix}:#{term}")
    end
  end

  def has_condition(term)
    case term
    when 'media'
      statuses[:id].in(MediaAttachment.where.not(status_id: nil).select(:status_id).arel)
    when 'poll'
      statuses[:poll_id].not_eq(nil)
    when 'embed', 'link'
      statuses[:id].in(PreviewCardsStatus.select(:status_id).arel)
    end
  end

  def is_condition(term)
    case term
    when 'reply'
      statuses[:in_reply_to_id].not_eq(nil)
    when 'sensitive'
      statuses[:sensitive].eq(true)
    end
  end

  def text_condition(term)
    return if term.blank?

    pattern = "%#{ActiveRecord::Base.sanitize_sql_like(term)}%"
    statuses[:text].matches(pattern).or(statuses[:spoiler_text].matches(pattern))
  end

  def account_id_from_term(term)
    return @account.id if term == 'me'

    username, domain = term.delete_prefix('@').split('@')
    domain = nil if TagManager.instance.local_domain?(domain)
    Account.find_remote(username, domain)&.id || -1
  end

  def time_from_term(term)
    return Time.zone.at(term.to_i / 1000.0) if term.match?(/\A\d+\z/)
    return Time.iso8601(term) if term.include?('T')

    date = Date.iso8601(term)
    time_zone.local(date.year, date.month, date.day)
  end

  def time_zone
    ActiveSupport::TimeZone[@account.user&.time_zone.presence || 'UTC'] || ActiveSupport::TimeZone['UTC']
  end

  def statuses
    Status.arel_table
  end
end
