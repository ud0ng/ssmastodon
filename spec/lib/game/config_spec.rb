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
      expect(described_class.sections('lessons').map(&:first)).to eq %w(lesson_commands lesson_rules grades bonus lesson_messages)
      expect(described_class.sections('lessons').to_h['lesson_rules'].map(&:key)).to eq %w(join_minutes class_minutes study_daily_limit)
    end

    it 'lays out a content as basic, rules, rewards, commands and messages (points live in the settings tab)' do
      sections = described_class.sections('jellybean').to_h { |name, fields| [name, fields.map(&:key)] }

      expect(sections.keys.first(5)).to eq %w(basic subject_rules rewards subject_commands subject_messages)
      expect(sections['basic']).to eq %w(enabled name command)
      expect(sections['subject_rules']).to include('beans', 'worst_flavor', 'flavors')
      expect(sections.keys - %w(basic subject_rules rewards subject_commands subject_messages)).to eq %w(points)
    end

    it 'lays out a lesson subject as basic, rules, commands and messages' do
      sections = described_class.sections('levitation').to_h { |name, fields| [name, fields.map(&:key)] }

      expect(sections.keys).to eq %w(basic subject_rules subject_commands subject_messages)
      expect(sections['subject_rules']).to include('signal_min', 'signal_max', 'seconds_O')
      expect(described_class.sections('practice').flat_map(&:last).map(&:key)).to_not include('patronus_spell', 'msg_patronus')
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
