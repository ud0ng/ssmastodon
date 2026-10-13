# frozen_string_literal: true

require 'rails_helper'

# 도둑 지도 (웹 전용, 학생 1 vs 사감)
RSpec.describe Game::Web::MaraudersMap do
  let!(:system) { Fabricate(:account, username: 'system') }
  let!(:harry) { Fabricate(:account, username: 'harry') }
  let!(:filch) { Fabricate(:account, username: 'filch') }
  let!(:snape) { Fabricate(:account, username: 'snape') }

  def toot(account, text)
    status = PostStatusService.new.call(account, text: text, visibility: 'private')
    Game::Engine.new(status).call
    status
  end

  def session
    GameSession.where(kind: 'marauders_map').order(:id).last
  end

  def submit(player, room, stance = '')
    current = session
    current.with_lock { described_class.new(current).submit_move!(current.players.find { |p| p.id == player.id }, [room.to_s], stance) }
  end

  before do
    toot(harry, '@system @filch @snape [도둑지도]')
    toot(filch, '@system [수락]')
    toot(snape, '@system [수락]')
  end

  it 'starts with the challenger as the student and hides them from prefects' do
    expect(session).to have_attributes(status: 'active', turn: 1)
    student, prefect = session.players.to_a
    student_view = described_class.new(session).view_for(student)
    prefect_view = described_class.new(session).view_for(prefect)

    expect(student_view[:role]).to eq 'student'
    expect(student_view[:tokens].size).to eq 3
    expect(student_view[:secret]).to_not be_empty
    expect(prefect_view[:tokens].pluck(:student)).to all(be false)
    expect(prefect_view[:secret]).to be_empty
  end

  it 'catches the student when a prefect walks into the same room' do
    current = session
    current.state['positions'] = { '0' => 12, '1' => 13, '2' => 0 }
    current.save!
    student, filch_player, snape_player = current.players.to_a

    submit(student, 12)
    submit(filch_player, 12)
    submit(snape_player, 0)

    expect(session.status).to eq 'finished'
    expect(filch_player.reload.result).to eq 'win'
    expect(student.reload.result).to eq 'lose'
  end

  it 'lets the student win by visiting every target, leaving footprints for prefects' do
    current = session
    current.state.merge!('positions' => { '0' => 5, '1' => 24, '2' => 23 }, 'targets' => [9])
    current.save!
    student, filch_player, snape_player = current.players.to_a

    submit(filch_player, 24)
    submit(snape_player, 23)
    submit(student, 9) # 도서관 → 필요의 방 (비밀 통로)

    expect(session.status).to eq 'finished'
    expect(student.reload.result).to eq 'win'
    expect(session.state['clues'].pluck('kind')).to include('footprint', 'target')
  end

  it 'reveals the student with homenum revelio once per prefect' do
    current = session
    current.state['positions'] = { '0' => 0, '1' => 24, '2' => 23 }
    current.save!
    student, filch_player, snape_player = current.players.to_a

    submit(student, 0)
    submit(filch_player, 24, 'revelio')
    submit(snape_player, 23)

    expect(session.state['clues'].last).to include('kind' => 'revelio', 'room' => 0)
    expect(described_class.new(session).view_for(filch_player)[:revelio_available]).to be false
  end
end
