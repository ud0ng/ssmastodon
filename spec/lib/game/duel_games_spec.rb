# frozen_string_literal: true

require 'rails_helper'

# 1:1 수 싸움: 빗자루 경주(체력 나누기) · 구슬 홀짝(블러핑 + 베팅)
RSpec.describe 'Duel games: broom race and marbles' do
  let!(:system) { Fabricate(:account, username: 'system') }
  let(:alice) { Fabricate(:account, username: 'alice') }
  let(:bob) { Fabricate(:account, username: 'bob') }

  before do
    allow(Game::System).to receive(:account).and_return(system)
    GameCharacter.for(alice).update!(name: '해리', house: GameHouse.create!(name: '그리핀도르', emoji: '🦁'))
    GameCharacter.for(bob).update!(name: '드레이코', house: GameHouse.create!(name: '슬리데린', emoji: '🐍'))
  end

  def toot(account, text, thread: nil, visibility: 'private')
    before = Status.where(account: system).pluck(:id)
    status = PostStatusService.new.call(account, text: text, thread: thread, visibility: visibility)
    Game::Engine.new(status).call
    @replies = Status.where(account: system).where.not(id: before).to_a
    status
  end

  def dm(account, text)
    toot(account, "@system #{text}", visibility: 'direct')
  end

  def session
    GameSession.last.reload
  end

  def start(command)
    toot(alice, "@system @bob [#{command}]")
    toot(bob, '@system [수락]', thread: @replies.last)
  end

  def seat_of(account)
    session.player_for(account).seat.to_s
  end

  describe Game::Kinds::BroomRace do
    it 'spends secret stamina each lap and wins after three laps, with the common finish' do
      Game::Config.update!('broom_race', 'points_win' => '5')
      start('경주')
      expect(session.status).to eq 'active'

      dm(alice, '[투입/5]')
      expect(session.state['choices']).to eq(seat_of(alice) => 5) # 상대가 낼 때까지 공개하지 않는다
      dm(bob, '[투입/3]')
      expect(session.state['wins'][seat_of(alice)]).to eq 1
      expect(session.state['stamina']).to eq(seat_of(alice) => 10, seat_of(bob) => 12)

      dm(alice, '[투입/2]')
      dm(bob, '[투입/2]') # 같으면 아무도 못 이김
      expect(session.state['wins'][seat_of(alice)]).to eq 1

      dm(alice, '[투입/4]')
      dm(bob, '[투입/0]')
      dm(alice, '[투입/4]')
      dm(bob, '[투입/1]')

      expect(session.status).to eq 'finished'
      expect(session.player_for(alice).result).to eq 'win'
      expect(GameHousePoint.where(game_session_id: session.id).sum(:amount)).to eq 5
    end

    it 'refuses more stamina than is left, and counts a timeout as zero' do
      start('경주')
      dm(alice, '[투입/99]')
      expect(session.state['choices']).to eq({})
      dm(alice, '[투입/1]')
      current = session
      current.with_lock { Game::Kinds::BroomRace.new(current).timeout! }
      expect(session.state['laps'].last['amounts']).to eq(seat_of(alice) => 1, seat_of(bob) => 0)
      expect(session.state['wins'][seat_of(alice)]).to eq 1
    end

    it 'ends in a draw when the laps run out with the same number of wins' do
      Game::Config.update!('broom_race', 'laps' => '2', 'wins_needed' => '2')
      start('경주')
      dm(alice, '[투입/3]')
      dm(bob, '[투입/1]')
      dm(alice, '[투입/1]')
      dm(bob, '[투입/3]')
      expect(session.status).to eq 'finished'
      expect(session.players.map(&:result).uniq).to eq ['draw']
    end
  end

  describe Game::Kinds::Marbles do
    def hider
      session.players.find { |player| player.seat == session.state['hider'] }.account
    end

    def guesser
      session.players.find { |player| player.seat != session.state['hider'] }.account
    end

    it 'hides in secret, bets in public, moves the marbles and swaps the roles' do
      start('홀짝')
      first_hider = hider
      first_guesser = guesser

      dm(first_hider, '[쥐기/3]')
      expect(session.state['phase']).to eq 'guess'
      toot(first_guesser, '@system [홀/4]')

      expect(session.state['marbles']).to eq(seat_of(first_guesser) => 14, seat_of(first_hider) => 6)
      expect(hider).to eq first_guesser # 역할이 바뀐다
      expect(session.turn).to eq 2

      dm(hider, '[쥐기/2]')
      toot(guesser, '@system [홀/6]') # 틀리면 건 만큼 내준다
      expect(session.status).to eq 'finished'
      expect(session.player_for(first_guesser).result).to eq 'win'
    end

    it 'keeps the bet within both players marbles and only lets the right person act' do
      start('홀짝')
      toot(guesser, '@system [짝/2]')
      expect(session.state['phase']).to eq 'hide' # 아직 숨기기 차례
      dm(hider, '[쥐기/11]')
      expect(session.state['phase']).to eq 'hide'
      dm(hider, '[쥐기/1]')
      toot(guesser, '@system [짝/11]')
      expect(session.state['phase']).to eq 'guess'
    end

    it 'treats a missed guess as a lost bet of one' do
      start('홀짝')
      first_guesser = guesser
      dm(hider, '[쥐기/2]')
      current = session
      current.with_lock { Game::Kinds::Marbles.new(current).timeout! }
      expect(session.state['marbles'][seat_of(first_guesser)]).to eq 9
    end
  end
end
