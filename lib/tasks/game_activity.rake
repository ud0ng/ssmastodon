# frozen_string_literal: true

namespace :game do
  desc 'Build the daily activity snapshots (toot counts and chars per character per day, KST) from every past toot'
  task activity_backfill: :environment do
    Game::ActivitySnapshot.catch_up!(force: true)
    puts "완료: #{Game::ActivitySnapshot.first_day} ~ #{Game::ActivitySnapshot.today} (#{GameActivityDay.count}줄, 상대 캐릭터 #{GameActivityPair.count}줄)"
  end

  # 두 캐릭터 사이의 답 횟수·스루를 대화마다 풀어 보여 준다 (툿 내용은 찍지 않는다).
  #   bin/rails "game:activity_explain[아이디A,아이디B]"
  # 대화 한 줄: 툿을 쓴 차례대로 A/B(그 밖의 사람은 ·), 찾아간 답(답 횟수)은 *, 스루로 센 툿은 !, 셋 이상 태그는 m, 태그 없음은 0, DM 은 d, 공개는 p
  desc 'Explain reply turns and skips between two characters, conversation by conversation'
  task :activity_explain, %i(a b) => :environment do |_, args|
    a = Account.find_local!(args[:a].to_s.delete_prefix('@'))
    b = Account.find_local!(args[:b].to_s.delete_prefix('@'))
    letter = { a.id => 'A', b.id => 'B' }
    snapshot = Game::ActivitySnapshot
    conversations = Status.local.where(account_id: [a.id, b.id], reblog_of_id: nil)
                          .where(id: Mention.where(account_id: [a.id, b.id]).select(:status_id))
                          .reorder(nil).distinct.pluck(:conversation_id).compact.sort
    sums = Hash.new(0)
    lines = []

    conversations.each do |conversation|
      toots = Status.where(conversation_id: conversation, reblog_of_id: nil).local.reorder(:id).includes(:mentions).to_a
      tagged = toots.any? { |toot| (toot.account_id == a.id && toot.mentions.any? { |m| m.account_id == b.id }) || (toot.account_id == b.id && toot.mentions.any? { |m| m.account_id == a.id }) }
      next unless tagged

      ids = toots.map(&:id)
      open = Status.where(id: ids).local.reorder(nil).where.not(visibility: :direct)
      visits = snapshot.first_visit_scope(open).where(statuses: { account_id: [a.id, b.id] }, parents: { account_id: [a.id, b.id] })
                       .pluck(Arel.sql('statuses.id'), Arel.sql('statuses.account_id')).to_h
      skips = snapshot.skipped_scope(ids).where(mentions: { account_id: [a.id, b.id] }, statuses: { account_id: [a.id, b.id] })
                      .pluck(Arel.sql('statuses.id'), Arel.sql('mentions.account_id')).to_h
      visits.each_value { |who| sums["#{letter[who]} 답 횟수"] += 1 }
      skips.each_value { |who| sums["#{letter[who]} 스루"] += 1 }

      marks = toots.map do |toot|
        others = toot.mentions.reject { |m| m.silent? || m.account_id == toot.account_id }
        flags = +''
        flags << '*' if visits.key?(toot.id)
        flags << '!' if skips.key?(toot.id)
        flags << 'm' if others.size > 1
        flags << '0' if others.empty? && letter.key?(toot.account_id)
        flags << 'd' if toot.direct_visibility?
        flags << 'p' if toot.public_visibility?
        "#{letter.fetch(toot.account_id, '·')}#{flags}"
      end
      lines << "#{Mastodon::Snowflake.to_time(toots.first.id).in_time_zone(snapshot::ZONE).strftime('%m-%d %H:%M')}  #{marks.join(' ')}"
    end

    puts "A = @#{a.username}, B = @#{b.username} / 대화 #{lines.size}개 (차례: * 찾아간 답, ! 스루, m 셋 이상 태그, 0 태그 없음, d DM, p 공개, · 다른 사람)"
    puts lines.last(60)
    puts '...' if lines.size > 60
    puts "툿으로 센 합계: A 답 횟수 #{sums['A 답 횟수']}, B 답 횟수 #{sums['B 답 횟수']}, A 스루 #{sums['A 스루']}, B 스루 #{sums['B 스루']}"
    stored = ->(from, to) { GameActivityPair.where(account_id: from.id, other_account_id: to.id).pick(Arel.sql('SUM(reply_turns)'), Arel.sql('SUM(skipped)')).map(&:to_i) }
    a_turns, a_skips = stored.call(a, b)
    b_turns, b_skips = stored.call(b, a)
    puts "스냅샷에 저장된 합계: A 답 횟수 #{a_turns}, B 답 횟수 #{b_turns}, A 스루 #{a_skips}, B 스루 #{b_skips} (다르면 game:activity_backfill 로 다시 계산)"
  end
end
