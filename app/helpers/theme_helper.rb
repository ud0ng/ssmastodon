# frozen_string_literal: true

module ThemeHelper
  def theme_style_tags(theme)
    if theme == 'system'
      ''.html_safe.tap do |tags|
        tags << vite_stylesheet_tag('styles/mastodon-light.scss', media: 'not all and (prefers-color-scheme: dark)', crossorigin: 'anonymous')
        tags << vite_stylesheet_tag('styles/application.scss', media: '(prefers-color-scheme: dark)', crossorigin: 'anonymous')
      end
    elsif theme == 'default'
      vite_stylesheet_tag 'styles/application.scss', media: 'all', crossorigin: 'anonymous'
    else
      vite_stylesheet_tag "styles/#{theme}.scss", media: 'all', crossorigin: 'anonymous'
    end
  end

  def theme_color_tags(theme)
    if theme == 'system'
      ''.html_safe.tap do |tags|
        tags << tag.meta(name: 'theme-color', content: Themes::THEME_COLORS[:dark], media: '(prefers-color-scheme: dark)')
        tags << tag.meta(name: 'theme-color', content: Themes::THEME_COLORS[:light], media: '(prefers-color-scheme: light)')
      end
    else
      tag.meta name: 'theme-color', content: theme_color_for(theme)
    end
  end

  def custom_stylesheet
    if active_custom_stylesheet.present?
      stylesheet_link_tag(
        custom_css_path(active_custom_stylesheet),
        host: root_url,
        media: :all,
        skip_pipeline: true
      )
    end
  end

  def custom_wordmark_tag
    declarations = SiteUpload::WORDMARK_VARS.filter_map do |var|
      upload = InstancePresenter.new.public_send(var)
      next if upload.blank?

      "--lw-#{var.dasherize}:url(\"#{css_string_escape(upload.file.url)}\");"
    end
    return if declarations.empty?

    tag.style(":root{#{declarations.join}}".html_safe) # rubocop:disable Rails/OutputSafety
  end

  COMMUNITY_THEME_DEFAULT_COLOR = '#1d9bf0'

  def community_theme_enabled?
    Setting.community_theme_enabled
  end

  # 커뮤니티 테마 (서버 설정 > 커뮤니티 옵션 > 테마)
  # 낮/밤 테마색·배경 이미지를 CSS 변수로 넣고, 그 변수를 쓰는 테마 스타일시트를 붙인다.
  # 밤 테마색을 비워두면 낮 테마색을 그대로 쓴다.
  def community_theme_tags
    return unless community_theme_enabled?

    light = community_theme_color(Setting.community_theme_color_light) || COMMUNITY_THEME_DEFAULT_COLOR
    dark  = community_theme_color(Setting.community_theme_color_dark) || light

    declarations = [
      "--community-theme-accent-light:#{light};",
      "--community-theme-accent-dark:#{dark};",
      "--community-theme-on-accent-light:#{community_theme_on_color(light)};",
      "--community-theme-on-accent-dark:#{community_theme_on_color(dark)};",
    ]

    %w(light dark).each do |mode|
      upload = InstancePresenter.new.public_send(:"community_theme_background_#{mode}")
      declarations << "--community-theme-background-#{mode}:url(\"#{css_string_escape(upload.file.url)}\");" if upload.present?
    end

    safe_join([
      tag.style(":root{#{declarations.join}}".html_safe), # rubocop:disable Rails/OutputSafety
      vite_stylesheet_tag('styles/entrypoints/community_theme.scss', media: 'all', crossorigin: 'anonymous'),
    ])
  end

  private

  def community_theme_color(value)
    value if value.to_s.match?(Form::AdminSettings::COMMUNITY_THEME_COLOR_FORMAT)
  end

  # 테마색 위에 올라갈 글자색. 흰색과 검은색 중 대비가 더 큰 쪽을 고른다.
  def community_theme_on_color(hex)
    channels = hex.delete_prefix('#').scan(/../).map do |pair|
      value = pair.to_i(16) / 255.0
      value <= 0.03928 ? value / 12.92 : ((value + 0.055) / 1.055)**2.4
    end
    luminance = (0.2126 * channels[0]) + (0.7152 * channels[1]) + (0.0722 * channels[2])

    (luminance + 0.05) / 0.05 > 1.05 / (luminance + 0.05) ? '#14161a' : '#ffffff'
  end

  def css_string_escape(value)
    value.to_s.gsub(%r{[^A-Za-z0-9\-._~:/?@!$&'()*+,;=%\[\]#]}) { |char| "\\#{char.ord.to_s(16)} " }
  end

  def active_custom_stylesheet
    if cached_custom_css_digest.present?
      [:custom, cached_custom_css_digest.to_s.first(8)]
        .compact_blank
        .join('-')
    end
  end

  def cached_custom_css_digest
    Rails.cache.fetch(:setting_digest_custom_css) do
      Setting.custom_css&.then { |content| Digest::SHA256.hexdigest(content) }
    end
  end

  def theme_color_for(theme)
    theme == 'mastodon-light' ? Themes::THEME_COLORS[:light] : Themes::THEME_COLORS[:dark]
  end
end
