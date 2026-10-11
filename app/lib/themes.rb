# frozen_string_literal: true

require 'singleton'
require 'yaml'

class Themes
  include Singleton

  THEME_COLORS = {
    dark: '#181820',
    light: '#ffffff',
  }.freeze

  # 커뮤니티 테마 (서버 설정 > 커뮤니티 옵션). 켜져 있을 때만 목록에 나오고,
  # 꺼지면 이 테마를 고른 사람은 같은 밝기의 유사 트위터 테마로 보인다.
  COMMUNITY_THEMES = {
    'community-light' => 'mastodon-bird-ui-light',
    'community-dark' => 'mastodon-bird-ui-dark',
  }.freeze

  COMMUNITY_THEME_MODES = %w(light dark).freeze

  def initialize
    @conf = YAML.load_file(Rails.root.join('config', 'themes.yml'))
  end

  # 지금 고를 수 있는 테마
  def names
    community_enabled? ? @conf.keys : base_names
  end

  # 커뮤니티 테마를 뺀 테마 (서버 기본 테마 목록)
  def base_names
    @conf.keys - COMMUNITY_THEMES.keys
  end

  def community?(theme)
    COMMUNITY_THEMES.key?(theme)
  end

  # 테마를 고르지 않은 사람(새로 가입한 사람, 로그인 안 한 사람)의 테마
  def default
    return "community-#{community_default_mode}" if community_enabled?

    ::Setting.theme
  end

  # 사용자가 고른 테마를 지금 쓸 수 있는 테마로 바꾼다.
  def resolve(theme)
    return theme if names.include?(theme)
    return COMMUNITY_THEMES[theme] if community?(theme)

    default
  end

  private

  def community_enabled?
    ::Setting.community_theme_enabled
  end

  def community_default_mode
    COMMUNITY_THEME_MODES.include?(::Setting.community_theme_default) ? ::Setting.community_theme_default : 'light'
  end
end
