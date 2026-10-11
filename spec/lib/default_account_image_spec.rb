# frozen_string_literal: true

require 'rails_helper'

RSpec.describe DefaultAccountImage do
  it 'falls back to the stock image when nothing is uploaded' do
    account = Fabricate(:account)

    expect(described_class.url(:avatar)).to be_nil
    expect(account.avatar_original_url).to end_with('i_missing.png')
  end

  it 'uses the uploaded default avatar for accounts without one' do
    Fabricate(:site_upload, var: 'default_avatar')
    account = Fabricate(:account)

    expect(account.avatar_original_url).to include('site_uploads')
    expect(account.header_original_url).to end_with('h_missing.png')
  end
end
