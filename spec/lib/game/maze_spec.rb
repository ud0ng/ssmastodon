# frozen_string_literal: true

require 'rails_helper'

# 트라이위저드 미로 (웹 전용, 2~4명)
RSpec.describe Game::Web::Maze do
  let!(:system) { Fabricate(:account, username: 'system') }
  let!(:harry) { Fabricate(:account, username: 'harry') }
  let!(:cedric) { Fabricate(:account, username: 'cedric') }
  let!(:fleur) { Fabricate(:account, username: 'fleur') }

  def toot(account, text)
    status = PostStatusService.new.call(account, text: text, visibility: 'private')
    Game::Engine.new(status).call
    status
  end

  def session
    GameSession.where(kind: 'maze').order(:id).last
  end

  def kind
    described_class.new(session.reload)
  end

  def start!
    toot(harry, '@system @cedric @fleur [미로]')
    toot(cedric, '@system [수락]')
    toot(fleur, '@system [수락]')
  end

  it 'invites several opponents and starts when everyone accepts' do
    start!

    expect(session).to have_attributes(status: 'active', turn: 1)
    expect(session.players.map(&:account)).to eq [harry, cedric, fleur]
    expect(session.state['positions'].values.uniq.size).to eq 3
    expect(Status.where(account: system).map(&:text)).to include(a_string_including('/system/sessions/'))
  end

  it 'refuses more opponents than allowed' do
    others = %w(a1 a2 a3).map { |name| Fabricate(:account, username: name) }
    toot(harry, "@system #{others.map { |a| "@#{a.username}" }.join(' ')} @cedric [미로]")

    expect(GameSession.where(kind: 'maze')).to be_empty
  end

  it 'builds a connected maze and shows each player only what is near' do
    start!
    view = kind.view_for(session.players.first)

    expect(view[:size]).to eq 15
    expect(view[:position]).to eq [0, 0]
    expect(view[:cells].size).to be_between(1, 9)
    expect(view[:cup]).to be_nil

    # 모든 칸이 이어져 있다 (출발점에서 다 갈 수 있다)
    cells = session.state['cells']
    seen = [0]
    queue = [[0, 0]]
    until queue.empty?
      x, y = queue.shift
      described_class::DIRS.each_value do |dx, dy, bit, _|
        nx = x + dx
        ny = y + dy
        next unless cells[(y * 15) + x].anybits?(bit)

        index = (ny * 15) + nx
        next if seen.include?(index)

        seen << index
        queue << [nx, ny]
      end
    end
    expect(seen.size).to eq 225
  end

  it 'moves everyone together once all have chosen, and the first at the cup wins' do
    start!
    current = session
    # 하네스: 컵 바로 옆에 해리를 두고 열린 쪽으로 한 칸
    cup = current.state['cup']
    cells = current.state['cells']
    dir, (dx, dy) = described_class::DIRS.find { |_, (ddx, ddy, bit, _)| cells[((cup[1] - ddy) * 15) + cup[0] - ddx].to_i.anybits?(bit) && (cup[0] - ddx).between?(0, 14) && (cup[1] - ddy).between?(0, 14) }
    current.state['positions']['0'] = [cup[0] - dx, cup[1] - dy]
    current.state['traps'] = []
    current.state['creatures'] = []
    current.state['items'] = []
    current.save!

    harry_player, cedric_player, fleur_player = current.players.to_a
    current.with_lock { described_class.new(current).submit_move!(harry_player, [dir], 'cooperate') }
    expect(current.reload.turn).to eq 1 # 아직 다른 사람이 고르지 않음

    current.with_lock { described_class.new(current).submit_move!(cedric_player, [], 'cooperate') }
    current.with_lock { described_class.new(current).submit_move!(fleur_player, [], 'hinder') }

    expect(current.reload.status).to eq 'finished'
    expect(harry_player.reload.result).to eq 'win'
  end

  it 'resolves a meeting by stance' do
    start!
    current = session
    current.state.merge!('traps' => [], 'creatures' => [], 'items' => [], 'cells' => Array.new(225, 15))
    current.state['positions'] = { '0' => [3, 3], '1' => [5, 3], '2' => [14, 14] }
    current.save!
    harry_player, cedric_player, fleur_player = current.players.to_a

    current.with_lock { described_class.new(current).submit_move!(harry_player, %w(E), 'hinder') }
    current.with_lock { described_class.new(current).submit_move!(cedric_player, %w(W), 'cooperate') }
    current.with_lock { described_class.new(current).submit_move!(fleur_player, [], 'cooperate') }

    state = current.reload.state
    expect(state['positions']['0']).to eq [4, 3]
    expect(state.dig('status', '1', 'stunned')).to eq 1
    expect(state.dig('status', '0', 'hostile')).to be true
  end
end
