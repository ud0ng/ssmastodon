# frozen_string_literal: true

# 자동봇 설정: 재화 이름·양도·출석·툿 보상·도움말, 스탯 목록
class Api::V1::Bot::ConfigsController < Api::V1::Bot::BaseController
  def show
    common = Game::Config.for('common')
    currency = Game::Config.for('currency')
    render json: {
      currency: common['currency_name'],
      transfer_enabled: currency['transfer_enabled'],
      attendance_reward: currency['attendance_reward'],
      toot_reward_every: currency['toot_reward_every'],
      toot_reward_amount: currency['toot_reward_amount'],
      help: Array(currency['help_lines']).map { |line| line.gsub('n재화', "n#{common['currency_name']}") },
      admin_help: Array(currency['admin_help_lines']),
      stats: GameCharacterField.stats.map { |field| { name: field.name, type: field.stat_type, min: field.stat? ? field.min : nil, max: field.stat? ? field.max : nil } },
    }
  end
end
