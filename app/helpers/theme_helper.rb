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

  COMMUNITY_THEME_DEFAULT_COLOR = CommunityTheme::DEFAULT_COLOR

  def community_theme_enabled?
    Setting.community_theme_enabled
  end

  def community_theme_active?(theme)
    community_theme_enabled? && Themes.instance.community?(theme)
  end

  # 커뮤니티 테마 (서버 설정 > 커뮤니티 테마)
  # 낮/밤 색(CommunityTheme 이 메인/서브색과 세부 색으로 만든 것)과 배경 이미지를 CSS 변수로 넣고,
  # 그 변수를 쓰는 테마 스타일시트를 붙인다.
  def community_theme_tags(theme)
    return unless community_theme_active?(theme)

    community_theme = CommunityTheme.new
    declarations = CommunityTheme::MODES.flat_map do |mode|
      community_theme.palette(mode).map do |item, value|
        value = "#{value}%" if item == 'box_opacity'
        "--community-theme-#{item.dasherize}-#{mode}:#{value};"
      end
    end

    CommunityTheme::MODES.each do |mode|
      upload = InstancePresenter.new.public_send(:"community_theme_background_#{mode}")
      declarations << "--community-theme-background-#{mode}:url(\"#{css_string_escape(upload.file.url)}\");" if upload.present?
    end

    safe_join([
      tag.style(":root{#{declarations.join}}".html_safe), # rubocop:disable Rails/OutputSafety
      vite_stylesheet_tag('styles/entrypoints/community_theme.scss', media: 'all', crossorigin: 'anonymous'),
    ])
  end

  private

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
    %w(mastodon-light community-light).include?(theme) ? Themes::THEME_COLORS[:light] : Themes::THEME_COLORS[:dark]
  end
end
