# frozen_string_literal: true

module BrandingHelper
  def logo_as_symbol(version = :icon)
    case version
    when :icon
      _logo_as_symbol_icon
    when :wordmark
      _logo_as_symbol_wordmark
    end
  end

  def _logo_as_symbol_wordmark
    content_tag(:img, nil, src: frontend_asset_path('images/logos/wordmark_dark.png'), class: 'logo logo--wordmark')  end

  def _logo_as_symbol_icon
    content_tag(:img, nil, src: frontend_asset_path('images/logos/logo_dark.png'), class: 'logo logo--icon')
  end

  def render_logo
    content_tag(:img, nil, src: frontend_asset_path('images/logos/logo_dark.png'), alt: 'Mastodon', class: 'logo logo--icon')
  end

  # 밝은 배경을 쓰는 테마 (낮 로고 = 라이트 테마용 워드마크)
  LIGHT_THEMES = %w(mastodon-light mastodon-bird-ui-light community-light).freeze

  # 테마에 맞는 로고 (디자인 탭의 낮/밤 로고, 없으면 기본 워드마크). 시스템 테마는 기기 설정을 따른다.
  def render_themed_wordmark(theme, css_class)
    alt = Setting.site_title.presence || 'Mastodon'
    return image_tag(themed_wordmark_url(:light), alt: alt, class: css_class) if LIGHT_THEMES.include?(theme)
    return image_tag(themed_wordmark_url(:dark), alt: alt, class: css_class) unless theme == 'system'

    content_tag(:picture) do
      tag.source(srcset: themed_wordmark_url(:dark), media: '(prefers-color-scheme: dark)') +
        image_tag(themed_wordmark_url(:light), alt: alt, class: css_class)
    end
  end

  def themed_wordmark_url(variant)
    upload = InstancePresenter.new.public_send(:"wordmark_#{variant}")
    upload.present? ? upload.file.url : frontend_asset_path("images/logos/wordmark_#{variant}.png")
  end

  def render_symbol(version = :icon)
    path = case version
           when :icon
             'logo-symbol-icon.svg'
           when :wordmark
             'logo-symbol-wordmark.svg'
           end

    render(file: Rails.root.join('app', 'javascript', 'images', path)).html_safe # rubocop:disable Rails/OutputSafety
  end
end
