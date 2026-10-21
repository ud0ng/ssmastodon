# 운영진(owner)이 비행 대결 이벤트를 열고 참가자를 모아 끝까지 진행하는 데모 (미리보기 서버, 화면으로 지켜보기용)
#   docker compose -f dev/preview/docker-compose.yml exec -T web bin/rails runner /dev/stdin < dev/preview/event_demo.rb
$stdout.sync = true
owner = User.find_by(email: 'owner@preview.test').account
kind = Game::Kinds.registry['flying']
GameSession.open.where(kind: 'flying').each { |s| s.update!(status: 'cancelled') }
bots = %w(cedric draco luna neville goyle).filter_map { |name| Account.find_by(username: name) }

session = Game::Events::Opening.open!(kind, owner)
puts "열었습니다: /system/sessions/#{session.id}"
sleep 8
bots.each do |bot|
  next if session.reload.players.exists?(account_id: bot.id)

  session.players.create!(account: bot, seat: (session.players.maximum(:seat) || -1) + 1, state: { 'accepted' => true })
  puts "참가: #{bot.username}"
  sleep 4
end
sleep 6
session.reload.kind_class.new(session).recruitment_over!
session.reload
puts "대기방: #{session.status}"

# 봇은 알아서 준비, owner 는 화면에서 [준비하기] (45초 안에 안 누르면 대신)
sleep 6
bots.each { |bot| session.with_lock { Game::Lobby.set_ready!(session.reload, bot, true) }; sleep 2 }
45.times { break if session.reload.lobby? && Game::Lobby.ready_ids(session).include?(owner.id); sleep 1 }
session.with_lock { Game::Lobby.set_ready!(session.reload, owner, true) } unless Game::Lobby.ready_ids(session.reload).include?(owner.id)
puts '모두 준비'
until session.reload.status == 'active'
  sleep 1
  break if session.status == 'cancelled'
end

# 진행: 라운드마다 봇은 몇 초 뒤 길을 고르고, owner 는 화면에서 고른다 (30초 안에 안 고르면 대신)
round = 0
while session.reload.status == 'active'
  round += 1
  lanes = session.state['lanes'].to_i
  alive = session.players.select { |p| session.state['alive'].nil? || Array(session.state['alive']).map(&:to_s).include?(p.seat.to_s) }
  puts "라운드 #{round}: 길 #{lanes}개, 생존 #{alive.size}명"
  sleep 4
  alive.each do |player|
    next if player.account_id == owner.id

    Game::WebCommand.play(session.reload, player.account, '비행', [(rand(lanes) + 1).to_s])
    sleep 2
  end
  30.times { break unless session.reload.status == 'active'; break if session.state['history'].to_a.size >= round; sleep 1 }
  next unless session.reload.status == 'active' && session.state['history'].to_a.size < round

  Game::WebCommand.play(session.reload, owner, '비행', [(rand(lanes) + 1).to_s])
  sleep 5
end
puts "끝: #{session.reload.status}"
