# frozen_string_literal: true

# 디자인 프리셋 (서버 설정 > 디자인): 낮·밤 테마 색 설정 전부 + 로고·배경 이미지를 한 묶음으로 저장
class CreateDesignPresets < ActiveRecord::Migration[8.0]
  def change
    create_table :design_presets do |t|
      t.string :name, null: false, default: ''
      t.integer :position, null: false, default: 0
      t.jsonb :theme_settings, null: false, default: {}
      t.string :clear_images, array: true, null: false, default: []
      t.timestamps
    end

    create_table :design_preset_images do |t|
      t.references :design_preset, null: false, foreign_key: { on_delete: :cascade }
      t.string :var, null: false, default: ''
      t.string :file_file_name
      t.string :file_content_type
      t.integer :file_file_size
      t.datetime :file_updated_at
      t.timestamps
    end

    add_index :design_preset_images, [:design_preset_id, :var], unique: true
  end
end
