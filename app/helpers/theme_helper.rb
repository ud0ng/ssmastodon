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

  COMMUNITY_THEME_DEFAULT_COLOR = '#4a5390'

  def community_theme_enabled?
    Setting.community_theme_enabled
  end

  # 커뮤니티 테마 (서버 설정 > 커뮤니티 옵션 > 테마)
  # 낮/밤 메인색(큰 박스·메뉴·비활성 색)과 서브색(포인트 버튼·링크), 배경 이미지를 CSS 변수로 넣고,
  # 그 변수를 쓰는 테마 스타일시트를 붙인다. 빈 칸은 이렇게 채운다.
  #   낮 서브색 ← 낮 메인색
  #   밤 메인색 ← 낮 메인색
  #   밤 서브색 ← 밤 메인색(없으면 낮 서브색)을 밝게 한 색 (어두운 박스 위에서 보이도록)
  def community_theme_tags
    return unless community_theme_enabled?

    colors = community_theme_colors
    declarations = colors.flat_map do |mode, (main, point)|
      [
        "--community-theme-main-#{mode}:#{main};",
        "--community-theme-point-#{mode}:#{point};",
        "--community-theme-on-point-#{mode}:#{community_theme_on_color(point)};",
      ]
    end

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

  def community_theme_colors
    main_light  = community_theme_color(Setting.community_theme_main_light) || COMMUNITY_THEME_DEFAULT_COLOR
    point_light = community_theme_color(Setting.community_theme_point_light) || main_light
    main_dark   = community_theme_color(Setting.community_theme_main_dark)
    point_dark  = community_theme_color(Setting.community_theme_point_dark) || community_theme_lighten(main_dark || point_light)

    { light: [main_light, point_light], dark: [main_dark || main_light, point_dark] }
  end

  def community_theme_color(value)
    value.downcase if value.to_s.match?(Form::AdminSettings::COMMUNITY_THEME_COLOR_FORMAT)
  end

  # 채도는 그대로 두고 밝기만 올린다. (흰색을 섞으면 탁해진다)
  def community_theme_lighten(hex, amount = 0.3)
    r, g, b = hex.delete_prefix('#').scan(/../).map { |pair| pair.to_i(16) / 255.0 }
    max, min = [r, g, b].minmax.reverse
    lightness = (max + min) / 2
    delta = max - min

    if delta.zero?
      hue = saturation = 0.0
    else
      saturation = lightness > 0.5 ? delta / (2 - max - min) : delta / (max + min)
      hue = case max
            when r then ((g - b) / delta) % 6
            when g then ((b - r) / delta) + 2
            else ((r - g) / delta) + 4
            end
      hue /= 6
    end

    lightness += (1 - lightness) * amount
    format('#%02x%02x%02x', *community_theme_hsl_to_rgb(hue, saturation, lightness))
  end

  def community_theme_hsl_to_rgb(hue, saturation, lightness)
    chroma = (1 - ((2 * lightness) - 1).abs) * saturation
    x = chroma * (1 - (((hue * 6) % 2) - 1).abs)
    m = lightness - (chroma / 2)
    r, g, b = [[chroma, x, 0], [x, chroma, 0], [0, chroma, x], [0, x, chroma], [x, 0, chroma], [chroma, 0, x]][(hue * 6).floor % 6]

    [r, g, b].map { |channel| ((channel + m) * 255).round }
  end

  # 서브색 위에 올라갈 글자색. 흰 글자가 충분히 읽히면(대비 3:1 이상) 흰색, 아니면 검은색.
  def community_theme_on_color(hex)
    channels = hex.delete_prefix('#').scan(/../).map do |pair|
      value = pair.to_i(16) / 255.0
      value <= 0.03928 ? value / 12.92 : ((value + 0.055) / 1.055)**2.4
    end
    luminance = (0.2126 * channels[0]) + (0.7152 * channels[1]) + (0.0722 * channels[2])

    1.05 / (luminance + 0.05) >= 3 ? '#ffffff' : '#14161a'
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
