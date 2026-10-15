# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Game::Config do
  describe '.sections' do
    it 'splits the common settings into the settings and commands pages' do
      settings = described_class.sections('common', 'settings').to_h { |name, fields| [name, fields.map(&:key)] }
      commands = described_class.sections('common', 'commands').to_h { |name, fields| [name, fields.map(&:key)] }

      expect(settings.keys).to eq %w(bots currency rules)
      expect(settings['bots']).to eq %w(system_username bot_usernames)
      expect(settings['currency']).to include('currency_name', 'attendance_reward', 'toot_reward_basis', 'toot_reward_public', 'toot_reward_every', 'toot_reward_amount')
      expect(settings['rules']).to eq %w(invite_minutes turn_seconds one_game_per_person)
      expect(commands['commands']).to eq %w(cmd_accept cmd_decline cmd_forfeit cmd_points cmd_record)
      expect((settings.values + commands.values).flatten).to_not include('house_label', 'scoring_mode', 'msg_season_final')
    end

    it 'lays out the lessons settings' do
      expect(described_class.sections('lessons').map(&:first)).to eq %w(rules points rewards lesson_messages)
    end
  end

  describe '.update!' do
    it 'keeps stored values that the form did not send' do
      described_class.merge!('common', 'house_label' => '반')

      described_class.update!('common', 'cmd_accept' => '좋아')

      expect(described_class.for('common')).to include('house_label' => '반', 'cmd_accept' => '좋아')
    end
  end
end
