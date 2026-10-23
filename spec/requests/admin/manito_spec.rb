# frozen_string_literal: true

require 'rails_helper'

# 관리 > RP > 마니또 설정: 저장만 (화면을 그리는 GET 은 Vite 빌드가 필요해서 미리보기로 확인)
RSpec.describe 'Admin manito' do
  let(:harry) { GameCharacter.for(Fabricate(:user).account) }
  let(:ron) { GameCharacter.for(Fabricate(:user).account) }

  before { sign_in Fabricate(:admin_user) }

  it 'saves the settings' do
    patch admin_rp_manito_path, params: { config: { manito_enabled: '1', manito_daily_limit: '3' } }

    expect(response).to redirect_to(admin_rp_manito_path)
    expect(Game::Manito.config).to include('manito_enabled' => true, 'manito_daily_limit' => 3)
  end

  it 'saves the words per counterpart, one per line, and lets staff clear a catch' do
    GameManitoWord.create!(account: harry.account, target_account: ron.account, words: %w(옛말), caught_at: Time.now.utc)

    patch admin_rp_manito_words_path(harry), params: { words: { ron.account_id => "하지마\r\n그만해\r\n하지마\r\n" } }

    expect(response).to redirect_to(admin_rp_manito_words_path(harry))
    pair = GameManitoWord.find_by!(account: harry.account, target_account: ron.account)
    expect(pair.words).to eq %w(하지마 그만해)
    expect(pair).not_to be_caught
    expect(GameManitoWord.where(account: ron.account)).to be_empty
  end
end
