# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Game::Text do
  let(:harry) { Fabricate(:account, username: 'harry') }
  let(:draco) { Fabricate(:account, username: 'draco') }

  before do
    GameCharacter.for(harry).update!(name: '해리')
    GameCharacter.for(draco).update!(name: '드레이코')
  end

  it 'fills Korean tokens for people and values, with particles' do
    text = described_class.render('{상대 계정명}, {계정명}{이가} {컨텐츠}{을를} 신청! ({계정아이디})', player: harry, opponent: draco, game: '마법결투')
    expect(text).to eq '드레이코, 해리가 마법결투를 신청! (@harry)'
  end

  it 'still understands the old %{key} form and leaves unknown tokens' do
    expect(described_class.render('%{player}{은는} {없는 명령어}', player: harry)).to eq '해리는 {없는 명령어}'
  end

  it 'marks avatars to attach' do
    text = described_class.render('{승자 계정 아바타}{승자 계정명}{이가} 이겼다', winner: harry)
    expect(text).to match(/\A#{Game::Text::AVATAR_PATTERN}해리가 이겼다\z/o)
    expect(text.scan(Game::Text::AVATAR_PATTERN).flatten).to eq [harry.id.to_s]
  end

  it 'shows default messages with Korean tokens in the settings' do
    field = Game::Config.schema('common').find { |each| each.key == 'msg_invite' }
    expect(field.default).to include('{상대 계정명}', '{계정명}{이가}', '{컨텐츠}{을를}')
    expect(field.tokens).to include('계정명', '상대 계정명', '컨텐츠')
  end

  describe Game::Poster do
    it 'attaches the profile pictures for avatar tokens and strips the marks' do
      system = Fabricate(:account, username: 'system')
      harry.update!(avatar: Rails.root.join('spec', 'fixtures', 'files', 'avatar.gif').open)
      text = Game::Text.render('{계정 아바타}{계정명}의 승리!', player: harry)

      status = Game::Poster.post(text, mentions: [harry], thread: nil, visibility: 'private')
      expect(status.account).to eq system
      expect(status.text).to eq "@harry\n해리의 승리!"
      expect(status.media_attachments.size).to eq 1
    end
  end
end
