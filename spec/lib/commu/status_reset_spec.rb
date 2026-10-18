# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Commu::StatusReset do
  let!(:system) { Fabricate(:account, username: 'system') }
  let(:harry) { Fabricate(:user, account: Fabricate(:account, username: 'harry')).account }
  let(:ron) { Fabricate(:user, account: Fabricate(:account, username: 'ron')).account }

  it 'deletes every status including DMs but keeps accounts, characters and game records' do
    house = GameHouse.create!(name: '그리핀도르', emoji: '🦁')
    GameCharacter.for(harry).update!(house: house, money: 7)
    PostStatusService.new.call(harry, text: '공개글', visibility: 'unlisted')
    dm = PostStatusService.new.call(harry, text: "@#{ron.username} 비밀", visibility: 'direct')
    session = GameSession.create!(kind: 'maze', status: 'finished', visibility: 'private', root_status_id: dm.id, last_status_id: dm.id)
    open_session = GameSession.create!(kind: 'flying', status: 'pending', visibility: 'private', root_status_id: dm.id)
    session.players.create!(account: harry, seat: 0, result: 'win', state: { 'dm_status_id' => dm.id.to_s })

    described_class.call

    expect(Status.unscoped.count).to eq 0
    expect(Mention.count).to eq 0
    expect(Notification.where(activity_type: 'Mention').count).to eq 0
    expect([Account.exists?(harry.id), Account.exists?(ron.id)]).to eq [true, true]
    expect(GameCharacter.for(harry).reload).to have_attributes(money: 7, group_id: house.id)
    expect(session.reload).to have_attributes(status: 'finished', root_status_id: nil)
    expect(session.players.first).to have_attributes(result: 'win')
    expect(session.players.first.state).to eq({})
    expect(open_session.reload.status).to eq 'cancelled'
    expect(harry.account_stat.reload.statuses_count).to eq 0
  end
end
