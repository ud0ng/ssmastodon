# frozen_string_literal: true

# 커뮤니티 테마 (서버 설정 > 커뮤니티 테마) 의 낮/밤 색 묶음.
#
# 기본은 메인색·서브색 두 가지로 나머지 색을 자동으로 만들고, 세부 색을 정하면 그 색을 쓴다.
#   메인색: 박스·메뉴·아이콘·아이디/시간 같은 바탕 색
#   서브색: 게시 버튼·링크·해시태그·보낸 채팅 같은 포인트 색
#
# 빈 메인/서브색은 이렇게 채운다.
#   낮 서브색 ← 낮 메인색
#   밤 메인색 ← 낮 메인색
#   밤 서브색 ← 밤 메인색(없으면 낮 서브색)을 밝게 한 색 (어두운 박스 위에서 보이도록)
class CommunityTheme
  MODES = %w(light dark).freeze
  DEFAULT_COLOR = '#4a5390'
  COLOR_FORMAT = /\A#\h{6}\z/

  # 세부 색 (설정 키: community_theme_<항목>_<light|dark>)
  DETAILS = %w(
    page
    box
    compose
    selected
    hover
    border
    text
    nav
    nav_hover
    dim
    dim_hover
    link_hover
    on_point
    post_button
    post_button_text
  ).freeze

  DEFAULT_BOX_OPACITY = 92
  BOX_OPACITY_RANGE = (0..100)

  def self.detail_keys
    MODES.flat_map { |mode| DETAILS.map { |item| :"community_theme_#{item}_#{mode}" } }
  end

  def self.box_opacity_keys
    MODES.map { |mode| :"community_theme_box_opacity_#{mode}" }
  end

  def initialize(settings = ::Setting)
    @settings = settings
  end

  # 자동 색이 반투명이라 CSS 가 직접 만드는 항목 (정했을 때만 넘긴다)
  CSS_DERIVED = %w(hover).freeze

  # 화면에 쓰는 색: 정한 세부 색 > 자동 색
  def palette(mode)
    auto = auto_palette(mode).except(*CSS_DERIVED)
    overrides = DETAILS.index_with { |item| color(setting("#{item}_#{mode}")) }.compact
    auto.merge(overrides).merge('box_opacity' => box_opacity(mode))
  end

  # 세부 색을 비워 뒀을 때의 색 (관리 화면에서 빈칸 옆에 보여 준다)
  def auto_palette(mode)
    main, point = base_colors.fetch(mode.to_sym)
    post_main = setting('post_button_main') == true || setting('post_button_main').to_s == '1'

    colors = mode.to_s == 'dark' ? dark_palette(main) : light_palette(main)
    colors['main'] = main
    colors['point'] = point
    colors['on_point'] = on_color(point)
    colors['nav_hover'] = point
    colors['link_hover'] = mode.to_s == 'dark' ? mix(point, 75, '#ffffff') : mix(point, 75, '#000000')
    colors['post_button'] = post_main ? colors['nav'] : point
    colors['post_button_text'] = on_color(colors['post_button'])
    colors
  end

  def base_colors
    main_light  = color(setting('main_light')) || DEFAULT_COLOR
    point_light = color(setting('point_light')) || main_light
    main_dark   = color(setting('main_dark'))
    point_dark  = color(setting('point_dark')) || lighten(main_dark || point_light)

    { light: [main_light, point_light], dark: [main_dark || main_light, point_dark] }
  end

  def box_opacity(mode)
    value = setting("box_opacity_#{mode}")
    return DEFAULT_BOX_OPACITY if value.blank?

    value.to_i.clamp(BOX_OPACITY_RANGE.min, BOX_OPACITY_RANGE.max)
  end

  def color(value)
    value.to_s.downcase if value.to_s.match?(COLOR_FORMAT)
  end

  # a 를 percent% 섞는다 (CSS color-mix(in srgb, a percent%, b) 와 같다)
  def mix(first, percent, second)
    weight = percent / 100.0
    first_rgb = rgb(first)
    second_rgb = rgb(second)
    hex(first_rgb.zip(second_rgb).map { |a, b| (a * weight) + (b * (1 - weight)) })
  end

  # 채도는 그대로 두고 밝기만 올린다. (흰색을 섞으면 탁해진다)
  def lighten(value, amount = 0.3)
    r, g, b = rgb(value).map { |channel| channel / 255.0 }
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
    hex(hsl_to_rgb(hue, saturation, lightness))
  end

  # 색 위에 올라갈 글자색. 흰 글자가 충분히 읽히면(대비 3:1 이상) 흰색, 아니면 검은색.
  def on_color(value)
    channels = rgb(value).map do |channel|
      channel /= 255.0
      channel <= 0.03928 ? channel / 12.92 : ((channel + 0.055) / 1.055)**2.4
    end
    luminance = (0.2126 * channels[0]) + (0.7152 * channels[1]) + (0.0722 * channels[2])

    1.05 / (luminance + 0.05) >= 3 ? '#ffffff' : '#14161a'
  end

  private

  # 낮: 메인색이 살짝 섞인 흰 박스 + 검은 글자, 메뉴는 진한 메인색, 비활성 색은 연한 메인색
  def light_palette(main)
    box = mix(main, 5, '#ffffff')
    nav = mix(main, 80, '#14161a')

    {
      'page' => box,
      'box' => box,
      'compose' => box,
      'selected' => mix(main, 10, '#ffffff'),
      'hover' => mix(mix(main, 8, '#14161a'), 5, box),
      'border' => mix(main, 22, '#ffffff'),
      'text' => mix(main, 8, '#14161a'),
      'nav' => nav,
      'dim' => mix(main, 50, '#ffffff'),
      'dim_hover' => nav,
    }
  end

  # 밤: 메인색을 깊게 어둡게 한 박스 + 흰 글자, 메뉴는 흰빛 메인색, 비활성 색은 탁한 메인색
  def dark_palette(main)
    box = mix(main, 28, '#0a0b10')
    text = mix(main, 6, '#f4f5f8')

    {
      'page' => box,
      'box' => box,
      'compose' => mix(main, 36, '#0d0e14'),
      'selected' => mix(main, 45, '#121318'),
      'hover' => mix('#ffffff', 6, box),
      'border' => mix(mix(main, 40, '#ffffff'), 16, box),
      'text' => text,
      'nav' => mix(main, 12, '#ffffff'),
      'dim' => mix(main, 40, '#b9bcc8'),
      'dim_hover' => text,
    }
  end

  def setting(name)
    @settings.public_send(:"community_theme_#{name}")
  end

  def rgb(value)
    value.delete_prefix('#').scan(/../).map { |pair| pair.to_i(16) }
  end

  def hex(channels)
    format('#%02x%02x%02x', *channels.map { |channel| channel.round.clamp(0, 255) })
  end

  def hsl_to_rgb(hue, saturation, lightness)
    chroma = (1 - ((2 * lightness) - 1).abs) * saturation
    x = chroma * (1 - (((hue * 6) % 2) - 1).abs)
    m = lightness - (chroma / 2)
    r, g, b = [[chroma, x, 0], [x, chroma, 0], [0, chroma, x], [0, x, chroma], [x, 0, chroma], [chroma, 0, x]][(hue * 6).floor % 6]

    [r, g, b].map { |channel| (channel + m) * 255 }
  end
end
