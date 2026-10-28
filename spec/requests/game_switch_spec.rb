# frozen_string_literal: true

require 'rails_helper'

# 컨텐츠 기능 스위치 (코드의 Game::Switch::ENABLED, 관리 화면에는 없다): 끄면 관리 화면·API 주소가 없는 주소가 되고, 켜면 그대로 돌아온다
# (화면을 그리는 확인은 Vite 빌드가 필요해 미리보기 서버에서 한다)
RSpec.describe 'Game feature switch' do
  # 주소가 없으면 404, 있으면 로그인·권한 때문에 401/302/403 등 (JSON 으로 받아 화면을 그리지 않는다)
  def not_found?(path)
    get path, headers: { 'Accept' => 'application/json' }
    response.status == 404
  end

  it 'is on by default and keeps the game addresses' do
    expect(Game::Switch.on?).to be true
    expect(not_found?('/admin/games/common')).to be false
    expect(not_found?('/api/v1/system/wallet')).to be false
  end

  describe 'when switched off' do
    before { stub_const('Game::Switch::ENABLED', false) }

    it 'removes the admin game addresses' do
      %w(/admin/games/common /admin/characters /admin/shop/settings /admin/shop/list /admin/rp/manito /admin/sheets /admin/events /admin/characters/houses /admin/settings/staff).each do |path|
        expect(not_found?(path)).to be(true), "#{path} should be 404"
      end
    end

    it 'keeps the server settings and the design tab' do
      expect(not_found?('/admin/settings/registrations')).to be false
      expect(not_found?('/admin/settings/community_theme')).to be false
    end

    it 'blocks the web system and bot APIs' do
      %w(/api/v1/system /api/v1/system/wallet /api/v1/system/fx /api/v1/system/sessions/1 /api/v1/bot/config /api/v1/bot/characters).each do |path|
        get path, headers: { 'Accept' => 'application/json' }
        expect(response).to have_http_status(404), "#{path} should be 404"
      end
    end

    it 'turns the web flags off in the initial state' do
      admin = Fabricate(:admin_user)
      state = ActiveModelSerializers::SerializableResource.new(InitialStatePresenter.new(settings: {}, current_account: admin.account), serializer: InitialStateSerializer).as_json
      expect(state[:meta]).to include(game_enabled: false, shop_enabled: false, contents_enabled: false, events_enabled: false)
    end

    it 'does not enqueue game work when a toot is saved' do
      account = Fabricate(:account)
      expect { Fabricate(:status, account: account, text: 'hello', visibility: :unlisted) }.to_not change(Game::ActivityWorker.jobs, :size)
    end

    it 'skips the schedulers' do
      expect(Game::ActivitySnapshot).to_not receive(:catch_up!)
      Scheduler::GameActivitySnapshotScheduler.new.perform
    end
  end

  it 'enqueues game work when switched on' do
    expect { Fabricate(:status, account: Fabricate(:account), text: 'hello', visibility: :unlisted) }.to change(Game::ActivityWorker.jobs, :size).by(1)
  end

  it 'is not a server setting any more' do
    expect(Form::AdminSettings::KEYS).not_to include(:game_features_enabled)
  end
end
