# frozen_string_literal: true

require 'rails_helper'

# 디자인 프리셋: 지금 디자인 저장 → 바꾼 뒤 적용하면 색·로고·배경이 모두 돌아온다, 기본 기숙사 프리셋
RSpec.describe DesignPreset do
  def wordmark
    Rack::Test::UploadedFile.new(Rails.root.join('spec', 'fixtures', 'files', 'wordmark.png'), 'image/png')
  end

  it 'captures every design setting and image, then applies them back' do
    Setting.community_theme_main_light = '#112233'
    Setting.community_theme_point_dark = '#abcdef'
    Setting.community_theme_bracket_light = '#445566'
    Setting.community_theme_box_border = false
    SiteUpload.create!(var: 'wordmark_light', file: wordmark)

    preset = described_class.capture!('내 디자인')
    expect(preset.theme_settings).to include('community_theme_main_light' => '#112233', 'community_theme_point_dark' => '#abcdef', 'community_theme_box_border' => false)
    expect(preset.images.pluck(:var)).to eq ['wordmark_light']
    expect(preset.clear_images).to contain_exactly('wordmark_dark', 'community_theme_background_light', 'community_theme_background_dark')
    expect(preset.current?(described_class.current_values)).to be true

    Setting.community_theme_main_light = '#999999'
    Setting.community_theme_bracket_light = nil
    Setting.community_theme_box_border = true
    SiteUpload.find_by(var: 'wordmark_light').destroy!
    SiteUpload.create!(var: 'wordmark_dark', file: wordmark)
    expect(preset.current?(described_class.current_values)).to be false

    preset.apply!

    expect(Setting.community_theme_main_light).to eq '#112233'
    expect(Setting.community_theme_bracket_light).to eq '#445566'
    expect(Setting.community_theme_box_border).to be false
    expect(SiteUpload.find_by(var: 'wordmark_light').file).to be_present
    expect(SiteUpload.find_by(var: 'wordmark_dark')).to be_nil
  end

  it 'keeps the current image when the preset has none and it is not set to clear' do
    SiteUpload.create!(var: 'wordmark_dark', file: wordmark)
    preset = described_class.create!(name: '색만', theme_settings: { 'community_theme_main_light' => '#aa0000' })

    preset.apply!

    expect(Setting.community_theme_main_light).to eq '#aa0000'
    expect(SiteUpload.find_by(var: 'wordmark_dark')).to be_present
  end

  it 'seeds the four house presets with backgrounds once' do
    described_class.seed_defaults!
    described_class.seed_defaults!

    expect(described_class.pluck(:name)).to eq %w(그리핀도르 후플푸프 슬리데린 래번클로)
    gryffindor = described_class.first
    expect(gryffindor.theme_settings).to include('community_theme_main_light' => '#7f0909', 'community_theme_point_dark' => '#e8b939', 'community_theme_box_border' => true)
    expect(gryffindor.images.pluck(:var)).to contain_exactly('community_theme_background_light', 'community_theme_background_dark')
    expect(gryffindor.preview_panels.first[:colors].first).to eq '#7f0909'

    gryffindor.apply!
    expect(Setting.community_theme_main_light).to eq '#7f0909'
    expect(SiteUpload.find_by(var: 'community_theme_background_dark').file).to be_present
  end
end
