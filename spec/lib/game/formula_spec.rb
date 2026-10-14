# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Game::Formula do
  let(:stats) { { '힘' => 10, '민첩' => 4 } }

  it 'multiplies a number written right after a stat' do
    expect(described_class.evaluate('{{힘}}5', stats)).to eq 50
    expect(described_class.evaluate('5{{힘}}', stats)).to eq 50
  end

  it 'supports the four operations, parentheses and unary minus' do
    expect(described_class.evaluate('{{힘}}*5', stats)).to eq 50
    expect(described_class.evaluate('({{힘}}+{{민첩}})/2', stats)).to eq 7
    expect(described_class.evaluate('10+{{힘}}*2', stats)).to eq 30
    expect(described_class.evaluate('-{{민첩}}+10', stats)).to eq 6
    expect(described_class.evaluate('2({{힘}}+1)', stats)).to eq 22
  end

  it 'treats an unknown stat as zero and rounds the result' do
    expect(described_class.evaluate('{{없음}}+3', stats)).to eq 3
    expect(described_class.evaluate('{{힘}}/4', stats)).to eq 3
  end

  it 'lists the stat names used' do
    expect(described_class.names('{{힘}}*{{ 민첩 }}+{{힘}}')).to eq %w(힘 민첩)
  end

  it 'rejects broken formulas without evaluating anything' do
    ['', '{{힘}}**2', '(1+2', '1+', 'system("ls")', '{{힘}}/0'].each do |formula|
      expect(described_class.valid?(formula)).to be(false), formula
    end
    expect { described_class.evaluate('1/0', {}) }.to raise_error(described_class::Error)
  end
end
