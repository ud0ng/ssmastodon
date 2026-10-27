# frozen_string_literal: true

# 디자인 프리셋의 이미지 하나 (var: 낮·밤 로고, 낮·밤 배경 = SiteUpload 의 var 와 같다). 적용하면 SiteUpload 로 복사한다.
class DesignPresetImage < ApplicationRecord
  include Attachmentable

  belongs_to :preset, class_name: 'DesignPreset', foreign_key: :design_preset_id, inverse_of: :images

  has_attached_file :file
  validates_attachment :file, presence: true, content_type: { content_type: %r{\Aimage/.*\z} }
  validates :var, inclusion: { in: ->(_) { DesignPreset::IMAGE_VARS } }
end
