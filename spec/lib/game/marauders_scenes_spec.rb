# frozen_string_literal: true

require 'rails_helper'

# 도둑 지도 '오늘의 MVP' 장면: 판 기록에서 활약을 골라 점수순, 장면마다 다시 틀어 줄 턴
RSpec.describe Game::MaraudersScenes do
  let(:players) { %w(해리 론 말포이 스네이프).each_with_index.map { |name, seat| instance_double(GamePlayer, seat: seat, name: name) } }

  it 'picks the catcher, the goal runner, the rescuer and the student never caught, each with the turn to replay' do
    state = {
      'history' => [
        { 'turn' => 1, 'arrests' => [] },
        { 'turn' => 2, 'arrests' => [{ 'seat' => 1, 'by' => 3, 'room' => 4, 'out' => false }] },
        { 'turn' => 3, 'arrests' => [{ 'seat' => 1, 'by' => 3, 'room' => 6, 'out' => true }] },
      ],
      'goals_by' => { '0' => 2 }, 'goals_by_turn' => { '0' => 3 },
      'rescues_by' => { '0' => 1 }, 'rescues_by_turn' => { '0' => 2 },
      'finished_turn' => 3,
    }

    scenes = described_class.call(state, players, %w(0 1))

    expect(scenes.pluck('kind')).to eq %w(arrest_king goal_runner hero ghost caught_twice)
    expect(scenes.first).to include('round' => 3, 'seats' => [3], 'title' => '체포왕')
    expect(scenes.first['text']).to include('스네이프가', '2번')
    expect(scenes.find { |scene| scene['kind'] == 'hero' }).to include('round' => 2, 'seats' => [0])
    expect(scenes.find { |scene| scene['kind'] == 'ghost' }).to include('round' => 3, 'seats' => [0])
  end
end
