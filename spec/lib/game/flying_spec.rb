# frozen_string_literal: true

require 'rails_helper'

# 비행 대결 (여럿이): 겹치지 않는 경로를 고르면 통과, 통과 횟수가 가장 많은 사람 승리
RSpec.describe Game::Kinds::Flying do
  let!(:system) { Fabricate(:account, username: 'system') }
  let!(:harry) { Fabricate(:account, username: 'harry') }
  let!(:ron) { Fabricate(:account, username: 'ron') }
  let!(:draco) { Fabricate(:account, username: 'draco') }

  def toot(account, text, visibility: 'private')
    status = PostStatusService.new.call(account, text: text, visibility: visibility)
    Game::Engine.new(status).call
    status
  end

  def session
    GameSession.where(kind: 'flying').order(:id).last
  end

  def start!
    toot(harry, '@system @ron @draco [비행대결]')
    [ron, draco].each { |account| toot(account, '@system [수락]') }
  end

  before { Game::Config.update!('flying', 'rounds' => '1') }

  it 'is a group content with fewer routes than players' do
    expect(Game::Guide.group_of(described_class)).to eq 'group'

    start!

    expect(session.status).to eq 'active'
    expect(session.state['routes'].size).to eq 2
    expect(described_class.new(session).card_actions.size).to eq 2
  end

  it 'lets the only one on a free route win' do
    start!

    toot(harry, '@system [비행/1]', visibility: 'direct')
    toot(ron, '@system [비행/1]', visibility: 'direct')
    toot(draco, '@system [비행/2]', visibility: 'direct')

    current = session.reload
    expect(current.status).to eq 'finished'
    expect(current.players.map { |player| [player.account.username, player.result] }).to eq [%w(harry lose), %w(ron lose), %w(draco win)]
    expect(Status.where(account: system).map(&:text).join).to include('충돌', '통과')
  end

  it 'is a draw when everyone crashes' do
    start!

    [harry, ron, draco].each { |account| toot(account, '@system [비행/1]', visibility: 'direct') }

    expect(session.reload.players.map(&:result)).to eq %w(draw draw draw)
  end
end
