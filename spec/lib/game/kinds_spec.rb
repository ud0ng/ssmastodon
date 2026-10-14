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

  describe Game::Kinds::Potion do
    before do
      Game::Config.update!('potion', 'answer_min' => '3', 'answer_max' => '3')
      start('물약')
    end

    def answer_numbers
      session.state['answer'].map { |name| session.state['shown'].index(name) + 1 }
    end

    it 'shows ingredients in public and by DM' do
      expect(session.state['shown'].size).to eq 9
      expect(session.state['answer'].size).to eq 3
      expect(@replies.find { |status| status.visibility == 'private' }.text).to include('재료:', '[조합]')
      expect(replies_to(alice, 'direct')).to be_present
    end

    it 'gives strike/ball hints by DM and ends the turn in public when both tried' do
      wrong = (1..9).to_a - answer_numbers
      toot(alice, "@system [조합] #{answer_numbers.reverse.join(' ')}", visibility: 'direct')
      hint = @replies.last.text
      expect(hint).to include('1번째 시도', '순서가 틀린 재료')

      toot(bob, "@system [조합] #{wrong.first(3).join(' ')}", visibility: 'direct')
      result = @replies.find { |status| status.visibility == 'private' }
      expect(result.text).to include('1턴', '드레이코: 정답 0 · 순서 틀림 0')
      expect(session.turn).to eq 2
    end

    it 'lets the first to brew the right order win' do
      toot(alice, "@system [조합] #{answer_numbers.join(' ')}", visibility: 'direct')
      toot(bob, '@system [조합] 1 2 3', visibility: 'direct') unless answer_numbers == [1, 2, 3]
      expect(session.status).to eq 'finished'
      expect(session.player_for(alice).result).to eq 'win'
    end

    it 'rejects a guess with the wrong number of ingredients' do
      toot(alice, '@system [조합] 1 2', visibility: 'direct')
      expect(@replies.last.text).to include('겹치지 않게')
      expect(session.state['tries']).to be_empty
    end
  end

  describe Game::Kinds::Quidditch do
    before { start('퀴디치') }

    it 'scores a guaranteed snitch catch and ends the match' do
      Game::Config.update!('quidditch', 'seek_start' => '100', 'chase_rate' => '100')
      session.update!(state: session.state.merge('seek' => { '0' => 100, '1' => 0 }))
      toot(alice, '@system [수색]', visibility: 'direct')
      toot(bob, '@system [추격]', visibility: 'direct')

      expect(session.status).to eq 'finished'
      expect(session.player_for(alice).result).to eq 'win'
      expect(Status.find(session.last_status_id).text).to include('골든 스니치', '+150')
    end

    it 'lets a beater cancel the other action' do
      Game::Config.update!('quidditch', 'beat_rate' => '100', 'chase_rate' => '100')
      toot(alice, '@system [몰이]', visibility: 'direct')
      toot(bob, '@system [추격]', visibility: 'direct')

      expect(session.state['scores']).to eq('A' => 0, 'B' => 0)
      expect(Status.find(session.last_status_id).text).to include('블러저가 드레이코를 덮쳤다')
    end
  end
end
