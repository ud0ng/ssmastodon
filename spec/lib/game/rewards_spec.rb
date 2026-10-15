# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Game::Rewards do
  let!(:system) { Fabricate(:account, username: 'system') }
  let(:alice) { Fabricate(:account, username: 'alice') }
  let(:bob) { Fabricate(:account, username: 'bob') }

  def session_with_players
    GameSession.create!(kind: 'jellybean', status: 'active').tap do |session|
      session.players.create!(account: alice, seat: 0)
      session.players.create!(account: bob, seat: 1)
    end
  end

  it 'rolls each item line by its chance' do
    lines = ['초콜릿 개구리|2|100', '용의 알|1|0', '버티 보츠|', '|3']
    expect(described_class.roll(lines)).to eq [
      { 'name' => '초콜릿 개구리', 'count' => 2 },
      { 'name' => '버티 보츠', 'count' => 1 },
    ]
  end

  it 'adds money and stacks items in the inventory' do
    GameCharacter.for(alice).update!(money: 5, inventory: [{ 'name' => '초콜릿 개구리', 'count' => 1, 'note' => '선물' }])
    session = session_with_players

    text = described_class.give(session, session.players.first, money: 10, items: [{ 'name' => '초콜릿 개구리', 'count' => 2 }, { 'name' => '깃펜', 'count' => 1 }])

    character = GameCharacter.for(alice)
    expect(character.money).to eq 15
    expect(character.inventory).to eq [
      { 'name' => '초콜릿 개구리', 'count' => 3, 'note' => '선물' },
      { 'name' => '깃펜', 'count' => 1, 'note' => '' },
    ]
    expect(text).to include('10 갈레온', '초콜릿 개구리 ×2', '깃펜')
    expect(GameReward.where(account: alice).sum(:money)).to eq 10
  end

  it 'pays winner, loser and draws as configured when a game ends' do
    Game::Config.update!('jellybean', 'reward_money_win' => 30, 'reward_money_lose' => 4, 'reward_items_win' => '우승 리본|1|')
    session = session_with_players
    winner = session.players.first

    Game::Kinds.fetch('jellybean').new(session).send(:finish!, winner: winner, message: '끝!')

    expect(GameCharacter.for(alice)).to have_attributes(money: 30, inventory: [{ 'name' => '우승 리본', 'count' => 1, 'note' => '' }])
    expect(GameCharacter.for(bob).money).to eq 4
    result = Status.where(account: system).order(:id).last
    expect(result.text).to include('30 갈레온', '우승 리본', '4 갈레온')
    expect(GameEvent.find_by(status: result).payload['rewards'].pluck('money')).to eq [30, 4]
  end

  it 'gives lesson points and rewards by grade, the same for self-study, with a bonus for the top of a class' do
    Game::Config.update!('lessons', 'points_O' => 20, 'reward_money_O' => 10, 'reward_items_O' => '깃펜|2|', 'reward_money_P' => 1,
                                    'class_bonus_percent' => 50, 'class_bonus_count' => 1, 'bonus_money' => 7, 'reward_items_bonus' => '우승 리본|1|')

    expect(Game::Lessons.points_for('O', 'study', nil)).to eq 20
    expect(Game::Lessons.points_for('O', 'class', 1)).to eq 30
    expect(Game::Lessons.points_for('O', 'class', 2)).to eq 20
    expect(Game::Lessons.rewards_for('O', 'study', nil)).to eq(money: 10, items: [{ 'name' => '깃펜', 'count' => 2 }])
    expect(Game::Lessons.rewards_for('O', 'class', 1)).to eq(money: 17, items: [{ 'name' => '깃펜', 'count' => 2 }, { 'name' => '우승 리본', 'count' => 1 }])
    expect(Game::Lessons.rewards_for('P', 'class', 1)).to eq(money: 1, items: [])
  end
end
