# 미리보기 컨텐츠 점검: 진짜 툿(sidekiq 처리)으로 컨텐츠마다 신청 → 진행 → 끝(또는 첫 턴)까지 돌려 본다.
#   docker compose -f dev/preview/docker-compose.yml exec -T web bin/rails runner dev/preview/smoke.rb
# 판을 짧게 하려고 미리보기 설정을 바꾼다 (끝나면 되돌린다). owner·luna·draco·ron·goyle 계정이 있어야 한다.

def account(name) = Account.find_local(name) || raise("계정 없음: #{name}")

def settle
  60.times do
    sleep 0.3
    break if Sidekiq::Queue.all.sum(&:size).zero? && Sidekiq::Workers.new.size.zero?
  end
  sleep 0.5
end

# 판 스레드에 답장(공개) 또는 시스템에게 DM
def say(user, text, session: nil, dm: false, application: nil)
  thread = session && !dm ? Status.find_by(id: session.reload.last_status_id) : nil
  PostStatusService.new.call(account(user), text: text, thread: thread, visibility: dm ? 'direct' : 'private', application: application)
  settle
end

def latest(kind) = GameSession.where(kind: kind).order(:id).last

def reset!
  GameSession.where(status: %w(pending active)).update_all(status: 'cancelled')
end

def notified?(session)
  status = Status.find_by(id: session.reload.last_status_id)
  return false if status.nil?

  status.mentions.all? { |mention| Notification.exists?(activity: mention) }
end

