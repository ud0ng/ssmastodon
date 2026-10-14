# frozen_string_literal: true

require 'rails_helper'

# 퀴디치 팀전 (신청자 + 앞쪽 절반 vs 나머지)
RSpec.describe Game::Kinds::Quidditch do
  let!(:system) { Fabricate(:account, username: 'system') }
  let!(:harry) { Fabricate(:account, username: 'harry') }
  let!(:ron) { Fabricate(:account, username: 'ron') }
  let!(:draco) { Fabricate(:account, username: 'draco') }
  let!(:goyle) { Fabricate(:account, username: 'goyle') }

  def toot(account, text, visibility: 'private')
    status = PostStatusService.new.call(account, text: text, visibility: visibility)
    Game::Engine.new(status).call
    status
  end

  def session
    GameSession.where(kind: 'quidditch').order(:id).last
  end

  def start!
    toot(harry, '@system @ron @draco @goyle [퀴디치]')
    [ron, draco, goyle].each { |account| toot(account, '@system [수락]') }
  end

  it 'refuses an odd number of players' do
    toot(harry, '@system @ron @draco [퀴디치]')

    expect(GameSession.where(kind: 'quidditch')).to be_empty
    expect(Status.where(account: system).last.text).to include('2·4·6명')
  end

  it 'splits two teams and announces them' do
    start!

    expect(session.status).to eq 'active'
    expect(session.state['teams']).to eq('0' => 'A', '1' => 'A', '2' => 'B', '3' => 'B')
    expect(Status.where(account: system).map(&:text).join).to include('신청 팀(harry·ron) vs 상대 팀(draco·goyle)')
    expect(described_class.new(session).card_data['team_names']).to eq('A' => '신청 팀', 'B' => '상대 팀')
  end

  it 'adds goals to the team and makes the whole team win' do
    Game::Config.update!('quidditch', 'chase_rate' => '100', 'seek_start' => '0', 'max_turns' => '1')
    start!

    toot(harry, '@system [추격]', visibility: 'direct')
    toot(ron, '@system [추격]', visibility: 'direct')
    toot(draco, '@system [추격]', visibility: 'direct')
    toot(goyle, '@system [수색]', visibility: 'direct')

    current = session.reload
    expect(current.status).to eq 'finished'
    expect(current.state['scores']['A']).to eq 20
    expect(current.players.map { |player| [player.account.username, player.result] }).to eq [%w(harry win), %w(ron win), %w(draco lose), %w(goyle lose)]
    expect(GameReward.where(game_session_id: current.id, account: [harry, ron]).sum(:money)).to eq 20
  end
end
