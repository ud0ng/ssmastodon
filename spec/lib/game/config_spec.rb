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
      expect(settings['rules']).to eq %w(contents_open invite_minutes turn_seconds one_game_per_person)
      expect(commands['commands']).to eq %w(cmd_accept cmd_decline cmd_cancel cmd_forfeit cmd_points cmd_record)
      expect((settings.values + commands.values).flatten).to_not include('house_label', 'scoring_mode', 'msg_season_final')
    end

    it 'lays out a content as basic, rules, rewards, commands and messages (points live in the settings tab)' do
      sections = described_class.sections('jellybean').to_h { |name, fields| [name, fields.map(&:key)] }

      expect(sections.keys.first(5)).to eq %w(basic subject_rules rewards subject_commands subject_messages)
      expect(sections['basic']).to eq %w(enabled name description command)
      expect(sections['subject_rules']).to include('beans', 'worst_flavor', 'flavors')
      expect(sections.keys - %w(basic subject_rules rewards subject_commands subject_messages)).to eq %w(points)
    end

  end

  describe '.update!' do
    it 'keeps stored values that the form did not send' do
      described_class.merge!('common', 'house_label' => '반')

      described_class.update!('common', 'cmd_accept' => '좋아')

      expect(described_class.for('common')).to include('house_label' => '반', 'cmd_accept' => '좋아')
    end

    it 'does not store a message that only differs from the default by form line endings' do
      default = described_class.schema('jellybean').find { |field| field.key == 'msg_turn' }.default

      described_class.update!('jellybean', 'msg_turn' => default.gsub("\n", "\r\n"))

      expect(GameConfig.find_by(key: 'jellybean').data).not_to have_key('msg_turn')
    end
  end
end
