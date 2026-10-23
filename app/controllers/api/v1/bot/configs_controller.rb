# frozen_string_literal: true

# 자동봇 설정: 재화 이름·양도·출석·툿 보상, 상점·운영진 명령어 이름, 운영진 계정, 도움말(상점·운영진·컨텐츠), 스탯 목록
class Api::V1::Bot::ConfigsController < Api::V1::Bot::BaseController
  # 자동봇이 원래 이름으로 처리하는 명령어 (설정 키 → 자동봇 쪽 이름)
  COMMANDS = {
    'cmd_bag' => 'bag', 'cmd_shop' => 'shop', 'cmd_buy' => 'buy', 'cmd_describe' => 'describe', 'cmd_discard' => 'discard',
    'cmd_use' => 'use', 'cmd_status' => 'status', 'cmd_transfer' => 'transfer', 'cmd_attendance' => 'attendance',
    'cmd_money_add' => 'money_add', 'cmd_money_sub' => 'money_sub', 'cmd_item_add' => 'item_add', 'cmd_item_sub' => 'item_sub',
    'cmd_stat_change' => 'stat_change'
  }.freeze

  def show
    common = Game::Config.for('common')
    currency = Game::Config.for('currency')
    render json: {
      currency: common['currency_name'],
      transfer_enabled: currency['transfer_enabled'],
      shop_open: currency['shop_open'],
      attendance_reward: common['attendance_reward'],
      # 툿 보상은 마스토돈이 툿이 저장될 때 직접 준다 (Game::Activity). 예전 자동봇의 툿 보상은 끈다
      toot_reward_every: 0,
      toot_reward_amount: 0,
      commands: COMMANDS.to_h { |key, name| [name, currency[key].to_s.strip.presence || Game::Config.schema('currency').find { |field| field.key == key }.default] },
      admins: Array(currency['admin_usernames']),
      # 마니또 추측 명령어 (관리 > RP > 마니또 설정). 꺼져 있어도 이 명령어는 서버가 '열려 있지 않다'고 답한다
      manito_command: Game::Manito.command,
      # 도움말: 컨텐츠 설정 > 도움말 (help 상점, admin_help 운영진, content_help 컨텐츠, basic_help 기본, help_topics 분류)
      **Game::Help.bot_json,
      stats: GameCharacterField.stats.map { |field| { name: field.name, type: field.stat_type, min: field.stat? ? field.min : nil, max: field.stat? ? field.max : nil } },
    }
  end
end
