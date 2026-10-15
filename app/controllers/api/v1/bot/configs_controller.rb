# frozen_string_literal: true

# 자동봇 설정: 재화 이름·양도·출석·툿 보상, 상점·운영진 명령어 이름, 운영진 계정, 도움말, 스탯 목록
class Api::V1::Bot::ConfigsController < Api::V1::Bot::BaseController
  # 자동봇이 원래 이름으로 처리하는 명령어 (설정 키 → 자동봇 쪽 이름)
  COMMANDS = {
    'cmd_bag' => 'bag', 'cmd_shop' => 'shop', 'cmd_buy' => 'buy', 'cmd_describe' => 'describe', 'cmd_consume' => 'consume',
    'cmd_use' => 'use', 'cmd_status' => 'status', 'cmd_transfer' => 'transfer', 'cmd_attendance' => 'attendance', 'cmd_help' => 'help',
    'cmd_money_add' => 'money_add', 'cmd_money_sub' => 'money_sub', 'cmd_item_add' => 'item_add', 'cmd_item_sub' => 'item_sub',
    'cmd_stat_change' => 'stat_change'
  }.freeze

  def show
    common = Game::Config.for('common')
    currency = Game::Config.for('currency')
    render json: {
      currency: common['currency_name'],
      transfer_enabled: currency['transfer_enabled'],
      attendance_reward: common['attendance_reward'],
      # 툿 보상은 마스토돈이 툿이 저장될 때 직접 준다 (Game::Activity). 예전 자동봇의 툿 보상은 끈다
      toot_reward_every: 0,
      toot_reward_amount: 0,
      commands: COMMANDS.to_h { |key, name| [name, currency[key].to_s.strip.presence || Game::Config.schema('currency').find { |field| field.key == key }.default] },
      admins: Array(currency['admin_usernames']),
      help: help_lines(Game::Config::SHOP_HELP, currency, common),
      admin_help: help_lines(Game::Config::SHOP_ADMIN_HELP, currency, common),
      stats: GameCharacterField.stats.map { |field| { name: field.name, type: field.stat_type, min: field.stat? ? field.min : nil, max: field.stat? ? field.max : nil } },
    }
  end

  private

  # 도움말 줄: 꺼진 기능(양도·출석)은 뺀다
  def help_lines(templates, currency, common)
    templates.filter_map do |key, template|
      next if key == 'cmd_transfer' && !currency['transfer_enabled']
      next if key == 'cmd_attendance' && common['attendance_reward'].to_i <= 0

      format(template, cmd: currency[key], currency: common['currency_name'])
    end
  end
end
