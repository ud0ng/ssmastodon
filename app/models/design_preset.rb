# frozen_string_literal: true

# 디자인 프리셋 (서버 설정 > 디자인 > 프리셋). 낮·밤 테마의 모든 설정(커뮤니티 테마 색 전부)과 로고·배경을 한 묶음으로 저장하고,
# 누르면(apply!) 디자인 설정이 모두 그 값으로 바뀐다.
#   theme_settings 설정 키 → 값 (SETTING_KEYS. 빈 값이면 자동 색)
#   images       로고·배경 (DesignPresetImage, 적용하면 SiteUpload 로 복사)
#   clear_images 이미지가 없을 때 적용하면 지울 것 (그 밖의 빈 이미지는 지금 것을 그대로 둔다)
class DesignPreset < ApplicationRecord
  SETTING_KEYS = (%w(
    community_theme_default
    community_theme_post_button_main
    community_theme_box_border
    community_theme_compose_border
    community_theme_dm_input_border
    community_theme_dm_button_border
    community_theme_main_light
    community_theme_point_light
    community_theme_main_dark
    community_theme_point_dark
    community_theme_paren_size
  ) + CommunityTheme.detail_keys.map(&:to_s) + CommunityTheme.box_opacity_keys.map(&:to_s)).freeze

  IMAGE_VARS = (SiteUpload::WORDMARK_VARS.reverse + SiteUpload::COMMUNITY_THEME_BACKGROUND_VARS).freeze

  # 기본 프리셋: 기숙사 테마 (배경은 db/seeds/design_presets/<key>_<light|dark>.jpg, 로고는 그대로 둔다)
  DEFAULTS = {
    'gryffindor' => {
      name: '그리핀도르',
      values: {
        'community_theme_main_light' => '#7f0909', 'community_theme_point_light' => '#b07d12',
        'community_theme_main_dark' => '#740001', 'community_theme_point_dark' => '#e8b939',
        'community_theme_bracket_light' => '#9c0b0b', 'community_theme_paren_light' => '#a8790f',
        'community_theme_bracket_dark' => '#ff8a7a', 'community_theme_paren_dark' => '#f0c75e',
      },
    },
    'hufflepuff' => {
      name: '후플푸프',
      values: {
        'community_theme_main_light' => '#c99a1e', 'community_theme_point_light' => '#2b2622',
        'community_theme_main_dark' => '#3a3128', 'community_theme_point_dark' => '#ecb939',
        'community_theme_bracket_light' => '#8a6200', 'community_theme_paren_light' => '#4a3f35',
        'community_theme_bracket_dark' => '#ffd34d', 'community_theme_paren_dark' => '#c9b79c',
      },
    },
    'slytherin' => {
      name: '슬리데린',
      values: {
        'community_theme_main_light' => '#1a472a', 'community_theme_point_light' => '#1f7a46',
        'community_theme_main_dark' => '#1a472a', 'community_theme_point_dark' => '#c0c8cc',
        'community_theme_bracket_light' => '#1a6b3a', 'community_theme_paren_light' => '#5d6d74',
        'community_theme_bracket_dark' => '#6fdc98', 'community_theme_paren_dark' => '#c0c8cc',
      },
    },
    'ravenclaw' => {
      name: '래번클로',
      values: {
        'community_theme_main_light' => '#0e1a40', 'community_theme_point_light' => '#9a5f22',
        'community_theme_main_dark' => '#1c2f6e', 'community_theme_point_dark' => '#e0a060',
        'community_theme_bracket_light' => '#1f3c9e', 'community_theme_paren_light' => '#946b2d',
        'community_theme_bracket_dark' => '#8fb0ff', 'community_theme_paren_dark' => '#e6b77e',
      },
    },
  }.freeze

  # 기본 프리셋의 켜기/끄기 (비워 두면 관리 화면 체크칸이 꺼진 것처럼 보인다)
  DEFAULT_SWITCHES = {
    'community_theme_default' => 'light', 'community_theme_post_button_main' => false,
    'community_theme_box_border' => true, 'community_theme_compose_border' => true,
    'community_theme_dm_input_border' => true, 'community_theme_dm_button_border' => true,
  }.freeze

  DEFAULT_IMAGES_DIR = Rails.root.join('db', 'seeds', 'design_presets')

  has_many :images, class_name: 'DesignPresetImage', inverse_of: :preset, dependent: :destroy

  validates :name, presence: true, length: { maximum: 30 }

  default_scope { order(:position, :id) }

  # 지금 디자인 설정 (설정 값 전부)
  def self.current_values
    SETTING_KEYS.index_with { |key| Setting.public_send(key) }
  end

  # 지금 디자인을 프리셋으로 (이미지도 복사, 지금 없는 이미지는 적용할 때 지운다)
  def self.capture!(name)
    transaction do
      create!(name: name, position: unscoped.maximum(:position).to_i + 1).tap(&:capture!)
    end
  end

  # 아직 없는 기본 프리셋을 더한다 (이름으로 확인, 20261027090300_seed_design_presets)
  def self.seed_defaults!
    existing = unscoped.pluck(:name)
    position = unscoped.maximum(:position).to_i
    DEFAULTS.each do |key, preset|
      next if existing.include?(preset[:name])

      position += 1
      record = create!(name: preset[:name], position: position, theme_settings: SETTING_KEYS.index_with { nil }.merge(DEFAULT_SWITCHES).merge(preset[:values]))
      %w(light dark).each do |mode|
        path = DEFAULT_IMAGES_DIR.join("#{key}_#{mode}.jpg")
        next unless path.exist?

        File.open(path) { |file| record.images.create!(var: "community_theme_background_#{mode}", file: file) }
      end
    end
  end

  # 지금 디자인으로 덮어쓰기
  def capture!
    transaction do
      images.destroy_all
      cleared = IMAGE_VARS.reject do |var|
        upload = SiteUpload.find_by(var: var)
        images.create!(var: var, file: upload.file) if upload&.file.present?
      end
      update!(theme_settings: self.class.current_values, clear_images: cleared)
    end
  end

  # 디자인 설정을 모두 이 프리셋 값으로
  def apply!
    transaction do
      SETTING_KEYS.each do |key|
        setting = Setting.where(var: key).first_or_initialize(var: key)
        setting.update!(value: theme_settings[key])
      end

      by_var = images.index_by(&:var)
      IMAGE_VARS.each do |var|
        if (image = by_var[var])
          upload = SiteUpload.where(var: var).first_or_initialize(var: var)
          upload.file = image.file
          upload.save!
        elsif clear_images.include?(var)
          SiteUpload.find_by(var: var)&.destroy!
        end
      end
    end
  end

  def image(var)
    images.find { |item| item.var == var }
  end

  # 카드 미리보기 (낮·밤): 바탕색·배경 이미지·색 [메인, 서브, 메뉴]. 정한 세부 색이 있으면 그 색
  def preview_panels
    theme = CommunityTheme.new(PresetSettings.new(theme_settings))
    CommunityTheme::MODES.map do |mode|
      palette = theme.auto_palette(mode).merge(theme.palette(mode))
      { background: palette['page'], image: image("community_theme_background_#{mode}")&.file&.url, colors: palette.values_at('main', 'point', 'nav') }
    end
  end

  # 지금 디자인 설정과 같은가 (빈 값은 같게 본다, 이미지는 보지 않는다)
  def current?(current_values)
    SETTING_KEYS.all? { |key| theme_settings[key].to_s == current_values[key].to_s }
  end

  # CommunityTheme 이 Setting 대신 읽을 값
  class PresetSettings
    def initialize(values)
      @values = values || {}
    end

    def method_missing(name, *)
      key = name.to_s
      key.start_with?('community_theme_') ? @values[key] : super
    end

    def respond_to_missing?(name, include_private = false)
      name.to_s.start_with?('community_theme_') || super
    end
  end
end
