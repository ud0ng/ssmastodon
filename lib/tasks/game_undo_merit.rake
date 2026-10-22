# frozen_string_literal: true

# 1회성 정리: 누적 수치 '상점'(칭찬)으로 얻은 소속 점수를 초기화하고,
# '상점'을 올리는 아이템을 지정한 때 이후에 구입한 것은 전부 환불하고 그 아이템을 삭제하며, 그 아이템을 써서 올라간 상점 횟수도 되돌린다. (벌점으로 바뀐 소속 점수는 그대로 둔다)
#
#   bin/rails game:undo_merit              미리보기: 아무것도 바꾸지 않고 무엇을 할지만 보여 준다
#   APPLY=1 bin/rails game:undo_merit      실제로 실행한다 (먼저 DB 를 백업해 두세요). 되돌릴 수 있게 tmp/undo_merit_<시각>.json 에 기록한다
#
#   COUNTER  누적 수치 이름 (기본 '상점')
#   SINCE    이 시각 이후의 구입만 환불 (기본 '2026-10-20 18:05', 한국 시간)
#
# 두 번 실행해도 이미 환불한 구입은 건너뛴다 (환불 기록에 구입 번호를 남긴다).
# 아이템 삭제는 구입한 개수만큼, 지금 가진 만큼만 지운다 (이미 쓴 아이템은 지울 수 없고 환불만 한다).
# 상점 횟수 되돌리기: 환불하는 구입자가 기준 시각 이후에 그 아이템을 써서 올린 기록을 구입한 개수만큼(최근 것부터) 되돌린다.
#   받은 사람의 상점 횟수가 그만큼 내려가고, 횟수로 붙었던 효과(칭호·데코 등)도 규칙대로 거둔다. 되돌린 기록에는 '롤백(기록 #번호)'를 남겨 두 번 되돌리지 않는다.
namespace :game do
  desc 'Reset house points earned from the merit counter and refund merit item purchases (one time; dry run unless APPLY=1)'
  task undo_merit: :environment do
    apply = ENV['APPLY'] == '1'
    counter_name = ENV.fetch('COUNTER', '상점')
    since = Time.find_zone!('Asia/Seoul').parse(ENV.fetch('SINCE', '2026-10-20 18:05'))
    counter = GameCounter.find_by(name: counter_name)
    abort "누적 수치 '#{counter_name}' 이 없습니다." if counter.nil?

    raises_counter = lambda do |item|
      item.effects_list.any? do |effect|
        effect['type'] == 'counter' && effect['counter_id'].to_i == counter.id && !effect['value'].to_s.strip.start_with?('-') && effect['value'].to_s.match?(/[1-9]/)
      end
    end
    items = GameShopItem.all.select(&raises_counter).index_by { |item| Game::Wallet.key(item.name) }
    name_of = ->(account_id) { GameCharacter.for(Account.find(account_id)).display_name }

    puts "== #{apply ? '실행' : '미리보기 (바꾸는 것 없음)'} =="
    puts "누적 수치: #{counter.name}, 기준 시각: #{since.strftime('%Y-%m-%d %H:%M %Z')}"
    puts "'#{counter.name}'을 올리는 아이템: #{items.values.map(&:name).join(', ').presence || '없음'}"

    # ① 이 수치로 얻은 소속 점수
    points = GameHousePoint.where(game_counter_id: counter.id)
    puts "\n[소속 점수] #{counter.name}으로 바뀐 기록 #{points.count}건, 합계 #{points.sum(:amount)}점"
    points.includes(:house).group_by(&:house).each { |house, rows| puts "  #{house&.name}: #{rows.sum(&:amount)}점 (#{rows.size}건)" }

    # ② 기준 시각 이후 구입한 해당 아이템
    refunded = GameReward.where(kind: 'admin', actor: 'undo_merit').pluck(:reason).join("\n")
    bought = GameReward.where(kind: 'purchase', created_at: since..).order(:id).select do |reward|
      reward.items.any? { |item| item['count'].to_i.positive? && items.key?(Game::Wallet.key(item['name'])) }
    end
    purchases = bought.select { |reward| refunded.exclude?("환불(구매 ##{reward.id})") }
    puts "\n[환불] 기준 시각 이후 구입 #{purchases.size}건"
    purchases.each do |reward|
      list = reward.items.select { |item| items.key?(Game::Wallet.key(item['name'])) }.map { |item| "#{item['name']} ×#{item['count']}" }.join(', ')
      puts "  구입 ##{reward.id} #{reward.created_at.in_time_zone('Asia/Seoul').strftime('%m/%d %H:%M')} #{name_of.call(reward.account_id)}: #{list}, #{-reward.money} 환불"
    end

    # ③ 기준 시각 이후 구입(이미 환불한 것도)으로 쓴 아이템: 구입자가 기준 시각 이후에 써서 올린 상점 횟수 (구입한 개수만큼, 최근 사용부터)
    #   '준 사람'(source_account_id)은 10-21 에 생긴 칸이라 그 전 기록에는 비어 있다 → 같은 때 남은 사용 기록(재화 기록 kind 'use')의 계정으로 찾는다
    done = GameCounterLog.where(actor: 'undo_merit').pluck(:reason).join("\n")
    source_of = lambda do |log|
      log.source_account_id || GameReward.where(kind: 'use', reason: log.reason, created_at: (log.created_at - 10.seconds)..(log.created_at + 10.seconds)).pick(:account_id)
    end
    need = Hash.new(0)
    bought.each do |reward|
      reward.items.each do |item|
        key = Game::Wallet.key(item['name'])
        need[[reward.account_id, key]] += item['count'].to_i if items.key?(key) && item['count'].to_i.positive?
      end
    end
    rollbacks = need.flat_map do |(account_id, key), count|
      item = items[key]
      logs = GameCounterLog.where(game_counter_id: counter.id, source_account_id: [account_id, nil], created_at: since..)
                           .where('delta > 0').where('reason LIKE ?', "#{GameCounterLog.sanitize_sql_like(item.name)}%").order(id: :desc).to_a
                           .select { |log| source_of.call(log) == account_id }
      # 이미 되돌린 기록도 구입한 개수에 넣는다 (다시 실행해도 더 되돌리지 않게)
      rolled, left = logs.partition { |log| done.include?("롤백(기록 ##{log.id})") }
      left.first([count - rolled.size, 0].max)
    end
    puts "\n[상점 횟수 되돌리기] 아이템을 써서 올린 기록 #{rollbacks.size}건"
    rollbacks.each do |log|
      character = GameCharacter.for(Account.find(log.account_id))
      puts "  기록 ##{log.id} #{name_of.call(source_of.call(log))} → #{name_of.call(log.account_id)}: #{counter.name} #{log.delta} 되돌림 (지금 누적 #{counter.raw_for(character)}회)"
    end

    unless apply
      puts "\n실제로 실행하려면: APPLY=1 bin/rails game:undo_merit"
      next
    end

    backup = { counter: counter.name, since: since.iso8601, points: points.map(&:attributes), refunds: [], counter_rollbacks: [] }
    GameHousePoint.transaction do
      points.delete_all
      purchases.each do |reward|
        account = Account.find(reward.account_id)
        removed = {}
        reward.items.each do |item|
          next unless items.key?(Game::Wallet.key(item['name'])) && item['count'].to_i.positive?

          held = Array(GameCharacter.for(account).reload.inventory).find { |entry| Game::Wallet.key(entry['name']) == Game::Wallet.key(item['name']) }.to_h['count'].to_i
          removed[item['name']] = -[held, item['count'].to_i].min
        end
        removed.reject! { |_, count| count.zero? }
        refund = [-reward.money, 0].max
        next if refund.zero? && removed.empty?

        Game::Wallet.apply!([{ account: account, money: refund, items: removed }], kind: 'admin', detail: "환불(구매 ##{reward.id}) #{reward.reason}".truncate(500), actor: 'undo_merit')
        backup[:refunds] << { reward_id: reward.id, account_id: account.id, money: refund, items_removed: removed }
      end

      rollbacks.each do |log|
        character = GameCharacter.for(Account.find(log.account_id))
        counter.add!(character, -log.delta, reason: "롤백(기록 ##{log.id}) #{log.reason}".truncate(200), actor: 'undo_merit')
        backup[:counter_rollbacks] << { log_id: log.id, account_id: log.account_id, source_account_id: source_of.call(log), delta: log.delta }
      end
    end

    path = Rails.root.join('tmp', "undo_merit_#{Time.current.strftime('%Y%m%d%H%M%S')}.json")
    File.write(path, JSON.pretty_generate(backup))
    puts "\n완료: 소속 점수 기록 #{backup[:points].size}건 삭제, 환불 #{backup[:refunds].size}건, 상점 횟수 되돌림 #{backup[:counter_rollbacks].size}건. 기록: #{path}"
  end
end
