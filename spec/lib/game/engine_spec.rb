# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Game::Engine do
  let!(:system) { Fabricate(:account, username: 'system') }
  let(:alice) { Fabricate(:account, username: 'alice') }
  let(:bob) { Fabricate(:account, username: 'bob') }
  let(:gryffindor) { GameHouse.create!(name: '그리핀도르', emoji: '🦁') }
  let(:slytherin) { GameHouse.create!(name: '슬리데린', emoji: '🐍') }

  before do
    GameCharacter.for(alice).update!(name: '해리', house: gryffindor)
    GameCharacter.for(bob).update!(name: '드레이코', house: slytherin)
  end

  # 사람이 툿을 쓰면 PostStatusService 가 Game::MentionWorker 를 넣는다. 여기서는 바로 처리한다.
  # 같은 밀리초에 만든 툿은 id 순서가 보장되지 않아서, 이번 명령어로 생긴 시스템 툿을 따로 기억한다.
  def toot(account, text, thread: nil, visibility: 'private')
    before = Status.where(account: system).pluck(:id)
    status = PostStatusService.new.call(account, text: text, thread: thread, visibility: visibility)
    described_class.new(status).call
    @replies = Status.where(account: system).where.not(id: before).to_a
    status
  end

  # 마지막 명령어에 시스템 계정이 답한 툿
  def last_reply
    @replies.last
  end

  def session
    GameSession.last
  end

  it 'parses the first bracket command and its arguments' do
    expect(described_class.parse('@system 한 입 [먹기 / 2] [다른 것]')).to eq ['먹기', ['2']]
    expect(described_class.parse('대괄호 없음')).to be_nil
  end

  describe 'invite' do
    it 'asks for exactly one opponent' do
      carol = Fabricate(:account, username: 'carol')
      toot(alice, '@system @bob @carol [젤리빈]')
      expect(GameSession.count).to eq 0
      expect(last_reply.text).to include('1:1')

      toot(alice, '@system [젤리빈]')
      expect(last_reply.text).to include('태그')
      expect(carol).to be_present
    end

    it 'creates a pending game, mentions both, and answers with the same visibility' do
      toot(alice, '@system @bob [젤리빈]', visibility: 'direct')

      expect(session).to have_attributes(kind: 'jellybean', status: 'pending', visibility: 'direct')
      expect(session.players.map(&:account)).to eq [alice, bob]
      expect(last_reply).to have_attributes(visibility: 'direct')
      expect(last_reply.text).to include('@alice', '@bob', '드레이코', '해리가', '[수락]')
      expect(Game::TimeoutWorker.jobs.size).to eq 1
    end

    it 'refuses when someone already has an open game' do
      toot(alice, '@system @bob [젤리빈]')
      carol = Fabricate(:account, username: 'carol')
      toot(carol, '@system @bob [젤리빈]')

      expect(GameSession.count).to eq 1
      expect(last_reply.text).to include('이미 진행 중')
    end

    it 'cancels a declined invite' do
      toot(alice, '@system @bob [젤리빈]')
      toot(bob, '@system [거절]', thread: last_reply)

      expect(session.status).to eq 'cancelled'
    end

    it 'cancels an invite nobody answered' do
      toot(alice, '@system @bob [젤리빈]')
      token = session.deadline_token
      travel_to(11.minutes.from_now) { Game::TimeoutWorker.new.perform(session.id, token) }

      expect(session.status).to eq 'cancelled'
      expect(Status.find(session.last_status_id).text).to include('취소')
    end
  end

  describe 'jellybean' do
    before do
      toot(alice, '@system @bob [젤리빈]')
      @accept = toot(bob, '@system [수락]', thread: last_reply)
    end

    def current_account
      session.players.find { |player| player.seat == session.state['seat'] }.account
    end

    it 'starts after the opponent accepts' do
      expect(session.status).to eq 'active'
      expect(session.state['bag'].size).to eq 10
      expect(session.state['bag'].count { |bean| bean['worst'] }).to eq 1
      expect(last_reply.text).to include('젤리빈 룰렛 시작')
    end

    it 'keeps one thread by replying to the command each player sent' do
      expect(last_reply.in_reply_to_id).to eq @accept.id

      eat = toot(current_account, '@system [먹기]', thread: last_reply)
      expect(last_reply.in_reply_to_id).to eq eat.id
    end

    it 'ignores eating out of turn' do
      waiting = ([alice, bob] - [current_account]).first
      toot(waiting, '@system [먹기]')
      expect(session.state['bag'].size).to eq 10
      expect(last_reply.text).to include('차례입니다')
    end

    it 'plays until someone eats the worst bean and gives the winner house points' do
      30.times do
        break unless session.status == 'active'

        toot(current_account, '@system [먹기/2]', thread: last_reply)
      end

      expect(session.status).to eq 'finished'
      winner = session.players.find { |player| player.result == 'win' }
      loser = session.players.find { |player| player.result == 'lose' }
      expect(winner).to be_present
      expect(loser).to be_present
      expect(last_reply.text).to include('최악의 맛', "+5점")
      expect(GameHousePoint.sum(:amount)).to eq 5
      expect(GameHousePoint.last.house).to eq winner.character.house
    end

    it 'gives the game to the opponent on forfeit' do
      toot(alice, '@system [기권]')
      expect(session.status).to eq 'finished'
      expect(session.player_for(bob).result).to eq 'win'
    end

    it 'makes the current player lose on turn timeout' do
      loser = current_account
      token = session.deadline_token
      travel_to(6.minutes.from_now) { Game::TimeoutWorker.new.perform(session.id, token) }

      expect(session.status).to eq 'finished'
      expect(session.player_for(loser).result).to eq 'lose'
    end
  end

  describe 'settings' do
    it 'uses commands changed in the admin settings' do
      Game::Config.update!('jellybean', 'command' => '젤리')
      toot(alice, '@system @bob [젤리]')
      expect(session&.kind).to eq 'jellybean'
    end

    it 'tells people when a game is turned off' do
      Game::Config.update!('jellybean', 'enabled' => '0')
      toot(alice, '@system @bob [젤리빈]')
      expect(GameSession.count).to eq 0
      expect(last_reply.text).to include('열려 있지 않습니다')
    end
  end

  it 'answers the house board and personal record' do
    GameHousePoint.create!(house: slytherin, amount: 7)
    toot(alice, '@system [점수]')
    expect(last_reply.text).to match(/1\. 🐍 슬리데린 7점.*2\. 🦁 그리핀도르 0점/m)

    toot(alice, '@system [내전적]')
    expect(last_reply.text).to include('해리의 전적: 0승 0패 0무')
  end
end
