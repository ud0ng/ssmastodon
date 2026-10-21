# frozen_string_literal: true

require 'rails_helper'

# 트라이위저드 미로 (웹 전용, 2~4명): 이동·생물·만남 모두 시스템에게 DM 으로 고른다
RSpec.describe Game::Web::Maze do
  let!(:system) { Fabricate(:account, username: 'system') }
  let!(:harry) { Fabricate(:account, username: 'harry') }
  let!(:cedric) { Fabricate(:account, username: 'cedric') }
  let!(:fleur) { Fabricate(:account, username: 'fleur') }

  def toot(account, text, visibility: 'private')
    status = PostStatusService.new.call(account, text: text, visibility: visibility)
    Game::Engine.new(status).call
    status
  end

  def dm(account, text)
    toot(account, "@system #{text}", visibility: 'direct')
  end

  def session
    GameSession.where(kind: 'maze').order(:id).last.reload
  end

  def start!
    toot(harry, '@system @cedric @fleur [미로]')
    toot(cedric, '@system [수락]')
    toot(fleur, '@system [수락]')
  end

  # 벽 없는 빈 미로에 사람 위치만 정한다 (기본은 함정·생물 없음)
  def open_field!(positions, cup: [7, 7], **extra)
    current = session
    current.state.merge!('traps' => [], 'creatures' => [], 'cup' => cup, 'cells' => Array.new(current.state['width'] * current.state['height'], 15),
                         'positions' => positions, 'phase' => 'move', 'moves' => {}, **extra.transform_keys(&:to_s))
    current.save!
  end

  def everyone_stays(except: [])
    { harry => '[대기]', cedric => '[대기]', fleur => '[대기]' }.each { |account, text| dm(account, text) unless except.include?(account) }
  end

  it 'invites several opponents, starts when everyone accepts and asks each player for a move by DM' do
    start!

    expect(session).to have_attributes(status: 'active', turn: 1)
    expect(session.players.map(&:account)).to eq [harry, cedric, fleur]
    expect(session.state['positions'].values.uniq.size).to eq 3
    
    expect(session.messages.where.not(account_id: nil).count).to eq 3 # 이동 안내는 툿이 아니라 웹 메시지
    expect(Status.where(account: system, visibility: :direct).count).to eq 0
  end

  it 'refuses more opponents than allowed' do
    others = %w(a1 a2 a3).map { |name| Fabricate(:account, username: name) }
    toot(harry, "@system #{others.map { |a| "@#{a.username}" }.join(' ')} @cedric [미로]")

    expect(GameSession.where(kind: 'maze')).to be_empty
  end

  it 'builds a connected maze of the configured size and shows each player only what is near' do
    Game::Config.update!('maze', 'width' => '14', 'height' => '15')
    start!
    view = described_class.new(session).view_for(session.players.first)

    expect([view[:width], view[:height]]).to eq [14, 15]
    expect(view[:position]).to eq [0, 0]
    expect(view[:cells].size).to eq 9
    expect(view[:cup]).to be_nil
    expect(view[:inventory]).to eq(portkey: 1, lumos: 1)

    cells = session.state['cells']
    seen = [0]
    queue = [[0, 0]]
    until queue.empty?
      x, y = queue.shift
      described_class::DIRS.each_value do |dx, dy, bit, _|
        next unless cells[(y * 14) + x].anybits?(bit)

        index = ((y + dy) * 14) + x + dx
        next if seen.include?(index)

        seen << index
        queue << [x + dx, y + dy]
      end
    end
    expect(seen.size).to eq 210
  end

  it 'lists the squares a player can click and moves everyone once all have sent their DM' do
    start!
    open_field!({ '0' => [3, 3], '1' => [14, 14], '2' => [0, 14] })
    cells = described_class.new(session).view_for(session.players.first)[:reachable].map { |cell| [cell[:x], cell[:y]] }

    expect(cells).to include([5, 3], [4, 4], [3, 1])
    expect(cells).not_to include([6, 3])

    dm(harry, '[이동/동/동]')
    expect(session.turn).to eq 1
    everyone_stays(except: [harry])

    expect(session.state['positions']['0']).to eq [5, 3]
    expect(session.turn).to eq 2
  end

  it 'refuses a move that is too long' do
    start!
    open_field!({ '0' => [3, 3], '1' => [14, 14], '2' => [0, 14] })
    dm(harry, '[이동/동/동/동]')

    expect(session.state['moves']).to eq({})
    expect(session.messages.where(account: harry).order(:id).last.text).to include('갈 수 없는 길')
  end

  it 'ends with the first player to reach the cup' do
    start!
    open_field!({ '0' => [6, 7], '1' => [0, 14], '2' => [14, 0] })

    dm(harry, '[이동/동]')
    everyone_stays(except: [harry])

    expect(session.status).to eq 'finished'
    expect(session.player_for(harry).result).to eq 'win'
    expect(session.player_for(cedric).result).to eq 'lose'
  end

  it 'gives a joint win when two players reach the cup in the same turn and splits the points' do
    start!
    open_field!({ '0' => [6, 7], '1' => [8, 7], '2' => [0, 0] })
    allow(Game::Points).to receive(:award).and_call_original

    dm(harry, '[이동/동]')
    dm(cedric, '[이동/서]')
    dm(fleur, '[대기]')

    expect(session.status).to eq 'finished'
    expect([session.player_for(harry).result, session.player_for(cedric).result]).to eq %w(win win)
    expect(session.player_for(fleur).result).to eq 'lose'
    expect(Game::Points).to have_received(:award).with(anything, anything, 3, outcome: 'win').twice
  end

  it 'makes a trap stop a player for a turn and remembers it for that player only' do
    start!
    open_field!({ '0' => [3, 3], '1' => [14, 14], '2' => [0, 14] }, traps: [[4, 3]])

    dm(harry, '[이동/동/동]')
    everyone_stays(except: [harry])

    expect(session.state['positions']['0']).to eq [4, 3]
    expect(session.state.dig('status', '0', 'stunned')).to eq 1
    expect(described_class.new(session).view_for(session.players.first)[:traps]).to eq [{ x: 4, y: 3 }]
    expect(described_class.new(session).view_for(session.players.last)[:traps]).to eq []
  end

  it 'asks for a spell when meeting a creature, removes it when beaten and lets the player continue' do
    start!
    open_field!({ '0' => [3, 3], '1' => [14, 14], '2' => [0, 14] }, creatures: [[4, 3, '스크루트']])
    allow_any_instance_of(described_class).to receive(:creature_spell).and_return('disarm')

    dm(harry, '[이동/동/동]')
    everyone_stays(except: [harry])

    expect(session.state['phase']).to eq 'fight'
    expect(session.state['positions']['0']).to eq [4, 3]

    dm(harry, '[공격]')

    expect(session.state['creatures']).to eq []
    expect(session.state['positions']['0']).to eq [5, 3]
    expect(session.state.dig('status', '0', 'boost')).to be true
  end

  it 'lets a creature injure a player who loses' do
    start!
    open_field!({ '0' => [3, 3], '1' => [14, 14], '2' => [0, 14] }, creatures: [[4, 3, '스크루트']])
    allow_any_instance_of(described_class).to receive(:creature_spell).and_return('attack')

    dm(harry, '[이동/동]')
    everyone_stays(except: [harry])
    dm(harry, '[무장해제]')

    expect(session.state.dig('status', '0', 'stunned')).to eq 1
    expect(session.state['creatures'].size).to eq 1
  end

  it 'resolves a meeting by secret stance and marks the hinderer as hostile' do
    start!
    open_field!({ '0' => [3, 3], '1' => [5, 3], '2' => [14, 14] })

    dm(harry, '[이동/동]')
    dm(cedric, '[대기]')
    dm(fleur, '[대기]')

    expect(session.state['phase']).to eq 'meet'
    dm(harry, '[방해]')
    dm(cedric, '[협력]')

    state = session.state
    expect(state.dig('status', '1', 'stunned')).to eq 1
    expect(state.dig('status', '0', 'stunned')).to be_nil
    expect(state['hostile']).to eq ['0-1']
    expect(session.turn).to eq 2
  end

  it 'shares maps when both cooperate' do
    start!
    open_field!({ '0' => [3, 3], '1' => [3, 4], '2' => [14, 14] })
    current = session
    current.state['seen']['1'] = [1000]
    current.save!

    everyone_stays
    dm(harry, '[협력]')
    dm(cedric, '[협력]')

    expect(session.state['seen']['0']).to include(1000)
  end

  it 'fights a known hostile player with spells and gives the winner the loser map' do
    start!
    open_field!({ '0' => [3, 3], '1' => [3, 4], '2' => [14, 14] }, hostile: ['0-1'])
    current = session
    current.state['seen']['1'] = [1000]
    current.save!

    everyone_stays
    dm(harry, '[공격]')
    dm(cedric, '[무장해제]')

    state = session.state
    expect(state['seen']['0']).to include(1000)
    expect(state.dig('status', '1', 'stunned')).to eq 2
  end

  it 'shows spectators and finished games everything: the whole maze, cup, traps, creatures, every position and path' do
    start!
    open_field!({ '0' => [3, 3], '1' => [14, 14], '2' => [0, 14] }, traps: [[4, 3]], creatures: [[6, 6, '스크루트']], trails: { '0' => [[3, 3]] })

    view = described_class.new(session).view_for(nil)
    expect(view).to include(revealed: true, spectator: true, cup: [7, 7])
    expect(view[:cells].size).to eq 225
    expect(view[:traps]).to eq [{ x: 4, y: 3 }]
    expect(view[:creatures].size).to eq 1
    expect(view[:players].map { |p| [p[:x], p[:y]] }).to eq [[3, 3], [14, 14], [0, 14]]
    expect(view[:trails]).to include('0' => [[3, 3]])
    expect(described_class.spectatable?).to be true

    dm(harry, '[대기]')
    everyone_stays(except: [harry])
    session.update!(status: 'finished')
    expect(described_class.new(session).view_for(session.players.first)).to include(revealed: true, spectator: false)
  end

  it 'uses a portkey once to point toward the cup and lumos to widen the view' do
    start!
    open_field!({ '0' => [3, 3], '1' => [14, 14], '2' => [0, 14] }, cup: [10, 3])

    dm(harry, '[포트키]')
    dm(harry, '[루모스]')
    dm(harry, '[포트키]')

    view = described_class.new(session).view_for(session.players.first)
    expect(view[:hint][:direction]).to eq '→'
    expect(view[:inventory]).to eq(portkey: 0, lumos: 0)
    expect(view[:vision]).to eq 3
    expect(view[:cells].size).to eq 49
  end
end
