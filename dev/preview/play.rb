# 미리보기용 컨텐츠 진행 흉내 (sidekiq 이 처리하게 툿만 올린다)
#   bin/rails runner dev/preview/play.rb <명령 줄> …   예: "owner|@system @luna [젤리빈]" "luna|@system [수락]|reply"
# 'reply' 를 붙이면 그 판의 마지막 시스템 툿에 답장한다. 끝나면 판 상태를 찍는다.
ARGV.each do |line|
  username, text, mode = line.split('|')
  account = Account.find_local(username)
  session = GameSession.order(:id).last
  thread = mode == 'reply' && session ? Status.find_by(id: session.last_status_id) : nil
  visibility = mode == 'dm' ? 'direct' : 'private'
  PostStatusService.new.call(account, text: text, thread: thread, visibility: visibility)
  20.times do
    sleep 0.5
    break if Sidekiq::Queue.all.sum(&:size).zero?
  end
  sleep 1.5
end
session = GameSession.order(:id).last
puts "session=#{session&.id} #{session&.kind} #{session&.status} turn=#{session&.turn} seat=#{session&.state&.dig('seat')} root=#{session&.root_status_id} events=#{session&.events&.count}"
