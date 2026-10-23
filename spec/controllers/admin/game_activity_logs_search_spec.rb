# frozen_string_literal: true

require 'rails_helper'

# 활동 기록은 검색만 된다: 캐릭터만, 상대 캐릭터만, 둘 다 (지은 이름이 없는 캐릭터는 계정 표시 이름으로도 찾는다)
RSpec.describe Admin::GameActivityLogsController do
  subject(:controller) { described_class.new }

  let(:harry) { Fabricate(:user, account: Fabricate(:account, username: 'harry', display_name: '해리 포터')).account }
  let(:ron) { Fabricate(:user, account: Fabricate(:account, username: 'ron', display_name: '론 위즐리')).account }
  let(:luna) { Fabricate(:user, account: Fabricate(:account, username: 'luna', display_name: '루나')).account }

  def search(**params)
    characters = [harry, ron, luna].map { |account| GameCharacter.for(account) }
    controller.instance_variable_set(:@characters, characters)
    allow(controller).to receive(:params).and_return(ActionController::Parameters.new(params))
    controller.instance_variable_set(:@single, controller.send(:single_character))
    controller.send(:filtered).pluck(:id)
  end

  let!(:reply) { Fabricate(:status, account: harry, text: '론에게', thread: Fabricate(:status, account: ron)) }
  let!(:dm) { Fabricate(:status, account: ron, text: '루나에게 비밀', visibility: :direct).tap { |status| status.mentions.create!(account: luna) } }
  let!(:plain) { Fabricate(:status, account: luna, text: '혼잣말') }

  it 'finds toots by the counterpart alone, by display name, username or part of it' do
    expect(search(opponent: '론 위즐리')).to include(reply.id)
    expect(search(opponent: '위즐')).to include(reply.id)
    expect(search(opponent: 'ron')).to include(reply.id)
    expect(search(opponent: '@ron')).to include(reply.id)
    expect(search(opponent: '루나')).to include(dm.id)
    expect(search(opponent: '루나')).not_to include(plain.id, reply.id)
  end

  it 'combines the character and the counterpart, and finds nothing for an unknown counterpart' do
    expect(search(q: '해리 포터', opponent: '론')).to eq [reply.id]
    expect(search(q: '루나', opponent: '론')).to be_empty
    expect(search(opponent: '없는 사람')).to be_empty
  end
end
