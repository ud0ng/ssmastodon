# frozen_string_literal: true

# 기본 디자인 프리셋: 그리핀도르·후플푸프·슬리데린·래번클로 (DesignPreset::DEFAULTS, 배경은 db/seeds/design_presets)
class SeedDesignPresets < ActiveRecord::Migration[8.0]
  def up
    DesignPreset.reset_column_information
    DesignPresetImage.reset_column_information
    DesignPreset.seed_defaults!
  end

  def down; end
end
