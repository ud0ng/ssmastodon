# frozen_string_literal: true

require 'rails_helper'

# 덤블도어의 군대 (웹 전용 이벤트, 5~24명, 아발론형): 대원 고르기 → 공개 투표 → 비밀 성공/방해 카드 → 임무 3개, 마지막에 첩자의 해리 지목
RSpec.describe Game::Web::DumbledoresArmy do
  let!(:system) { Fabricate(:account, username: 'system') }
  let(:accounts) { Array.new(24) { |index| Fabricate(:account, username: "student#{index}") } }

  before do
    allow(Game::System).to receive(:account).and_return(system)
    allow(Game::Engine).to receive(:set_deadline_in!)
  end

  def session
    GameSession.where(kind: 'dumbledores_army').order(:id).last.reload
  end

  def kind
    described_class.new(session)
  end

  def start_game!(count = 5, test: false)
    current = GameSession.create!(kind: 'dumbledores_army', status: 'lobby', visibility: 'private', state: { 'mode' => 'event', 'test' => test || nil }.compact)
    accounts.first(count).each_with_index { |account, seat| current.players.create!(account: account, seat: seat, state: { 'accepted' => true }) }
    Game::Lobby.start!(current.reload)
  end

  def act(seat, command, args = [])
    account = accounts[seat]
    Game::WebCommand.play(session, account, command, args)
  end

  def roles
    session.state['roles'].transform_keys(&:to_i)
  end

  def spies
    roles.select { |_, role| role == 'spy' }.keys.sort
  end

  def leader
    kind.send(:leader_seat)
  end

  def vote_all!(choice, except: [])
    (0...session.players.size).each { |seat| act(seat, choice, []) unless except.include?(seat) }
  end

  # 대원을 정하고 투표를 통과시킨 다음 모두 카드를 낸다. sabotage: 방해를 낼 첩자 자리들
  def run_mission!(team: nil, sabotage: [])
    size = kind.send(:team_size)
    team ||= (0...session.players.size).to_a.first(size)
    act(leader, '대원', team.map(&:to_s))
    vote_all!('찬성')
    kind.timeout! # 투표 결과 공개가 끝나면 임무
    team.each { |seat| act(seat, sabotage.include?(seat) ? '방해' : '성공') }
    team
  end

  it 'deals a third of the players (rounded up) as spies, one hidden Harry and a Ron from 16 players' do
    {5 => 2, 6 => 2, 7 => 3, 8 => 3, 10 => 4, 15 => 5, 16 => 6, 20 => 7, 24 => 8}.each do |count, spy_count|
      expect(described_class.spy_count(count)).to eq spy_count
    end

    start_game!(5)
    expect(session.state['roles'].values.tally).to include('spy' => 2, 'harry' => 1, 'da' => 2)
    expect(session.state['roles'].values).not_to include('ron')

    start_game!(16)
    expect(session.state['roles'].values.tally).to include('spy' => 6, 'harry' => 1, 'ron' => 1)
  end

  it 'uses the mission team sizes of the rules table and the 2-sabotage exceptions' do
    expect(described_class.team_sizes(5)).to eq [2, 3, 2, 3, 3]
    expect(described_class.team_sizes(6)).to eq [2, 3, 4, 3, 4]
    expect(described_class.team_sizes(7)).to eq [2, 3, 3, 4, 4]
    expect(described_class.team_sizes(9)).to eq [3, 4, 4, 5, 5]
    expect(described_class.team_sizes(12)).to eq [4, 5, 5, 6, 6]
    expect(described_class.team_sizes(18)).to eq [5, 6, 6, 7, 7]
    expect(described_class.team_sizes(24)).to eq [6, 7, 7, 8, 8]

    expect(described_class.sabotage_needed(5, 4, 3)).to eq 1
    expect(described_class.sabotage_needed(7, 4, 4)).to eq 2 # 7명 이상의 4번째 임무
    expect(described_class.sabotage_needed(7, 3, 3)).to eq 1
    expect(described_class.sabotage_needed(16, 2, 6)).to eq 2 # 대원 6명 이상
  end

  it 'only lets the leader pick exactly the right number of members, then everyone votes openly' do
    start_game!(5)
    expect(session.state['phase']).to eq 'team'
    non_leader = (0..4).find { |seat| seat != leader }

    act(non_leader, '대원', %w(0 1))
    expect(session.state['phase']).to eq 'team' # 리더가 아니면 안 된다
    act(leader, '대원', %w(0 1 2))
    expect(session.state['phase']).to eq 'team' # 첫 임무는 2명

    act(leader, '대원', %w(0 1))
    expect(session.state['phase']).to eq 'vote'
    act(0, '찬성')
    expect(kind.view_for(session.players.find_by(seat: 1))[:players].pluck(:vote)).to all(be_nil) # 다 모이기 전에는 비공개
    vote_all!('찬성', except: [0])
    expect(session.state['phase']).to eq 'vote_result'
    expect(kind.view_for(session.players.find_by(seat: 1))[:players].pluck(:vote)).to all(eq('yes'))
  end

  it 'rejects a team when more than half vote no, moves the leader on and ends in a spy win after five rejections' do
    start_game!(5)
    first_leader = leader
    4.times do
      act(leader, '대원', %w(0 1))
      vote_all!('반대')
      kind.timeout!
    end
    expect(session.state['rejects']).to eq 4
    expect(leader).not_to eq first_leader

    act(leader, '대원', %w(0 1))
    vote_all!('반대')
    kind.timeout!

    expect(session).to have_attributes(status: 'finished')
    expect(session.state).to include('winner' => 'spy', 'reason' => 'rejects')
  end

  it 'passes a tied vote (rejected only by a majority) and lets only spies sabotage' do
    start_game!(6)
    spy = spies.first
    da = (0..5).find { |seat| roles[seat] != 'spy' }
    act(leader, '대원', [spy, da].map(&:to_s))
    (0..2).each { |seat| act(seat, '반대') }
    (3..5).each { |seat| act(seat, '찬성') }
    expect(session.state['vote_result']).to include('passed' => true)
    kind.timeout!
    expect(session.state['phase']).to eq 'mission'

    act(da, '방해')
    expect(session.state['cards']).not_to have_key(da.to_s) # 첩자만 방해를 낼 수 있다
    act(da, '성공')
    act(spy, '방해')

    expect(session.state['phase']).to eq 'result'
    result = session.state['results'].last
    expect(result).to include('sabotage' => 1, 'success' => false, 'need' => 1)
    expect(result['cards']).to match_array(%w(success sabotage)) # 카드 장수만, 누가 냈는지는 없다
    expect(result).not_to have_key('by')
  end

  it 'fails a mission only with two sabotages when two are needed' do
    start_game!(7)
    session_state = session
    session_state.state['mission'] = 4
    session_state.save!
    team = spies.first(1) + (0..6).reject { |seat| roles[seat] == 'spy' }.first(3)
    act(leader, '대원', team.map(&:to_s))
    vote_all!('찬성')
    kind.timeout!
    team.each { |seat| act(seat, spies.include?(seat) ? '방해' : '성공') }

    expect(session.state['results'].last).to include('sabotage' => 1, 'need' => 2, 'success' => true)
  end

  it 'shows each role only what it may know' do
    start_game!(16)
    spy = session.players.find_by(seat: spies.first)
    harry_seat = roles.key('harry')
    ron_seat = roles.key('ron')
    da_seat = roles.select { |_, role| role == 'da' }.keys.first

    spy_view = kind.view_for(spy)
    expect(spy_view[:players].select { |entry| entry[:role] }.pluck(:seat)).to match_array(spies)

    harry_view = kind.view_for(session.players.find_by(seat: harry_seat))
    expect(harry_view[:players].select { |entry| entry[:role] == 'spy' }.pluck(:seat)).to match_array(spies)

    ron_view = kind.view_for(session.players.find_by(seat: ron_seat))
    expect(ron_view[:players].select { |entry| entry[:role] }.pluck(:seat, :role)).to match_array([[harry_seat, 'harry']])

    expect(kind.view_for(session.players.find_by(seat: da_seat))[:players].pluck(:role).compact).to be_empty
    expect(kind.view_for(nil, staff: true)[:players].pluck(:role)).to all(be_present) # 운영진 관전은 전부
    expect(kind.view_for(nil)[:players].pluck(:role).compact).to be_empty
  end

  it 'wins for the army after three successes when the spies miss Harry, and for the spies when they hit' do
    start_game!(5)
    3.times { run_mission!; kind.timeout! }

    expect(session.state['phase']).to eq 'assassin'
    harry_seat = roles.key('harry')
    wrong = (0..4).find { |seat| roles[seat] == 'da' }
    spies.each { |seat| act(seat, '지목', [wrong.to_s]) }
    expect(session).to have_attributes(status: 'finished')
    expect(session.state).to include('winner' => 'da', 'reason' => 'guess_miss')

    start_game!(5)
    3.times { run_mission!; kind.timeout! }
    harry_seat = roles.key('harry')
    spies.each { |seat| act(seat, '지목', [harry_seat.to_s]) }
    expect(session.state).to include('winner' => 'spy', 'reason' => 'guess')
  end

  it 'wins for the spies after three failed missions' do
    start_game!(5)
    3.times do
      size = kind.send(:team_size)
      team = (spies.first(1) + (0..4).reject { |seat| spies.first(1).include?(seat) }).first(size)
      run_mission!(team: team, sabotage: spies.first(1))
      kind.timeout!
    end

    expect(session.state).to include('winner' => 'spy', 'reason' => 'missions')
  end

  it 'never stalls: a leader who does not pick, silent voters and missing cards are filled in when time runs out' do
    start_game!(5)
    kind.timeout! # 리더가 안 골랐다 → 무작위 대원, 리더 포함
    expect(session.state['phase']).to eq 'vote'
    expect(session.state['team']).to include(leader)

    kind.timeout! # 투표를 안 했다 → 모두 찬성
    expect(session.state['vote_result']).to include('passed' => true)
    kind.timeout!
    kind.timeout! # 카드를 안 냈다 → 성공
    expect(session.state['results'].last).to include('success' => true, 'sabotage' => 0)
  end

  it 'gives points and rewards to the winning side, but nothing in a test play' do
    Game::Config.update!('dumbledores_army', 'points_win' => '10')
    house = GameHouse.create!(name: '그리핀도르', emoji: '🦁')
    accounts.first(5).each { |account| GameCharacter.for(account).update!(house: house) }
    start_game!(5)
    3.times { run_mission!; kind.timeout! }
    spies.each { |seat| act(seat, '지목', [roles.key('harry').to_s]) }

    expect(GameHousePoint.where(game_session_id: session.id).sum(:amount)).to eq 20 # 첩자 2명 × 10

    start_game!(5, test: true)
    3.times { run_mission!; kind.timeout! }
    spies.each { |seat| act(seat, '지목', [roles.key('harry').to_s]) }
    expect(session.status).to eq 'finished'
    expect(GameHousePoint.where(game_session_id: session.id).count).to eq 0
  end
end
