# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Themes do
  subject(:themes) { described_class.instance }

  context 'when the community theme is off' do
    before do
      Setting.community_theme_enabled = false
      Setting.theme = 'mastodon-bird-ui-dark'
    end

    it 'hides the community themes' do
      expect(themes.names).to_not include('community-light', 'community-dark')
    end

    it 'uses the server theme by default' do
      expect(themes.default).to eq 'mastodon-bird-ui-dark'
    end

    it 'shows community theme users the matching base theme' do
      expect(themes.resolve('community-light')).to eq 'mastodon-bird-ui-light'
      expect(themes.resolve('community-dark')).to eq 'mastodon-bird-ui-dark'
    end
  end

  context 'when the community theme is on' do
    before do
      Setting.community_theme_enabled = true
      Setting.community_theme_default = 'dark'
    end

    it 'lists the community themes' do
      expect(themes.names).to include('community-light', 'community-dark')
      expect(themes.base_names).to_not include('community-light')
    end

    it 'uses the chosen community theme by default' do
      expect(themes.default).to eq 'community-dark'
      expect(themes.resolve(nil)).to eq 'community-dark'
      expect(User.new.settings['theme']).to eq 'community-dark'
    end

    it 'keeps a theme the user picked' do
      expect(themes.resolve('mastodon-bird-ui-light')).to eq 'mastodon-bird-ui-light'
    end
  end
end
