# frozen_string_literal: true

require 'rails_helper'

RSpec.describe BotSheets do
  subject(:bot_sheet) { described_class.new('main', backend: BotSheets::LocalBackend.new(dir)) }

  let(:dir) { Dir.mktmpdir }

  before do
    FileUtils.mkdir_p(File.join(dir, 'main'))
    File.write(File.join(dir, 'main', '설정.csv'), <<~CSV)
      설정 시트
      항목,값,설명
      재화 이름,코인,소지금 단위
      키워드 이미지,사용,키워드 답변 이미지
      합계,=1+1,수식
      하루 조사 횟수,3,
    CSV
    File.write(File.join(dir, 'main', '상점.csv'), "아이템명,가격\n사과,1\n")
  end

  after { FileUtils.remove_entry(dir) }

  describe '.id' do
    it 'takes the ID out of a sheet URL' do
      Setting.bot_sheet_main_id = 'https://docs.google.com/spreadsheets/d/abc-123_X/edit#gid=0'
      expect(described_class.id('main')).to eq 'abc-123_X'
    end

    it 'lists only connected sheets' do
      Setting.bot_sheet_main_id = 'abc'
      Setting.bot_sheet_story_id = ''
      expect(described_class.connected).to include('main')
      expect(described_class.connected).to_not include('story')
    end
  end

  describe '#settings' do
    it 'reads items under the header row, leaving out what moved to Mastodon' do
      expect(bot_sheet.settings.map { |item| [item.row, item.name, item.value, item.formula] }).to eq [
        [4, '키워드 이미지', '사용', false],
        [5, '합계', '=1+1', true],
        [6, '하루 조사 횟수', '3', false],
      ]
      expect(bot_sheet.settings.first).to be_switch
      expect(bot_sheet.settings.first).to_not be_number
      expect(bot_sheet.settings.last).to be_number
    end
  end

  describe '#update_settings' do
    it 'writes changed values only' do
      expect(bot_sheet.update_settings(6 => %w(3 5), 4 => %w(사용 사용))).to eq 1
      expect(bot_sheet.rows('설정')[5]).to eq ['하루 조사 횟수', '5', '']
    end

    it 'does not touch formula cells' do
      expect(bot_sheet.update_settings(5 => %w(=1+1 3))).to eq 0
    end

    it 'refuses to save when the sheet changed meanwhile' do
      expect { bot_sheet.update_settings(6 => %w(1 9)) }.to raise_error(BotSheets::Conflict) { |error| expect(error.names).to eq ['하루 조사 횟수'] }
      expect(bot_sheet.rows('설정')[5][1]).to eq '3'
    end

    it 'does not save items that moved to Mastodon' do
      expect(bot_sheet.update_settings(3 => %w(코인 골드))).to eq 0
      expect(bot_sheet.rows('설정')[2][1]).to eq '코인'
    end
  end

  describe '#table' do
    before do
      File.write(File.join(dir, 'main', '명단.csv'), <<~CSV)
        안내 문구
        이름,아이디,,메모
        엘레나,elena,,

      CSV
    end

    it 'splits notes, header and rows' do
      table = bot_sheet.table('명단')
      expect(table.notes).to eq ['안내 문구']
      expect(table.header).to eq ['이름', '아이디', '', '메모']
      expect(table.rows.map(&:cells)).to eq [['엘레나', 'elena', '', '']]
      expect(table.rows.map(&:number)).to eq [3]
    end

    it 'appends a row in header order, leaving blank header columns empty' do
      expect(bot_sheet.append_row('명단', %w(카일 kyle 무시 메모))).to be true
      expect(bot_sheet.table('명단').rows.last.cells).to eq ['카일', 'kyle', '', '메모']
    end

    it 'updates only the changed cells of a row' do
      expect(bot_sheet.update_row('명단', 3, ['엘레나', 'elena', '', ''], ['엘레나', 'elena', '무시', '새 메모'])).to eq 1
      expect(bot_sheet.table('명단').rows.first.cells).to eq ['엘레나', 'elena', '', '새 메모']
    end

    it 'deletes a row' do
      bot_sheet.append_row('명단', %w(카일 kyle))
      bot_sheet.delete_row('명단', 3, ['엘레나', 'elena'])
      expect(bot_sheet.table('명단').rows.map { |row| row.cells.first }).to eq ['카일']
    end

    it 'refuses to edit or delete a row that changed or moved meanwhile' do
      expect { bot_sheet.update_row('명단', 3, %w(다른사람 other), %w(x y)) }.to raise_error(BotSheets::Conflict)
      expect { bot_sheet.delete_row('명단', 4, %w(엘레나 elena)) }.to raise_error(BotSheets::Conflict)
      expect(bot_sheet.table('명단').rows.first.cells.first).to eq '엘레나'
    end

    it 'does not append an empty row' do
      expect(bot_sheet.append_row('명단', ['', ''])).to be false
    end
  end

  describe '.group_settings' do
    it 'groups known items and puts the rest under others' do
      groups = described_class.group_settings(bot_sheet.settings).to_h { |group, items| [group, items.map(&:name)] }
      expect(groups).to eq('features' => ['키워드 이미지', '하루 조사 횟수'], 'others' => ['합계'])
    end
  end

  describe '#worksheets' do
    it 'lists the worksheets but hides the ones that moved to Mastodon' do
      expect(bot_sheet.worksheets).to include('설정')
      expect(bot_sheet.worksheets).to_not include('상점')
      expect(bot_sheet.moved_worksheets).to eq ['상점']
    end
  end

  describe '.moved_command?' do
    it 'spots help lines of commands that moved to Mastodon' do
      moved = ['[가방]', '[구매/아이템명]', '[상태 확인]', '[소지금 추가/10/전원]', '[힘 변경/+3/겐지]']
      kept = ['[운세]', '[NdM]', '[랜덤/A, B]', '[조사/포인트]', '', '설명']
      expect(moved.map { |line| described_class.moved_command?(line) }).to all(be true)
      expect(kept.map { |line| described_class.moved_command?(line) }).to all(be false)
    end
  end
end
