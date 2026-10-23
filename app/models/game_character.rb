# frozen_string_literal: true

# 캐릭터 명단: 서버원 한 명당 하나 (회원 목록에서 만들고 관리 화면에서 고친다)
class GameCharacter < ApplicationRecord
  belongs_to :account
  belongs_to :house, class_name: 'GameHouse', foreign_key: :game_house_id, optional: true, inverse_of: :characters
  belongs_to :faction, class_name: 'GameHouse', foreign_key: :game_faction_id, optional: true, inverse_of: :faction_characters

  validates :name, length: { maximum: 50 }
  validates :note, length: { maximum: 2_000 }
  validates :grade, numericality: { only_integer: true, in: 1..7 }, allow_nil: true
  validates :money, numericality: { only_integer: true }

  # 게임에 낄 수 있는 서버원 (시스템 계정·정지된 계정 제외)
  # 운영진 계정(서버 설정 > 운영)은 캐릭터가 아니다 — 소속·재화·인벤토리·전적이 없다
  def self.staff_usernames
    Array(Game::Config.for('currency')['admin_usernames']).map { |name| name.to_s.delete_prefix('@').downcase }.compact_blank
  end

  def self.eligible_accounts
    scope = Account.local.without_instance_actor.without_suspended.where(anonymized_at: nil).joins(:user).merge(User.approved.confirmed)
                   .where.not(id: Game::System.account&.id)
    staff = staff_usernames
    staff.any? ? scope.where.not('lower(accounts.username) IN (?)', staff) : scope
  end

  def self.for(account)
    find_or_create_by!(account: account)
  rescue ActiveRecord::RecordNotUnique
    find_by!(account: account)
  end

  # 명단에 보이는 캐릭터 (정지·승인 대기 회원은 캐릭터를 남겨 두고 숨긴다)
  scope :visible, -> { where(account_id: eligible_accounts.select(:id)) }

  # 회원 목록과 맞춘다: 새 회원은 추가하고, 탈퇴한 회원(로그인 계정이 없어진 계정)의 캐릭터는 지운다.
  # 정지된 회원은 지우지 않고 visible 에서 빠진다 (정지를 풀면 돈·인벤토리·스탯 그대로 돌아온다).
  # (회원이 바뀔 때마다 Game::RosterSyncWorker 가 부르고, 명단 화면을 열 때도 한 번 확인한다)
  def self.sync!
    # 탈퇴(계정이 '탈퇴한 사용자'로 바뀐 것)한 회원과 로그인 계정이 없어진 회원의 캐릭터는 지운다
    where.not(account_id: Account.local.where(anonymized_at: nil).joins(:user).select(:id)).destroy_all
    # 운영진 계정의 캐릭터도 지운다 (소속·재화·인벤토리·전적이 없는 계정)
    where(account_id: Account.where('lower(accounts.username) IN (?)', staff_usernames.presence || ['']).select(:id)).destroy_all
    existing = pluck(:account_id)
    eligible_accounts.where.not(id: existing).find_each { |account| find_or_create_by!(account: account) }
  end

  # 점수를 모으는 소속 (공통 설정의 점수 단위에 따라 기숙사·진영·더 만든 종류)
  def group
    group_of(GameHouse.mode)
  end

  def group_id
    case (mode = GameHouse.mode)
    when 'house' then game_house_id
    when 'faction' then game_faction_id
    else group_of(mode)&.id
    end
  end

  # 종류(house·faction·x1 …)별 소속
  def group_of(category)
    case category
    when 'house' then house
    when 'faction' then faction
    else
      id = extra_group_ids[category.to_s]
      id && GameHouse.unscoped.find_by(id: id, category: category.to_s)
    end
  end

  # 종류별 소속 바꾸기 (nil 이면 소속 없음)
  def assign_group!(category, house_record)
    case category
    when 'house' then update!(house: house_record)
    when 'faction' then update!(faction: house_record)
    else update!(extra_group_ids: house_record ? extra_group_ids.merge(category.to_s => house_record.id) : extra_group_ids.except(category.to_s))
    end
  end

  # 이름이나 계정 아이디로 캐릭터를 찾는다 (자동봇·시스템 [사용/아이템/@상대], 웹). 아이디가 같은 캐릭터가 있으면 그쪽만,
  # 없으면 이름(공백 무시)이 같은 캐릭터 → 그 말로 시작하는 캐릭터 → 그 말이 들어 있는 캐릭터 순으로 처음 나온 묶음.
  # 예: '에이비 시디' 는 '에이비' 만 써도 찾는다. 여럿이면 여럿 다 돌려주니 부르는 쪽이 다시 물어본다.
  def self.search(query)
    text = query.to_s.strip.delete_prefix('@').delete_prefix('＠').strip
    key = Game::Wallet.key(text)
    return [] if key.blank?

    username = text.split('@').first.to_s
    characters = visible.includes(:account).to_a
    [
      characters.select { |character| character.account.username.casecmp?(username) },
      characters.select { |character| Game::Wallet.key(character.display_name) == key },
      characters.select { |character| Game::Wallet.key(character.display_name).start_with?(key) },
      characters.select { |character| Game::Wallet.key(character.display_name).include?(key) },
    ].find(&:any?) || []
  end

  def display_name
    name.presence || account.display_name.presence || account.username
  end

  # 저장된 스탯 값 (정수). 입력한 값이 없으면 최소치, 최소~최대 안으로 맞춘다. 일시 효과는 들어 있지 않다 (고치는 화면·변동 계산용)
  def raw_stat_value(field)
    field.clamp(stats.fetch(field.name, field.min))
  end

  # 지금 쓰는 스탯 값: 저장된 값 + 아직 끝나지 않은 일시 효과
  def stat_value(field)
    field.clamp(raw_stat_value(field) + active_effects.sum { |effect| effect['stat'] == field.name ? effect['delta'].to_i : 0 })
  end

  # 상태 수치 계산: 수식에 이 캐릭터의 스탯(일시 효과 포함)을 넣고 영구 변동분을 더한다 (수식이 틀리면 nil)
  def status_value(field, base_fields = GameCharacterField.base_stats)
    Game::Formula.evaluate(field.formula, base_fields.to_h { |base| [base.name, stat_value(base)] }) + stats[field.name].to_i
  rescue Game::Formula::Error
    nil
  end

  # 일시 효과 (아이템 [사용]으로 스탯이 잠깐 오르내림): [{ 'stat', 'delta', 'until' (ISO), 'item' }]
  def active_effects
    Array(effects).select { |effect| Time.zone.parse(effect['until'].to_s)&.future? }
  end

  # 지금 붙은 효과 목록의 칭호·데코 [[effects 안 순서, 효과]] (관리 화면에서 고치고 지운다)
  def fx_entries
    Array(effects).each_with_index.select { |entry, _| entry['kind'] == 'fx' && Time.zone.parse(entry['until'].to_s)&.future? }.map { |entry, index| [index, entry] }
  end

  # 착용 표시 (동물 귀 등): 일정 시간 동안 캐릭터에 붙는 표시
  def add_wear!(label:, minutes:, item:)
    update!(effects: active_effects + [{ 'kind' => 'wear', 'label' => label, 'until' => minutes.minutes.from_now.iso8601, 'item' => item }])
  end

  def wearing
    active_effects.select { |effect| effect['kind'] == 'wear' }
  end

  def add_effect!(stat:, delta:, minutes:, item:)
    update!(effects: active_effects + [{ 'stat' => stat, 'delta' => delta, 'until' => minutes.minutes.from_now.iso8601, 'item' => item }])
  end

  # 인벤토리: [{ name, count, note }] ↔ "이름|개수|메모" 줄
  def inventory_text
    Array(inventory).map { |item| [item['name'], item['count'], item['note'].presence].compact.join('|') }.join("\n")
  end

  def inventory_text=(text)
    self.inventory = text.to_s.lines.filter_map do |line|
      name, count, note = line.split('|', 3).map(&:strip)
      next if name.blank?

      { 'name' => name, 'count' => [count.to_i, 1].max, 'note' => note.to_s }
    end
  end

  # 받은 아이템을 더한다 (이름이 같으면 개수만)
  def add_items(items)
    list = Array(inventory).map(&:dup)
    items.each do |item|
      existing = list.find { |entry| entry['name'] == item['name'] }
      if existing
        existing['count'] = existing['count'].to_i + item['count'].to_i
      else
        list << { 'name' => item['name'], 'count' => item['count'].to_i, 'note' => '' }
      end
    end
    self.inventory = list
  end

  def item_count
    Array(inventory).sum { |item| item['count'].to_i }
  end
end
