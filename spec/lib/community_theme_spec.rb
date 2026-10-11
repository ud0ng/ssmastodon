# frozen_string_literal: true

require 'rails_helper'

RSpec.describe CommunityTheme do
  subject(:community_theme) { described_class.new }

  before { Setting.community_theme_main_light = '#003C4F' }

  describe '#palette' do
    it 'derives every colour from the main colour' do
      palette = community_theme.palette('light')

      expect(palette).to include(
        'main' => '#003c4f',
        'point' => '#003c4f',
        'box' => community_theme.mix('#003c4f', 5, '#ffffff'),
        'nav' => community_theme.mix('#003c4f', 80, '#14161a'),
        'on_point' => '#ffffff',
        'box_opacity' => 92
      )
      expect(palette.keys).to include(*(described_class::DETAILS - described_class::CSS_DERIVED))
    end

    it 'uses a detailed colour when one is set' do
      Setting.community_theme_box_light = '#FFFFFF'
      Setting.community_theme_box_opacity_light = '100'

      expect(community_theme.palette('light')).to include('box' => '#ffffff', 'box_opacity' => 100)
      expect(community_theme.palette('dark')['box']).to_not eq '#ffffff'
    end

    it 'leaves the hover background to CSS unless it is set' do
      expect(community_theme.palette('light')).to_not have_key('hover')
      expect(community_theme.auto_palette('light')).to have_key('hover')

      Setting.community_theme_hover_light = '#EEEEEE'
      expect(community_theme.palette('light')['hover']).to eq '#eeeeee'
    end

    it 'ignores an invalid colour' do
      Setting.community_theme_text_light = 'red'

      expect(community_theme.palette('light')['text']).to eq community_theme.auto_palette('light')['text']
    end

    it 'paints the post button with the menu colour when that option is on' do
      Setting.community_theme_post_button_main = true

      palette = community_theme.palette('light')
      expect(palette['post_button']).to eq palette['nav']
    end
  end

  describe '#mix' do
    it 'matches CSS color-mix in srgb' do
      expect(community_theme.mix('#000000', 50, '#ffffff')).to eq '#808080'
      expect(community_theme.mix('#ff0000', 100, '#0000ff')).to eq '#ff0000'
    end
  end
end
