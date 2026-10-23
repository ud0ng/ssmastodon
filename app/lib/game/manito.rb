# frozen_string_literal: true

module Game
  # 마니또 (관리 > RP > 마니또 설정). 운영진이 캐릭터(A)마다 상대(B)에게 몰래 말해야 하는 단어를 정해 준다.
  #   사용  A가 B를 태그한 툿에 그 단어가 들어 있으면 1회 (툿 하나에 1회, DM 은 설정에 따라). 하루 최대 보상 횟수 안이면
  #         보상(소속 점수·재화·아이템)을 받고, 상점봇이 A에게만 DM 으로 몰래 알려 준다 (record!, Game::ManitoWorker).
  #   추측  B가 상점봇에게 [마니또/단어/캐릭터] → 자동봇(ssbot)이 서버에 묻는다 (guess!, POST /api/v1/bot/manito/guess).
  #         맞으면 A가 B에게서 받은 보상을 B가 모두 빼앗고 A는 더 이상 B에게서 보상을 받지 못한다 (다른 상대에게는 계속).
  #         틀리면 벌금(재화)을 내고, 하루 추측 횟수에 제한이 있다.
  module Manito
    ZONE = 'Asia/Seoul'
    KEY = 'manito'

    F = Game::Config::Field

    FIELDS = [
      F.new(key: 'manito_enabled', type: :boolean, default: false, group: 'manito_unlock', label: '마니또 해금', hint: '끄면 단어를 써도 세지 않고 추측 명령어도 받지 않습니다'),
      F.new(key: 'manito_daily_limit', type: :integer, default: 5, group: 'manito_limits', label: '하루 최대 보상 획득 횟수', hint: '한 캐릭터가 하루(00시 기준)에 보상을 받는 횟수. 넘으면 횟수만 셉니다 (0 = 제한 없음)'),
      F.new(key: 'manito_include_dm', type: :boolean, default: false, group: 'manito_limits', label: 'DM 포함', hint: '켜면 상대에게 보낸 DM 에 쓴 단어도 셉니다'),
      F.new(key: 'manito_guess_limit', type: :integer, default: 3, group: 'manito_limits', label: '하루 최대 추측 횟수', hint: '한 캐릭터가 하루에 [마니또]로 추측할 수 있는 횟수 (0 = 제한 없음)'),
      F.new(key: 'manito_wrong_penalty', type: :integer, default: 0, group: 'manito_limits', label: '오답 벌금 (재화)', hint: '틀릴 때마다 빼는 재화. 모자라면 추측할 수 없습니다 (0 = 없음)'),
      F.new(key: 'manito_reward_points', type: :integer, default: 0, group: 'manito_rewards', label: '소속 점수', hint: '단어 1회 사용마다 말한 캐릭터의 소속에 주는 점수'),
      F.new(key: 'manito_reward_money', type: :integer, default: 1, group: 'manito_rewards', label: '재화', hint: '단어 1회 사용마다 주는 재화'),
      F.new(key: 'reward_items_manito', type: :lines, default: [], group: 'manito_rewards', label: '아이템', hint: Game::Rewards::ITEMS_HINT),
      F.new(key: 'manito_command', type: :string, default: '마니또', group: 'manito_commands', label: '추측 명령어', hint: '상점봇에게 [마니또/단어/캐릭터 이름이나 아이디]'),
      F.new(key: 'msg_manito_use', type: :text, group: 'manito_messages', label: '단어 성공 (상점봇이 말한 사람에게 DM)',
            default: "%{target}의 단어(%{word}) %{uses}회 사용\n보상 %{rewards} 획득"),
      F.new(key: 'msg_manito_use_capped', type: :text, group: 'manito_messages', label: '단어 성공, 오늘 보상 횟수를 다 씀 (DM)',
            default: "%{target}의 단어(%{word}) %{uses}회 사용\n오늘 받을 수 있는 보상을 모두 받았습니다."),
      F.new(key: 'msg_manito_wrong', type: :text, group: 'manito_messages', label: '오답', default: '오답입니다.%{penalty}'),
      F.new(key: 'msg_manito_correct', type: :text, group: 'manito_messages', label: '정답',
            default: "정답입니다. %{target}의 보상을 탈취합니다.\n보상 내역 : %{rewards}"),
      F.new(key: 'msg_manito_caught', type: :text, group: 'manito_messages', label: '들킴 (상점봇이 들킨 사람에게 DM)',
            default: "%{target}에게 단어(%{word})를 들켰습니다. 보상을 빼앗겼습니다 : %{rewards}\n이제 %{target}에게서는 보상을 받을 수 없습니다."),
      F.new(key: 'msg_manito_guess_limit', type: :text, group: 'manito_messages', label: '추측 횟수 초과', default: '오늘은 더 추측할 수 없습니다. (하루 %{limit}번)'),
      F.new(key: 'msg_manito_no_money', type: :text, group: 'manito_messages', label: '벌금 부족', default: '추측하려면 %{penalty}{이가} 필요합니다.'),
    ].freeze

    class Error < StandardError; end

    module_function

    def config
      Game::Config.for(KEY)
    end

    def enabled?
      config['manito_enabled']
    end

    def command
      config['manito_command'].to_s.strip.presence || '마니또'
    end

    def today_range
      Time.now.in_time_zone(ZONE).beginning_of_day..
    end

    # ── 사용: 툿이 저장될 때 ──
    # 말한 사람(A)이 태그한 상대(B)마다, B에게 정해 둔 단어가 툿에 있으면 1회. 들킨 상대·시스템·상점봇은 뺀다
    def record!(status)
      return unless enabled?
      return if status.nil? || !status.local? || status.reblog_of_id.present?
      return if status.direct_visibility? && !config['manito_include_dm']

      excluded = excluded_account_ids
      return if excluded.include?(status.account_id)

      targets = status.mentions.reject { |mention| mention.silent? || mention.account_id == status.account_id || excluded.include?(mention.account_id) }.map(&:account_id).uniq
      return if targets.empty?

      GameManitoWord.where(account_id: status.account_id, target_account_id: targets, caught_at: nil).includes(:target_account).find_each do |pair|
        word = pair.match(status.text)
        use!(pair, word, status) if word
      end
    end

    def use!(pair, word, status)
      log = nil
      GameManitoWord.transaction do
        pair.lock!
        return if pair.caught? || GameManitoLog.exists?(kind: 'use', status_id: status.id, other_account_id: pair.target_account_id)

        pair.increment!(:uses)
        limit = config['manito_daily_limit'].to_i
        rewarded = limit.zero? || GameManitoLog.uses.where(account_id: pair.account_id, rewarded: true, created_at: today_range).count < limit
        reward = rewarded ? give_reward!(pair) : { money: 0, items: [], points: 0 }
        log = GameManitoLog.create!(kind: 'use', account_id: pair.account_id, other_account_id: pair.target_account_id, word: word, status_id: status.id,
                                    rewarded: rewarded, money: reward[:money], items: reward[:items], points: reward[:points])
      end
      notify_use(pair, word, log)
      log
    end

    # 보상: 재화·아이템(확률대로 뽑음)은 캐릭터에, 점수는 소속에
    def give_reward!(pair)
      money = config['manito_reward_money'].to_i
      items = Game::Rewards.roll(config['reward_items_manito'])
      points = config['manito_reward_points'].to_i
      if money.positive? || items.any?
        Game::Wallet.apply!([{ account: pair.account, money: money, items: items.to_h { |item| [item['name'], item['count']] }, other: pair.target_account, other_dir: 'to' }],
                            kind: 'manito', detail: '마니또 단어 사용', actor: 'manito')
      end
      house = points.positive? ? GameCharacter.for(pair.account).group : nil
      GameHousePoint.create!(house: house, account: pair.account, amount: points, reason: 'manito') if house
      { money: [money, 0].max, items: items, points: house ? points : 0 }
    end

    # ── 추측: B가 [마니또/단어/캐릭터] ──
    # 결과 문구를 돌려준다. 맞으면 A의 B 관련 보상을 B에게 옮기고 A에게 DM 으로 알린다
    def guess!(guesser, word, accused)
      raise Error, I18n.t('admin.manito.errors.off', default: '마니또가 열려 있지 않습니다.') unless enabled?
      raise Error, I18n.t('admin.manito.errors.self', default: '자기 자신은 고를 수 없습니다.') if accused.id == guesser.id

      settings = config
      limit = settings['manito_guess_limit'].to_i
      if limit.positive? && GameManitoLog.guesses.where(account_id: guesser.id, created_at: today_range).count >= limit
        return Game::Text.render(settings['msg_manito_guess_limit'], player: guesser, limit: limit)
      end

      pair = GameManitoWord.find_by(account_id: accused.id, target_account_id: guesser.id)
      return correct!(pair, guesser, word) if pair && !pair.caught? && pair.word?(word)

      wrong!(guesser, accused, word)
    end

    def wrong!(guesser, accused, word)
      settings = config
      penalty = settings['manito_wrong_penalty'].to_i
      currency = Game::Config.for('common')['currency_name']
      if penalty.positive? && GameCharacter.for(guesser).money < penalty
        return Game::Text.render(settings['msg_manito_no_money'], player: guesser, penalty: "#{penalty} #{currency}")
      end

      GameManitoLog.transaction do
        Game::Wallet.apply!([{ account: guesser, money: -penalty, other: accused, other_dir: 'to' }], kind: 'manito', detail: '마니또 오답 벌금', actor: 'manito') if penalty.positive?
        GameManitoLog.create!(kind: 'wrong', account: guesser, other_account: accused, word: word.to_s.strip.truncate(100), money: -penalty)
      end
      Game::Text.render(settings['msg_manito_wrong'], player: guesser, target: accused, penalty: penalty.positive? ? " (벌금 #{penalty} #{currency})" : '')
    end

    def correct!(pair, guesser, word)
      taken = nil
      GameManitoWord.transaction do
        pair.lock!
        return wrong!(guesser, pair.account, word) if pair.caught?

        taken = steal!(pair)
        pair.update!(caught_at: Time.now.utc)
        GameManitoLog.create!(kind: 'correct', account: guesser, other_account: pair.account, word: word.to_s.strip.truncate(100),
                              money: taken[:money], items: taken[:items], points: taken[:points])
      end
      rewards = describe(taken)
      settings = config
      notify(pair.account, Game::Text.render(settings['msg_manito_caught'], player: pair.account, target: guesser, word: pair.words.first, rewards: rewards))
      Game::Text.render(settings['msg_manito_correct'], player: guesser, target: pair.account, rewards: rewards)
    end

    # A가 B에게서 받은 (아직 안 빼앗긴) 보상을 B에게. A가 이미 써 버린 재화·아이템은 남은 만큼만, 점수는 A 소속에서 빼서 B 소속에 준다
    def steal!(pair)
      logs = GameManitoLog.uses.where(account_id: pair.account_id, other_account_id: pair.target_account_id, rewarded: true, stolen_at: nil).to_a
      thief = pair.target_account
      victim = GameCharacter.for(pair.account)
      money = [logs.sum(&:money), victim.money].min
      wanted = logs.flat_map { |log| Array(log.items) }.each_with_object(Hash.new(0)) { |item, sum| sum[item['name']] += item['count'].to_i }
      items = wanted.filter_map do |name, count|
        owned = Array(victim.inventory).find { |entry| Game::Wallet.key(entry['name']) == Game::Wallet.key(name) }.to_h['count'].to_i
        [name, [count, owned].min] if [count, owned].min.positive?
      end.to_h
      points = logs.sum(&:points)

      if money.positive? || items.any?
        Game::Wallet.apply!([{ account: pair.account, money: -money, items: items.transform_values(&:-@), other: thief, other_dir: 'to' },
                             { account: thief, money: money, items: items, other: pair.account, other_dir: 'from' }],
                            kind: 'manito', detail: '마니또 들킴', actor: 'manito')
      end
      if points.positive?
        from = victim.group
        to = GameCharacter.for(thief).group
        GameHousePoint.create!(house: from, account: pair.account, amount: -points, reason: 'manito') if from
        GameHousePoint.create!(house: to, account: thief, amount: points, reason: 'manito') if to
      end
      GameManitoLog.where(id: logs.map(&:id)).update_all(stolen_at: Time.now.utc)
      { money: money, items: items.map { |name, count| { 'name' => name, 'count' => count } }, points: points }
    end

    # ── 알림·문구 ──
    def notify_use(pair, word, log)
      settings = config
      template = log.rewarded ? settings['msg_manito_use'] : settings['msg_manito_use_capped']
      notify(pair.account, Game::Text.render(template, player: pair.account, target: pair.target_account, word: word, uses: pair.uses, rewards: describe(log)))
    end

    # 상점봇이 그 사람에게만 DM (상점봇이 없으면 시스템 계정)
    def notify(account, text)
      bot = Game::Gift.bot_accounts.first || Game::System.account
      return if bot.nil? || text.blank?

      PostStatusService.new.call(bot, text: "@#{account.username} #{text}", visibility: 'direct')
    rescue => e
      Rails.logger.warn { "manito notify failed: #{e.class} #{e.message}" }
      nil
    end

    # "3 갈레온, 사과 ×2, 소속 점수 5점" (없으면 '없음')
    def describe(reward)
      reward = reward.is_a?(GameManitoLog) ? { money: reward.money, items: reward.items, points: reward.points } : reward
      common = Game::Config.for('common')
      parts = []
      parts << Game::Rewards.describe(reward[:money].to_i, Array(reward[:items]), common['currency_name']).presence
      parts << "#{common['house_term']} 점수 #{reward[:points]}점" if reward[:points].to_i.positive?
      parts.compact.join(', ').presence || '없음'
    end

    def excluded_account_ids
      [Game::System.account, *Game::Gift.bot_accounts].compact.map(&:id)
    end

    # ── 관리 화면 ──
    # account_id => { money:, points:, items: { 이름 => 개수 } }: 지금 가지고 있는 마니또 보상 (안 빼앗긴 사용 보상 + 맞혀서 빼앗은 것)
    def holdings(account_ids)
      result = Hash.new { |hash, id| hash[id] = { money: 0, points: 0, items: Hash.new(0) } }
      GameManitoLog.where(account_id: account_ids).where("(kind = 'use' AND rewarded AND stolen_at IS NULL) OR kind = 'correct'").find_each do |log|
        row = result[log.account_id]
        row[:money] += log.money
        row[:points] += log.points
        Array(log.items).each { |item| row[:items][item['name']] += item['count'].to_i }
      end
      result
    end
  end
end
