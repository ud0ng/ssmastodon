# frozen_string_literal: true

require 'rails_helper'

# 서버 설정 > 디자인 > 프리셋: 저장·적용·이름/이미지 고치기·덮어쓰기·삭제
RSpec.describe 'Admin Settings Design Presets' do
  before { sign_in Fabricate(:admin_user) }

  it 'saves the current design, applies it, edits and deletes it' do
    Setting.community_theme_main_light = '#123456'

    post admin_settings_design_presets_path, params: { design_preset: { name: '봄' } }
    expect(response).to redirect_to(admin_settings_community_theme_path)
    preset = DesignPreset.last
    expect(preset.name).to eq '봄'

    Setting.community_theme_main_light = '#654321'
    post apply_admin_settings_design_preset_path(preset)
    expect(response).to redirect_to(admin_settings_community_theme_path)
    expect(Setting.community_theme_main_light).to eq '#123456'

    background = Rack::Test::UploadedFile.new(Rails.root.join('spec', 'fixtures', 'files', '600x400.png'), 'image/png')
    patch admin_settings_design_preset_path(preset), params: { design_preset: { name: '여름', images: { community_theme_background_dark: background }, clear: { wordmark_light: '1' } } }
    preset.reload
    expect(preset.name).to eq '여름'
    expect(preset.images.pluck(:var)).to eq ['community_theme_background_dark']
    expect(preset.clear_images).to eq ['wordmark_light']

    Setting.community_theme_main_light = '#777777'
    patch admin_settings_design_preset_path(preset, overwrite: '1')
    expect(preset.reload.theme_settings['community_theme_main_light']).to eq '#777777'

    expect { delete admin_settings_design_preset_path(preset) }.to change(DesignPreset, :count).by(-1)
  end
end