# 1:1 컨텐츠: 신청·수락 뒤 끝날 때까지 (move 가 한 턴을 보낸다)
def duel_flow(kind, command, players: %w(owner luna), limit: 12)
  reset!
  say(players.first, "@system #{players.drop(1).map { |name| "@#{name}" }.join(' ')} [#{command}]")
  session = latest(kind)
  return "신청 안 됨 (#{Status.where(account: account('system')).order(:id).last&.text.to_s.lines.last&.strip})" if session.nil?

  players.drop(1).each { |name| say(name, '@system [수락]', session: session) }
  return "수락 뒤 #{session.reload.status}" unless session.reload.status == 'active'

  limit.times do
    break if session.reload.status != 'active'

    yield session
  end
  session.reload
  rewards = GameReward.where(game_session_id: session.id).count
  "#{session.status}, #{session.turn}턴, 결과 #{session.players.map { |player| "#{player.account.username}:#{player.result || '-'}" }.join(' ')}, 보상 #{rewards}건, 알림 #{notified?(session) ? 'O' : 'X'}"
end

def current_user(session)
  session.players.find { |player| player.seat == session.state['seat'] }&.account&.username
end

saved = GameConfig.all.to_h { |config| [config.key, config.data.deep_dup] }
results = {}
check = lambda do |name, &block|
  results[name] = begin
    block.call
  rescue => e
    "오류: #{e.class} #{e.message.lines.first}"
  end
  puts "#{name}: #{results[name]}"
end

begin
  Game::Config.merge!('common', 'one_game_per_person' => true)

  Game::Config.merge!('jellybean', 'beans' => 2, 'worst_count' => 1, 'max_per_turn' => 1)
  check.call('젤리빈') { duel_flow('jellybean', '젤리빈') { |s| say(current_user(s), '@system [먹기]', session: s) } }

  Game::Config.merge!('gobstones', 'rounds' => 1)
  check.call('곱스톤') { duel_flow('gobstones', '곱스톤') { |s| say(current_user(s), '@system [약]', session: s) } }

  Game::Config.merge!('duel', 'hp' => 1)
  check.call('마법결투') do
    duel_flow('duel', '결투') do |s|
      say('owner', '@system [공격]', dm: true)
      say('luna', '@system [방어]', dm: true)
    end
  end

  Game::Config.merge!('potion', 'max_tries' => 1)
  check.call('물약') do
    duel_flow('potion', '물약') do |s|
      answer = s.reload.state['answer']
      # 번호로 보낸다 (재료 이름에 띄어쓰기가 있을 수 있다)
      shown = s.state['shown']
      say('owner', "@system [조합] #{answer.map { |name| shown.index(name) + 1 }.join(' ')}", dm: true)
      say('luna', "@system [조합] #{(1..answer.size).to_a.reverse.join(' ')}", dm: true)
    end
  end

  Game::Config.merge!('quidditch', 'max_turns' => 1, 'chase_rate' => 100)
  check.call('퀴디치 1:1') do
    duel_flow('quidditch', '퀴디치') do
      say('owner', '@system [추격]', dm: true)
      say('luna', '@system [몰이]', dm: true)
    end
  end
  check.call('퀴디치 2:2') do
    duel_flow('quidditch', '퀴디치', players: %w(owner ron draco goyle)) do
      %w(owner ron draco goyle).each { |name| say(name, '@system [추격]', dm: true) }
    end
  end

  # 웹 전용: 신청·수락 → 진행판 보기 → 모두 한 턴 보내면 다음 턴
  check.call('트라이위저드 미로') do
    reset!
    say('owner', '@system @luna [미로]')
    session = latest('maze')
    say('luna', '@system [수락]', session: session)
    session.reload
    kind = Game::Web::Maze.new(session)
    view = kind.view_for(session.players.first)
    session.players.each { |player| session.with_lock { Game::Web::Maze.new(session).submit_move!(player, [], 'cooperate') } }
    "#{session.reload.status}, 시야 #{view[:cells].size}칸, 한 턴 뒤 #{session.turn}턴"
  end

  check.call('도둑 지도') do
    reset!
    say('owner', '@system @luna [도둑지도]')
    session = latest('marauders_map')
    say('luna', '@system [수락]', session: session)
    session.reload
    view = Game::Web::MaraudersMap.new(session).view_for(session.players.first)
    session.players.each do |player|
      current = session.reload
      current.with_lock { Game::Web::MaraudersMap.new(current).submit_move!(current.players.find { |p| p.id == player.id }, [], '') }
    end
    "#{session.reload.status}, 방 #{view[:rooms].size}개, 한 턴 뒤 #{session.turn}턴"
  end

  check.call('비밀의방') do
    reset!
    say('owner', '@system [비밀의방]')
    session = latest('secret_chamber')
    next "열리지 않음 (#{Status.where(account: account('system')).order(:id).last&.text.to_s.lines.last&.strip})" if session.nil?

    %w(luna ron draco goyle).each { |name| say(name, '@system [참가]', session: session) }
    "#{session.reload.status}, 참가 #{session.players.count}명"
  end

  # 수업
  Game::Config.merge!('lessons', 'study_daily_limit' => 0)
  Game::Config.merge!('transfiguration', 'tries' => 1)
  check.call('변신술 자습') do
    reset!
    say('owner', '@system [자습/변신술]')
    session = latest('transfiguration')
    say('owner', '@system [약]', session: session)
    grade = GameGrade.where(session: session).last&.grade
    "#{session.reload.status}, 등급 #{grade || '-'}, 보상 #{GameReward.where(game_session_id: session.id).count}건"
  end

  Game::Config.merge!('practice', 'gain_min' => 100, 'gain_max' => 100)
  check.call('어둠의 마법 방어술 자습') do
    reset!
    say('owner', '@system [자습/어둠의 마법 방어술]')
    session = latest('practice')
    say('owner', '@system [연습]', session: session)
    "#{session.reload.status}, 등급 #{GameGrade.where(session: session).last&.grade || '-'}"
  end

  check.call('일반 마법 자습') do
    reset!
    say('owner', '@system [자습/일반 마법]')
    session = latest('levitation')
    "#{session.reload.status} (신호까지 기다리는 중, 신호 시각 #{session.deadline_at&.strftime('%H:%M:%S')})"
  end

  check.call('비행 수업 (시스템 계정으로 열기)') do
    reset!
    app = Doorkeeper::Application.find_by(name: 'Web') || Doorkeeper::Application.first
    say('system', '[수업/비행]', application: app)
    session = latest('flying')
    next '열리지 않음' if session.nil? || session.created_at < 1.minute.ago

    %w(owner luna ron draco).each { |name| say(name, '@system [참가]', session: session) }
    "#{session.reload.status}, 참가 #{session.players.count}명 (모집 끝나면 시작)"
  end
ensure
  reset!
  GameConfig.where.not(key: saved.keys).destroy_all
  saved.each { |key, data| GameConfig.find_or_initialize_by(key: key).update!(data: data) }
end

puts
puts results.map { |name, result| "#{name}: #{result}" }
