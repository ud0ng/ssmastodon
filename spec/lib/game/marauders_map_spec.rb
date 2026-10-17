# frozen_string_literal: true

require 'rails_helper'

# 도둑 지도 (웹 전용, 학생 1 vs 사감): 학생이 먼저 → 사감 팀 동시, 모두 시스템에게 DM 으로 고른다
RSpec.describe Game::Web::MaraudersMap do
  let!(:system) { Fabricate(:account, username: 'system') }
  let!(:harry) { Fabricate(:account, username: 'harry') }
  let!(:minerva) { Fabricate(:account, username: 'minerva') }
  let!(:severus) { Fabricate(:account, username: 'severus') }

  def toot(account, text, visibility: 'private')
    status = PostStatusService.new.call(account, text: text, visibility: visibility)
    Game::Engine.new(status).call
    status
  end

  def dm(account, text)
    toot(account, "@system #{text}", visibility: 'direct')
  end

  def session
    GameSession.where(kind: 'marauders_map').order(:id).last.reload
  end

  def kind
    described_class.new(session)
  end

  def start!
    toot(harry, '@system @minerva @severus [도둑지도]')
    toot(minerva, '@system [수락]')
    toot(severus, '@system [수락]')
  end

  # 5x5 격자에서 계단·막힌 길·비밀 통로 없이 위치만 정한다
  def plain_map!(positions, **extra)
    current = session
    current.state.merge!('blocked' => [], 'stairs_a' => [], 'stairs_b' => [], 'secret' => [], 'positions' => positions, **extra.transform_keys(&:to_s))
    current.save!
  end

  it 'builds a connected 5x5 map by default and starts with the student first' do
    start!

    expect(session).to have_attributes(status: 'active', turn: 1)
    expect(session.state['width']).to eq 5
    expect(session.state['phase']).to eq 'student'
    expect(session.state['targets'].size).to eq 3 # 사감 2명은 밸런스 인원(3) 미만이라 기본 목표 3곳
  end

  it 'keeps the targets secret from the prefects (public card and view)' do
    start!
    plain_map!({ '0' => 0, '1' => 12, '2' => 13 })

    expect(kind.card_data.keys).not_to include('targets')
    expect(kind.view_for(session.players.to_a[1])[:targets]).to eq []
    expect(kind.view_for(session.players.first)[:targets].size).to eq session.state['targets'].size
  end

  it 'asks the prefects only after the student has chosen and then resolves together' do
    start!
    plain_map!({ '0' => 0, '1' => 12, '2' => 13 }, 'targets' => [24, 23, 22])

    dm(minerva, '[이동/대연회장]')
    expect(session.state['moves']).to eq({}) # 아직 학생 차례

    dm(harry, '[이동/그리핀도르 휴게실]')
    expect(session.state['phase']).to eq 'prefects'

    dm(minerva, '[숨기]')
    dm(severus, '[숨기]')

    expect(session.turn).to eq 2
    expect(session.state['positions']['0']).to eq 1
    expect(session.state['phase']).to eq 'student'
  end

  it 'refuses a room that is not next to the player' do
    start!
    plain_map!({ '0' => 0, '1' => 12, '2' => 13 })
    dm(harry, '[이동/정문]')

    expect(session.state['moves']).to eq({})
  end

  it 'catches the student when a prefect enters the same room and gives the prefects the win' do
    start!
    plain_map!({ '0' => 11, '1' => 12, '2' => 24 }, 'targets' => [20, 21, 22])

    dm(harry, '[숨기]')
    dm(minerva, '[이동/마법약 교실]')
    dm(severus, '[숨기]')

    expect(session.status).to eq 'finished'
    expect(session.player_for(harry).result).to eq 'lose'
    expect(session.player_for(minerva).result).to eq 'win'
  end

  it 'lets the student win after visiting all targets' do
    start!
    plain_map!({ '0' => 0, '1' => 24, '2' => 23 }, 'targets' => [1], 'visited' => [])

    dm(harry, '[이동/그리핀도르 휴게실]')
    dm(minerva, '[숨기]')
    dm(severus, '[숨기]')

    expect(session.status).to eq 'finished'
    expect(session.player_for(harry).result).to eq 'win'
  end

  it 'leaves a footprint on a secret passage unless cloaked, and the cloak hides it' do
    start!
    plain_map!({ '0' => 0, '1' => 24, '2' => 23 }, 'targets' => [10, 11, 13], 'secret' => [[0, 21]])

    dm(harry, '[투명망토]')
    dm(harry, '[이동/비밀의 방 입구]')
    dm(minerva, '[숨기]')
    dm(severus, '[숨기]')
    expect(session.state['clues']).to eq([])

    plain_map!(session.state['positions'], 'cloak' => 0, 'secret' => [[21, 0]])
    dm(harry, '[이동/천문탑]')
    dm(minerva, '[숨기]')
    dm(severus, '[숨기]')
    expect(session.state['clues'].map { |clue| clue['kind'] }).to include('footprint')
  end

  it 'answers a revelio only with whether the student is within range' do
    start!
    plain_map!({ '0' => 0, '1' => 2, '2' => 24 }, 'targets' => [10, 11, 13])

    dm(harry, '[숨기]')
    dm(minerva, '[레벨리오]')
    dm(minerva, '[숨기]')
    dm(severus, '[숨기]')

    expect(session.state['clues'].last).to include('kind' => 'revelio', 'found' => true)
    expect(session.state['revelio_left']['1']).to eq 0
  end

  it 'relays the prefect team chat only to the other prefects and never to the student' do
    start!
    plain_map!({ '0' => 0, '1' => 12, '2' => 13 })

    dm(minerva, '[팀채팅/정문 쪽으로 몰자]')

    expect(kind.view_for(session.players.to_a[2])[:team_chat]).to eq([{ 'name' => minerva.username, 'text' => '정문 쪽으로 몰자' }])
    expect(kind.view_for(session.players.first)[:team_chat]).to eq []
    relayed = Status.where(account: system, visibility: :direct).select { |status| status.text.include?('정문 쪽으로 몰자') }
    expect(relayed.map { |status| status.mentions.map(&:account_id) }.flatten).to eq [severus.id]
    dm(harry, '[팀채팅/난 학생]')
    expect(session.state['team_chat'].size).to eq 1
  end

  it 'reduces the targets and adds cloaks when there are many prefects' do
    extra = %w(a1 a2).map { |name| Fabricate(:account, username: name) }
    toot(harry, "@system @minerva @severus @#{extra.first.username} [도둑지도]")
    [minerva, severus, extra.first].each { |account| toot(account, '@system [수락]') }

    expect(session.state['targets'].size).to eq 2
    expect(session.state['cloaks_left']).to eq 2
  end
end
