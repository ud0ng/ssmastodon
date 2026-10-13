# frozen_string_literal: true

module Game
  # 컨텐츠 보상: 돈(캐릭터 money)과 아이템(캐릭터 inventory). 기록은 GameReward.
  # 컨텐츠마다 설정 'rewards' 묶음 (Kinds::Base.base_fields), 마법 수업은 등급별 (Game::Lessons::FIELDS).
  # 같은 상대와 하루 N판 규칙(공통 daily_pair_limit)은 점수와 같이 적용한다.
  module Rewards
    ITEMS_HINT = '줄마다 아이템|개수|확률% (예: 초콜릿 개구리|1|30). 확률을 비우면 반드시 줍니다. 줄마다 따로 뽑습니다.'

    module_function

    # 승패에 따른 보상. outcome: 'win' / 'draw' / 'lose'
    def for_outcome(session, player, config, outcome, reason:)
      money = config["reward_money_#{outcome}"].to_i
      items = outcome == 'win' ? roll(config['reward_items_win']) : []
      give(session, player, money: money, items: items, reason: reason, pair_limit: true)
    end

    # 보상을 주고 안내 문구를 돌려준다 (안 줬으면 nil)
    def give(session, player, money:, items: [], reason: '', pair_limit: false)
      money = money.to_i
      items = Array(items).select { |item| item['name'].present? && item['count'].to_i.positive? }
      return if money <= 0 && items.empty?

      account = player.is_a?(Account) ? player : player.account
      return if pair_limit && over_daily_limit?(session, account)

      character = GameCharacter.for(account)
      character.with_lock do
        character.money += money
        character.add_items(items)
        character.save!
      end
      GameReward.create!(account: account, session: session, money: money, items: items, reason: reason.to_s)

      common = Game::Config.for('common')
      Game::Text.render(common['msg_reward'], player: player, rewards: describe(money, items, common['currency_name']),
                                              money: money, currency: common['currency_name'], items: items.map { |item| item_label(item) }.join(', '))
    end

    # "아이템|개수|확률%" 줄마다 따로 뽑는다 (확률을 비우면 100%)
    def roll(lines, random: Random)
      Array(lines).filter_map do |line|
        name, count, chance = line.to_s.split('|', 3).map(&:strip)
        next if name.blank?

        chance = chance.presence ? chance.delete('%').to_f : 100.0
        next unless random.rand * 100 < chance

        { 'name' => name, 'count' => [count.to_i, 1].max }
      end
    end

    def describe(money, items, currency)
      parts = []
      parts << "#{money} #{currency}" if money.positive?
      parts.concat(items.map { |item| item_label(item) })
      parts.join(', ')
    end

    def item_label(item)
      item['count'].to_i > 1 ? "#{item['name']} ×#{item['count']}" : item['name']
    end

    # 오늘(한국 시간) 같은 상대가 있는 판으로 이미 limit 번 보상을 받았는가
    def over_daily_limit?(session, account)
      limit = Game::Config.for('common')['daily_pair_limit'].to_i
      return false if limit <= 0 || session.nil?

      opponent_ids = session.players.map(&:account_id) - [account.id]
      return false if opponent_ids.empty?

      shared = GamePlayer.where(account_id: opponent_ids).select(:game_session_id)
      GameReward.where(account: account, game_session_id: shared)
                .where.not(game_session_id: session.id)
                .where(created_at: Time.now.in_time_zone('Asia/Seoul').beginning_of_day..)
                .count >= limit
    end
  end
end
