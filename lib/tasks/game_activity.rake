# frozen_string_literal: true

namespace :game do
  desc 'Build the daily activity snapshots (toot counts and chars per character per day, KST) from every past toot'
  task activity_backfill: :environment do
    Game::ActivitySnapshot.catch_up!(force: true)
    puts "완료: #{Game::ActivitySnapshot.first_day} ~ #{Game::ActivitySnapshot.today} (#{GameActivityDay.count}줄, 상대 캐릭터 #{GameActivityPair.count}줄)"
  end
end
