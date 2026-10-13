# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Game kinds' do
  let!(:system) { Fabricate(:account, username: 'system') }
  let(:alice) { Fabricate(:account, username: 'alice') }
  let(:bob) { Fabricate(:account, username: 'bob') }

  before do
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

  def replies_to(account, visibility)
    @replies.select { |status| status.visibility == visibility && status.mentions.any? { |mention| mention.account_id == account.id } }
  end

  def session
    GameSession.last
  end

  def start(command)
    toot(alice, "@system @bob [#{command}]")
    toot(bob, '@system [수락]', thread: @replies.last)
  end

  describe Game::Kinds::Gobstones do
    def current
      session.players.find { |player| player.seat == session.state['seat'] }.account
    end

    it 'alternates throws for the set rounds and scores them' do
      Game::Config.update!('gobstones', 'rounds' => '2', 'hit_strong' => '0', 'hit_weak' => '100')
      start('곱스톤')
      expect(session.status).to eq 'active'

      first = current
      toot(first, '@system [약]')
      expect(@replies.last.text).to include('명중! +1점', '1라운드')
      toot(current, '@system [강]')
      expect(@replies.last.text).to include('냄새나는 액체', '-1점')
      toot(current, '@system [약]')
      toot(current, '@system [약]')

      expect(session.status).to eq 'finished'
      expect(session.player_for(first).result).to eq 'win'
      expect(session.state['scores'].values).to contain_exactly(2, 0)
    end

    it 'counts a timed-out throw as zero and keeps playing' do
      start('곱스톤')
      waiting = current
      token = session.deadline_token
      travel_to(6.minutes.from_now) { Game::TimeoutWorker.new.perform(session.id, token) }

      expect(session.status).to eq 'active'
      expect(current).to_not eq waiting
      expect(Status.find(session.last_status_id).text).to include('던지지 못했다')
    end
  end

  describe Game::Kinds::Duel do
    before { start('결투') }

    it 'asks each player by DM and reveals both spells together' do
      expect(session.status).to eq 'active'
      expect(replies_to(alice, 'direct').last.text).to include('1턴', '[공격]', '스투페파이')
      expect(replies_to(bob, 'direct').last.text).to include('1턴')

      toot(alice, '@system [방어]', visibility: 'direct')
      expect(@replies.map(&:visibility)).to eq ['direct']
      toot(bob, '@system [공격]', visibility: 'direct')

      result = @replies.find { |status| status.visibility == 'private' }
      expect(result.text).to include('1턴', '해리 [방어] vs 드레이코 [공격]', '해리의 주문이 통했습니다', '드레이코 ❤️❤️🖤')
      expect(session.state['hp']).to eq('0' => 3, '1' => 2)
    end

    it 'does not take spells sent in public' do
      toot(alice, '@system [공격]')
      expect(session.state['choices']).to be_empty
      expect(@replies.last.text).to include('DM으로')
    end

    it 'doubles damage with the special move and backfires when it loses' do
      toot(alice, '@system [공격/필살]', visibility: 'direct')
      toot(bob, '@system [무장해제]', visibility: 'direct')
      expect(session.state['hp']).to eq('0' => 3, '1' => 1)

      toot(alice, '@system [공격/필살]', visibility: 'direct') # 이미 씀 → 보통 공격
      toot(bob, '@system [방어/필살]', visibility: 'direct')
      expect(session.state['hp']).to eq('0' => 1, '1' => 1)
    end

    it 'treats a missing spell as a failure on timeout and ends when HP runs out' do
      3.times do
        toot(alice, '@system [공격]', visibility: 'direct')
        token = session.deadline_token
        travel_to(session.reload.deadline_at + 1.second) { Game::TimeoutWorker.new.perform(session.id, token) }
      end

      expect(session.status).to eq 'finished'
      expect(session.player_for(alice).result).to eq 'win'
      expect(Status.find(session.last_status_id).text).to include('주문 실패', '쓰러졌습니다')
    end
  end
end
