# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Game::Lessons do
  let!(:system) { Fabricate(:account, username: 'system') }
  let(:gryffindor) { GameHouse.create!(name: '그리핀도르', emoji: '🦁') }
  let(:harry) { Fabricate(:account, username: 'harry') }
  let(:ron) { Fabricate(:account, username: 'ron') }
  let(:hermione) { Fabricate(:account, username: 'hermione') }
  let(:neville) { Fabricate(:account, username: 'neville') }
  let(:app) { Fabricate(:application) }

  before do
    { harry => '해리', ron => '론', hermione => '헤르미온느', neville => '네빌' }.each do |account, name|
      GameCharacter.for(account).update!(name: name, house: gryffindor)
    end
  end

  def toot(account, text, thread: nil, visibility: 'private')
    before = Status.where(account: system).pluck(:id)
    status = PostStatusService.new.call(account, text: text, thread: thread, visibility: visibility)
    Game::Engine.new(status).call
    @replies = Status.where(account: system).where.not(id: before).to_a
    status
  end

  # 운영진이 시스템 계정으로 직접 [수업/과목] 툿을 쓴다 (앱에서 쓴 툿)
  def open_class(subject)
    before = Status.where(account: system).pluck(:id)
    status = PostStatusService.new.call(system, text: "[수업/#{subject}]", visibility: 'private', application: app)
    Game::Engine.new(status).call if Game::System.class_toot?(status)
    @replies = Status.where(account: system).where.not(id: before + [status.id]).to_a
    status
  end

  def session
    GameSession.last
  end

  def run_timeout
    token = session.deadline_token
    travel_to(session.reload.deadline_at + 1.second) { Game::TimeoutWorker.new.perform(session.id, token) }
  end

  def last_text
    Status.find(session.reload.last_status_id).text
  end

  describe 'levitation (일반 마법)' do
    it 'gives T when casting before the signal' do
      toot(harry, '@system [자습/일반 마법]')
      expect(session).to have_attributes(kind: 'levitation', status: 'active')
      expect(@replies.last.text).to include('깃털을 바라보며')

      toot(harry, '@system [레비오사]')
      expect(session.status).to eq 'finished'
      expect(GameGrade.last).to have_attributes(account: harry, subject: 'levitation', grade: 'T', mode: 'study')
      expect(@replies.last.text).to include('레비-오사', '해리 — T')
    end

    it 'grades by reaction time after the signal and pays the same points for study' do
      toot(harry, '@system [자습/일반 마법]')
      run_timeout
      expect(last_text).to include('지금!')

      signal = Time.iso8601(session.state['signal_at'])
      travel_to(signal + 2.seconds) { toot(harry, '@system [레비오사]') }
      expect(GameGrade.last.grade).to eq 'O'
      expect(gryffindor.total).to eq 15 # 자습도 등급 점수 그대로
    end

    it 'limits study to once a day per subject' do
      toot(harry, '@system [자습/일반 마법]')
      toot(harry, '@system [레비오사]')
      toot(harry, '@system [자습/일반 마법]')
      expect(@replies.last.text).to include('하루 1번까지')
    end
  end

  describe 'transfiguration class (변신술 수업)' do
    before { Game::Config.update!('transfiguration', 'high_perfect' => '100') }

    it 'gathers a class, then each student tries and gets ranked with a bonus' do
      open_class('변신술')
      expect(session.status).to eq 'pending'
      expect(@replies.last.text).to include('변신술 수업이 열립니다', '[참가]')

      toot(harry, '@system [참가]')
      toot(ron, '@system [참가]')
      expect(session.players.map(&:account)).to eq [harry, ron]

      run_timeout
      expect(session.status).to eq 'active'
      expect(last_text).to include('과제:')

      toot(harry, '@system [강]')
      expect(@replies.last.mentions.map(&:account)).to eq [harry]
      toot(ron, '@system [약]')
      toot(ron, '@system [약]')
      toot(ron, '@system [약]')

      expect(session.status).to eq 'finished'
      expect(last_text).to include('1. 해리 — O')
      expect(GameGrade.where(mode: 'class').count).to eq 2
      expect(GameHousePoint.where(account: harry).sum(:amount)).to eq 20 # 15 + 상위 보너스 5
    end

    it 'opens a class only from a toot the staff wrote as the system account' do
      toot(harry, '@system [수업/변신술]')
      expect(GameSession.count).to eq 0
      expect(@replies.last.text).to include('시스템 계정으로')

      # 시스템이 자동으로 올린 툿(앱 없음)은 수업을 열지 않는다
      automatic = PostStatusService.new.call(system, text: '[수업/변신술]', visibility: 'private')
      expect(Game::System.class_toot?(automatic)).to be false

      open_class('변신술')
      expect(session).to have_attributes(kind: 'transfiguration', status: 'pending')
    end
  end

  describe 'flying (비행)' do
    it 'is class only and needs enough students' do
      toot(harry, '@system [자습/비행]')
      expect(@replies.last.text).to include('수업으로만')

      open_class('비행')
      toot(harry, '@system [참가]')
      run_timeout
      expect(session.status).to eq 'cancelled'
      expect(last_text).to include('최소 4명')
    end

    it 'succeeds alone on a route and crashes when routes overlap' do
      Game::Config.update!('flying', 'rounds' => '1')
      open_class('비행')
      [harry, ron, hermione, neville].each { |account| toot(account, '@system [참가]') }
      run_timeout
      expect(session.state['routes'].size).to eq 3

      toot(harry, '@system [비행/1]', visibility: 'direct')
      toot(ron, '@system [비행/2]', visibility: 'direct')
      toot(hermione, '@system [비행/3]', visibility: 'direct')
      toot(neville, '@system [비행/3]', visibility: 'direct')

      expect(session.status).to eq 'finished'
      grades = GameGrade.where(subject: 'flying').to_h { |grade| [grade.account_id, grade.grade] }
      expect(grades).to eq(harry.id => 'O', ron.id => 'O', hermione.id => 'P', neville.id => 'P')
      expect(last_text).to include('충돌')
    end
  end

  describe 'practice (어둠의 마법 방어술)' do
    it 'levels up the spell' do
      Game::Config.update!('practice', 'gain_min' => '100', 'gain_max' => '100')
      toot(harry, '@system [자습/어둠의 마법 방어술]')
      toot(harry, '@system [연습] 행복한 기억을 떠올린다')

      character = GameCharacter.for(harry).reload
      expect(character.progress['spells']).to eq('익스펙토 패트로눔' => 1)
      expect(character.progress['patronus']).to be_blank
      expect(@replies.last.text).to include('해리 — O')

      toot(harry, '@system [성적표]')
      expect(@replies.last.text).to include('해리의 성적표', '어둠의 마법 방어술: O', '익스펙토 패트로눔 Lv.1')
    end
  end

  it 'refuses locked subjects' do
    Game::Config.update!('levitation', 'enabled' => '0')
    toot(harry, '@system [자습/일반 마법]')
    expect(GameSession.count).to eq 0
    expect(@replies.last.text).to include('아직 열리지 않은 과목')
  end
end
