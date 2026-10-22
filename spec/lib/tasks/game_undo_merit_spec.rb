# frozen_string_literal: true

require 'rails_helper'
require 'rake'

# 1회성 정리 (lib/tasks/game_undo_merit.rake): 상점(칭찬) 수치로 얻은 소속 점수 초기화 + 기준 시각 이후 구입 환불·아이템 삭제
RSpec.describe 'game:undo_merit' do
  let(:house) { GameHouse.create!(name: '그리핀도르', color: '#ae0001', category: 'house') }
  let(:praise) { GameCounter.create!(name: '상점', max_count: 5) }
  let(:report) { GameCounter.create!(name: '벌점', max_count: 5) }
  let(:harry) { Fabricate(:account, username: 'harry') }
  let(:task) { Rake::Task['game:undo_merit'] }

  def character
    GameCharacter.for(harry).reload
  end

  def count_of(name)
    Array(character.inventory).find { |item| item['name'] == name }.to_h['count'].to_i
  end

  def run(apply:)
    ENV['APPLY'] = apply ? '1' : nil
    task.reenable
    expect { task.invoke }.to output.to_stdout
  ensure
    ENV.delete('APPLY')
  end

  before do
    Rake::Task.define_task(:environment)
    Rails.application.load_tasks unless Rake::Task.task_defined?('game:undo_merit')
    GameCharacter.for(harry).update!(house: house)
    shop = GameShop.create!(name: '특수')
    shop.items.create!(name: '칭찬권', price: 10, item_effects: [{ 'type' => 'counter', 'counter_id' => praise.id, 'value' => '1' }])
    shop.items.create!(name: '벌점권', price: 10, item_effects: [{ 'type' => 'counter', 'counter_id' => report.id, 'value' => '1' }])
    Game::Wallet.apply!([{ account: harry, money: 100 }], kind: 'admin')

    travel_to(Time.zone.parse('2026-10-19 12:00')) { Game::Wallet.apply!([{ account: harry, money: -10, items: { '칭찬권' => 1 } }], kind: 'purchase', detail: '칭찬권 1개', actor: 'web') }
    travel_to(Time.zone.parse('2026-10-21 12:00')) do
      Game::Wallet.apply!([{ account: harry, money: -20, items: { '칭찬권' => 2 } }], kind: 'purchase', detail: '칭찬권 2개', actor: 'web')
      Game::Wallet.apply!([{ account: harry, money: -10, items: { '벌점권' => 1 } }], kind: 'purchase', detail: '벌점권 1개', actor: 'web')
    end

    GameHousePoint.create!(house: house, account: harry, counter: praise, amount: 6, reason: '상점 3회')
    GameHousePoint.create!(house: house, account: harry, counter: report, amount: -4, reason: '벌점 2회')
    GameHousePoint.create!(house: house, account: harry, amount: 10, reason: '응원봉 → 그리핀도르')
  end

  it 'only shows what it would do without APPLY' do
    run(apply: false)

    expect(GameHousePoint.count).to eq 3
    expect(character.money).to eq 60
    expect(count_of('칭찬권')).to eq 3
  end

  it 'resets the merit points, refunds the purchases after the cutoff and removes those items, once' do
    run(apply: true)

    expect(GameHousePoint.pluck(:amount)).to match_array([-4, 10])
    # 10월 21일 칭찬권 2개(20)만 환불, 10월 19일 구입과 벌점권은 그대로
    expect(character.money).to eq 80
    expect(count_of('칭찬권')).to eq 1
    expect(count_of('벌점권')).to eq 1
    expect(GameReward.where(kind: 'admin', actor: 'undo_merit').count).to eq 1

    run(apply: true)
    expect(character.money).to eq 80
    expect(count_of('칭찬권')).to eq 1
  end

  it 'rolls back the merit count raised by using the refunded items, as many as were bought, and only once' do
    ron = Fabricate(:account, username: 'ron')
    GameCharacter.for(ron).update!(house: house)
    travel_to(Time.zone.parse('2026-10-21 13:00')) do
      # 구입한 2개 중 2번 사용 + 구입하지 않은(기준 이전 구입분) 사용 1번이 더 있다
      2.times { praise.add!(GameCharacter.for(ron), 1, item: '칭찬권', reason: '칭찬권 → 론', actor: 'web', source: harry) }
    end
    praise.add!(GameCharacter.for(ron), 1, item: '칭찬권', reason: '칭찬권 → 론', actor: 'web', source: Fabricate(:account, username: 'luna'))
    expect(praise.raw_for(GameCharacter.for(ron).reload)).to eq 3

    run(apply: true)

    expect(praise.raw_for(GameCharacter.for(ron).reload)).to eq 1 # 해리가 쓴 2번만 되돌리고, 다른 사람이 쓴 1번은 그대로
    expect(GameCounterLog.where(actor: 'undo_merit').count).to eq 2

    run(apply: true)
    expect(praise.raw_for(GameCharacter.for(ron).reload)).to eq 1
  end

  it 'rolls back uses logged before the source column existed, even after the purchases were already refunded' do
    ron = Fabricate(:account, username: 'ron')
    GameCharacter.for(ron).update!(house: house)
    run(apply: true) # 예전 명령으로 환불만 된 상태

    travel_to(Time.zone.parse('2026-10-21 13:00')) do
      2.times do
        Game::Wallet.apply!([{ account: harry, items: { '칭찬권' => 0 } }], kind: 'use', detail: '칭찬권 → 론', actor: 'web')
        praise.add!(GameCharacter.for(ron), 1, item: '칭찬권', reason: '칭찬권 → 론', actor: 'web')
      end
    end
    expect(praise.raw_for(GameCharacter.for(ron).reload)).to eq 2

    run(apply: true)
    expect(praise.raw_for(GameCharacter.for(ron).reload)).to eq 0
    expect(character.money).to eq 80

    run(apply: true)
    expect(GameCounterLog.where(actor: 'undo_merit').count).to eq 2
  end

  it 'refunds in full even when the items were already used, deleting only what is left' do
    Game::Wallet.apply!([{ account: harry, items: { '칭찬권' => -2 } }], kind: 'use')

    run(apply: true)

    expect(character.money).to eq 80
    expect(count_of('칭찬권')).to eq 0
  end
end
