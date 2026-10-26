# frozen_string_literal: true

class Form::AdminSettings
  include ActiveModel::Model

  include AuthorizedFetchHelper

  KEYS = %i(
    site_contact_username
    site_contact_email
    site_title
    site_short_description
    site_extended_description
    site_terms
    registrations_mode
    closed_registrations_message
    timeline_preview
    bootstrap_timeline_accounts
    theme
    activity_api_enabled
    peers_api_enabled
    preview_sensitive_media
    custom_css
    profile_directory
    thumbnail
    mascot
    trends
    trends_as_landing_page
    trendable_by_default
    show_domain_blocks
    show_domain_blocks_rationale
    noindex
    require_invite_text
    media_cache_retention_period
    content_cache_retention_period
    backups_retention_period
    status_page_url
    captcha_enabled
    authorized_fetch
    app_icon
    favicon
    min_age
    wordmark_dark
    wordmark_light
    status_max_characters
    status_min_characters
    status_min_exclude_public
    status_min_exclude_dm
    status_search_enabled
    status_search_scope
    community_theme_enabled
    community_theme_main_light
    community_theme_point_light
    community_theme_main_dark
    community_theme_point_dark
    community_theme_post_button_main
    community_theme_box_border
    community_theme_compose_border
    community_theme_dm_input_border
    community_theme_dm_button_border
    community_theme_default
    community_theme_background_light
    community_theme_background_dark
    default_avatar
    default_header
    community_theme_paren_size
    bot_sheet_main_id
    bot_sheet_reservation_id
    bot_sheet_story_id
    bot_sheet_investigation_id
  ).concat(CommunityTheme.detail_keys, CommunityTheme.box_opacity_keys).freeze

  INTEGER_KEYS = %i(
    media_cache_retention_period
    content_cache_retention_period
    backups_retention_period
    min_age
    status_max_characters
    status_min_characters
  ).freeze

  BOOLEAN_KEYS = %i(
    status_min_exclude_public
    status_min_exclude_dm
    timeline_preview
    activity_api_enabled
    peers_api_enabled
    preview_sensitive_media
    profile_directory
    trends
    trends_as_landing_page
    trendable_by_default
    noindex
    require_invite_text
    captcha_enabled
    authorized_fetch
    status_search_enabled
    community_theme_enabled
    community_theme_post_button_main
    community_theme_box_border
    community_theme_compose_border
    community_theme_dm_input_border
    community_theme_dm_button_border
  ).freeze

  UPLOAD_KEYS = %i(
    thumbnail
    mascot
    app_icon
    favicon
    wordmark_dark
    wordmark_light
    community_theme_background_light
    community_theme_background_dark
    default_avatar
    default_header
  ).freeze

  DIGEST_KEYS = %i(
    custom_css
  ).freeze

  OVERRIDEN_SETTINGS = {
    authorized_fetch: :authorized_fetch_mode?,
  }.freeze

  DESCRIPTION_LIMIT = 200
  STATUS_SEARCH_SCOPES = %w(following all).freeze
  COMMUNITY_THEME_COLOR_FORMAT = /\A#\h{6}\z/

  attr_accessor(*KEYS)

  validates :registrations_mode, inclusion: { in: %w(open approved none) }, if: -> { defined?(@registrations_mode) }
  validates :site_contact_email, :site_contact_username, presence: true, if: -> { defined?(@site_contact_username) || defined?(@site_contact_email) }
  validates :site_contact_username, existing_username: true, if: -> { defined?(@site_contact_username) }
  validates :bootstrap_timeline_accounts, existing_username: { multiple: true }, if: -> { defined?(@bootstrap_timeline_accounts) }
  validates :show_domain_blocks, inclusion: { in: %w(disabled users all) }, if: -> { defined?(@show_domain_blocks) }
  validates :show_domain_blocks_rationale, inclusion: { in: %w(disabled users all) }, if: -> { defined?(@show_domain_blocks_rationale) }
  validates :media_cache_retention_period, :content_cache_retention_period, :backups_retention_period, numericality: { only_integer: true }, allow_blank: true, if: -> { defined?(@media_cache_retention_period) || defined?(@content_cache_retention_period) || defined?(@backups_retention_period) }
  validates :min_age, numericality: { only_integer: true }, allow_blank: true, if: -> { defined?(@min_age) }
  validates :status_max_characters, numericality: { only_integer: true, in: StatusLengthValidator::MAX_CHARS_RANGE }, if: -> { defined?(@status_max_characters) }
  validates :status_min_characters, numericality: { only_integer: true, in: StatusLengthValidator::MIN_CHARS_RANGE }, if: -> { defined?(@status_min_characters) }
  validates :status_search_scope, inclusion: { in: STATUS_SEARCH_SCOPES }, if: -> { defined?(@status_search_scope) }
  validates :community_theme_default, inclusion: { in: Themes::COMMUNITY_THEME_MODES }, if: -> { defined?(@community_theme_default) }
  validates :community_theme_main_light, :community_theme_point_light, :community_theme_main_dark, :community_theme_point_dark, format: { with: COMMUNITY_THEME_COLOR_FORMAT }, allow_blank: true
  validates(*CommunityTheme.detail_keys, format: { with: COMMUNITY_THEME_COLOR_FORMAT }, allow_blank: true)
  validates :community_theme_paren_size, numericality: { only_integer: true, in: CommunityTheme::PAREN_SIZE_RANGE }, allow_blank: true
  validates(*CommunityTheme.box_opacity_keys, numericality: { only_integer: true, in: CommunityTheme::BOX_OPACITY_RANGE }, allow_blank: true)
  validates :site_short_description, length: { maximum: DESCRIPTION_LIMIT }, if: -> { defined?(@site_short_description) }
  validates :status_page_url, url: true, allow_blank: true
  validate :validate_site_uploads

  KEYS.each do |key|
    define_method(key) do
      return instance_variable_get(:"@#{key}") if instance_variable_defined?(:"@#{key}")

      stored_value = if UPLOAD_KEYS.include?(key)
                       SiteUpload.where(var: key).first_or_initialize(var: key)
                     elsif OVERRIDEN_SETTINGS.include?(key)
                       public_send(OVERRIDEN_SETTINGS[key])
                     else
                       Setting.public_send(key)
                     end

      instance_variable_set(:"@#{key}", stored_value)
    end
  end

  UPLOAD_KEYS.each do |key|
    define_method(:"#{key}=") do |file|
      value = public_send(key)
      value.file = file
    rescue Mastodon::DimensionsValidationError => e
      errors.add(key.to_sym, e.message)
    end
  end

  def save
    # NOTE: Annoyingly, files are processed and can error out before
    # validations are called, and `valid?` clears errors…
    # So for now, return early if errors aren't empty.
    return false unless errors.empty? && valid?

    KEYS.each do |key|
      next unless instance_variable_defined?(:"@#{key}")

      cache_digest_value(key) if DIGEST_KEYS.include?(key)

      if UPLOAD_KEYS.include?(key)
        public_send(key).save
      else
        setting = Setting.where(var: key).first_or_initialize(var: key)
        setting.update(value: typecast_value(key, instance_variable_get(:"@#{key}")))
      end
    end
  end

  private

  def cache_digest_value(key)
    Rails.cache.delete(:"setting_digest_#{key}")

    key_value = instance_variable_get(:"@#{key}")
    if key_value.present?
      Rails.cache.write(
        :"setting_digest_#{key}",
        Digest::SHA256.hexdigest(key_value)
      )
    end
  end

  def typecast_value(key, value)
    if BOOLEAN_KEYS.include?(key)
      value == '1'
    elsif INTEGER_KEYS.include?(key)
      value.blank? ? value : Integer(value)
    else
      value
    end
  end

  def validate_site_uploads
    UPLOAD_KEYS.each do |key|
      next unless instance_variable_defined?(:"@#{key}")

      upload = instance_variable_get(:"@#{key}")
      next if upload.valid?

      upload.errors.each do |error|
        errors.import(error, attribute: key)
      end
    end
  end
end
