# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Admin content settings' do
  before { sign_in Fabricate(:admin_user) }

  it 'saves the per-content points table from the settings tab' do
    patch admin_game_setting_path('common'), params: {
      config: { currency_name: '시클' },
      points: { jellybean: { win: '50', draw: '10', lose: '30' }, duel: { win: '40', draw: '', lose: '-5' }, chess: { win: '99' } },
    }

    expect(response).to redirect_to(admin_game_setting_path('common'))
    expect(Game::Config.for('jellybean').slice('points_win', 'points_draw', 'points_lose')).to eq('points_win' => 50, 'points_draw' => 10, 'points_lose' => 30)
    expect(Game::Config.for('duel').slice('points_win', 'points_draw', 'points_lose')).to eq('points_win' => 40, 'points_draw' => 0, 'points_lose' => 0)
    expect(Game::Config.for('common')['currency_name']).to eq '시클'
  end

  it 'keeps other content settings when the points change' do
    Game::Config.merge!('jellybean', 'beans' => 6)

    patch admin_game_setting_path('common'), params: { points: { jellybean: { win: '7', draw: '0', lose: '0' } } }

    expect(Game::Config.for('jellybean')).to include('beans' => 6, 'points_win' => 7)
  end

  it 'puts the record commands on their own row' do
    rows = Game::Config.sections('common', 'commands').to_h.fetch('commands').slice_before { |field| Game::Config::ROW_STARTS.include?(field.key) }.map { |row| row.map(&:key) }

    expect(rows).to eq [%w(cmd_accept cmd_decline cmd_forfeit), %w(cmd_points cmd_record)]
  end
end
