# frozen_string_literal: true

require 'rails_helper'

# 컨텐츠 하루 신청 횟수: 컨텐츠를 모두 합한 횟수, 같은 상대와의 횟수 (내가 보낸 신청만, 이벤트 제외)
RSpec.describe Game::DailyLimits do
  let!(:system) { Fabricate(:account, username: 'system') }
  let!(:harry) { Fabricate(:account, username: 'harry') }
  let!(:ron) { Fabricate(:account, username: 'ron') }
  let!(:hermione) { Fabricate(:account, username: 'hermione') }

  def toot(account, text)
    status = PostStatusService.new.call(account, text: text, visibility: 'private')
    Game::Engine.new(status).call
    status
  end

  def sent_sessions
    GameSession.joins(:players).where(game_players: { account_id: harry.id, seat: 0 })
  end

  it 'allows everything while both limits are 0 (default)' do
    Game::Config.merge!('common', 'one_game_per_person' => false)
    3.times { toot(harry, '@system @ron [젤리빈]') }

    expect(sent_sessions.count).to eq 3
  end

  it 'refuses the invite over the daily limit with a reply mention, summing every content' do
    Game::Config.merge!('common', 'daily_game_limit' => 2, 'one_game_per_person' => false)
    toot(harry, '@system @ron [젤리빈]')
    toot(harry, '@system @hermione [곱스톤]')
    toot(harry, '@system @ron [곱스톤]')

    expect(sent_sessions.count).to eq 2
    expect(Status.where(account: system).reorder(:id).last.text).to include('오늘은 더 이상 컨텐츠를 신청할 수 없습니다', '하루 최대 2회')
  end

  it 'limits invites to the same opponent per day but not to others' do
    Game::Config.merge!('common', 'daily_opponent_limit' => 1, 'one_game_per_person' => false)
    toot(harry, '@system @ron [젤리빈]')
    toot(harry, '@system @ron [곱스톤]')
    expect(sent_sessions.count).to eq 1
    expect(Status.where(account: system).reorder(:id).last.text).to include('ron', '같은 상대와 하루 최대 1회')

    toot(harry, '@system @hermione [곱스톤]')
    expect(sent_sessions.count).to eq 2
  end

  it 'counts only invites I sent, not events or tournament matches or invites sent to me' do
    Game::Config.merge!('common', 'daily_game_limit' => 1)
    GameSession.create!(kind: 'maze', status: 'active', visibility: 'private', state: { 'mode' => 'event' }).players.create!(account: harry, seat: 0)
    GameSession.create!(kind: 'jellybean', status: 'active', visibility: 'private', state: { 'tournament_match_id' => 1 }).players.create!(account: harry, seat: 0)
    GameSession.create!(kind: 'jellybean', status: 'active', visibility: 'private').players.create!(account: harry, seat: 1)

    expect(described_class.check(harry, [ron])).to be_nil
  end
end
