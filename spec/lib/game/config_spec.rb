# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Game::Config do
  describe '.sections' do
    it 'lays out the common settings and hides the group labels edited elsewhere' do
      sections = described_class.sections('common').to_h { |name, fields| [name, fields.map(&:key)] }

      expect(sections.keys).to eq %w(basic rules summary messages tournament)
      expect(sections['basic']).to include('system_username', 'currency_name', 'group_mode', 'scoring_mode')
      expect(sections['rules']).to include('cmd_accept', 'invite_minutes', 'daily_pair_limit')
      expect(sections.values.flatten).to_not include('house_label', 'faction_label')
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
