# frozen_string_literal: true

module Game
  # 서버원 활동 (캐릭터 관리 > 활동)과 툿 보상 (컨텐츠 설정 > 설정 > 재화 설정)
  #   퍼블 툿: 답글이 아닌 툿 (누군가를 태그했어도 답글이 아니면 퍼블)   답 툿: 답글
  #   둘 다 DM·부스트는 빼고, 지운 툿은 세지 않는다. 글자 수는 본문(text) 길이.
  #
  # 툿 보상은 툿이 저장될 때(웹·앱 모두 같은 경로) Status 의 after_create_commit → Game::ActivityWorker 가 확인한다.
  # 캐릭터마다 지금까지 받은 횟수(toot_reward_units)를 두고, 쌓인 양 ÷ 단위가 그보다 커지면 그만큼 지급한다.
  # 기준(툿 수/글자 수, 퍼블 포함, 단위)을 바꾸면 그때 쌓인 양을 새 출발점으로 삼는다 (한꺼번에 몰아 주지 않게).
  module Activity
    Stats = Struct.new(:posts, :post_chars, :replies, :reply_chars, keyword_init: true) do
      def self.empty
        new(posts: 0, post_chars: 0, replies: 0, reply_chars: 0)
      end
    end

    module_function

    # account_id => Stats
    def stats(account_ids)
      result = Hash.new { |hash, key| hash[key] = Stats.empty }
      counted(account_ids).pluck(:account_id, Arel.sql('in_reply_to_id IS NULL'), Arel.sql('COUNT(*)'), Arel.sql('COALESCE(SUM(char_length(text)), 0)'))
                          .each do |account_id, top_level, count, chars|
        stats = result[account_id]
        if top_level
          stats.posts = count
          stats.post_chars = chars.to_i
        else
          stats.replies = count
          stats.reply_chars = chars.to_i
        end
      end
      result
    end

    def counted(account_ids)
      Status.where(account_id: account_ids, reblog_of_id: nil).where.not(visibility: :direct).reorder(nil)
            .group(:account_id, Arel.sql('in_reply_to_id IS NULL'))
    end

    # 지금 툿 보상 설정: { basis:, public:, every:, amount: } (끔이면 nil)
    def reward_rule
      common = Game::Config.for('common')
      every = common['toot_reward_every'].to_i
      amount = common['toot_reward_amount'].to_i
      return if every <= 0 || amount <= 0

      { basis: common['toot_reward_basis'] == 'chars' ? 'chars' : 'toots', public: common['toot_reward_public'] ? true : false, every: every, amount: amount }
    end

    def rule_signature(rule)
      "#{rule[:basis]}:#{rule[:public] ? 'all' : 'replies'}:#{rule[:every]}"
    end

    # 규칙에 맞는 쌓인 양 (툿 수 또는 글자 수)
    def progress(stats, rule)
      if rule[:basis] == 'chars'
        stats.reply_chars + (rule[:public] ? stats.post_chars : 0)
      else
        stats.replies + (rule[:public] ? stats.posts : 0)
      end
    end

    # 이 계정의 툿 보상 확인·지급. 준 재화를 돌려준다 (안 줬으면 0)
    def reward!(account)
      rule = reward_rule
      return 0 if rule.nil?

      character = GameCharacter.visible.find_by(account_id: account.id)
      return 0 if character.nil?

      units = progress(stats([account.id])[account.id], rule) / rule[:every]
      signature = rule_signature(rule)
      paid = 0
      character.with_lock do
        if character.toot_reward_basis != signature
          # 기준이 바뀌었거나 처음: 지금까지 쌓인 양을 출발점으로
          character.update!(toot_reward_basis: signature, toot_reward_units: units)
        elsif units > character.toot_reward_units
          steps = units - character.toot_reward_units
          paid = steps * rule[:amount]
          character.update!(toot_reward_units: units)
        end
      end
      if paid.positive?
        Game::Wallet.apply!([{ account: account, money: paid }], kind: 'toot',
                                                                  detail: reward_detail(units * rule[:every], rule[:basis]))
      end
      paid
    end

    # 재화 내역에 남기는 말 (워커 언어와 상관없이 한글): 툿 보상 (100자) / 툿 보상 (100툿)
    def reward_detail(amount, basis)
      "툿 보상 (#{amount}#{basis == 'chars' ? '자' : '툿'})"
    end
  end
end
