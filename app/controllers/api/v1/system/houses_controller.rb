# frozen_string_literal: true

# 웹 소속 점수 화면 (글쓰기 패널 아래 소속 점수 카드를 누르면): 그 소속의 이번 시즌 점수 내역
#   house: 현재 소속 점수 (이름·색·합계)
#   top_gain: 가장 많이 획득한 사람 (점수를 받은 합계가 가장 큰 캐릭터), top_loss: 가장 많이 깎은 사람 (잃은 합계가 가장 큰 캐릭터)
#   records: 내역을 최신순으로 (filter: gain 획득 / loss 차감, 없으면 전체. 재화 기록처럼 max_id 로 다음 쪽)
class Api::V1::System::HousesController < Api::BaseController
  include Api::GameGate
  include RoutingHelper

  LIMIT = 30

  before_action -> { doorkeeper_authorize! :read }
  before_action :require_user!
  before_action :require_contents_open!
  before_action :set_house

  def show
    scope = season_points
    scope = scope.where(amount: 1..) if params[:filter] == 'gain'
    scope = scope.where(amount: ...0) if params[:filter] == 'loss'
    scope = scope.where(game_counter_id: params[:counter].to_i) if params[:counter].present?
    scope = scope.where(id: ...params[:max_id].to_i) if params[:max_id].present?
    rows = scope.includes(:account).order(id: :desc).limit(LIMIT + 1).to_a
    page = rows.first(LIMIT)
    people = people_for(page.filter_map(&:account) + top_accounts)

    render json: {
      house: { id: @house.id.to_s, name: @house.name, color: @house.color, total: @house.total, term: Game::Config.for('common')['house_term'] },
      top_gain: top(:gain, people),
      top_loss: top(:loss, people),
      counters: house_counters.map { |counter| { id: counter.id.to_s, name: counter.name } },
      members: members_json(house_counters),
      records: page.map { |point| record_json(point, people) },
      next_max_id: rows.size > LIMIT ? page.last.id.to_s : nil,
    }
  end

  private

  # 소속 점수에 영향을 주는 누적 수치 (소속 점수 화면의 탭·배지)
  def house_counters
    @house_counters ||= GameCounter.where(affects_house: true).includes(:opposite).to_a
  end

  # 이 소속 캐릭터들: 아바타·이름(데코·칭호는 웹이 계정 번호로 입힌다)과 누적 수치 결과값(상성은 상쇄한 값)
  def members_json(counters)
    GameCharacter.visible.includes(:account).select { |character| character.group == @house }.sort_by { |character| character.display_name.to_s }.map do |character|
      {
        account_id: character.account_id.to_s,
        name: character.display_name,
        acct: character.account.acct,
        avatar: full_asset_url(character.account.avatar_static_url),
        counters: counters.map { |counter| { id: counter.id.to_s, name: counter.name, value: counter.net_for(character) } },
      }
    end
  end

  def set_house
    @house = GameHouse.find(params[:id])
  end

  # 이번 시즌 점수 (마지막으로 끝난 시즌 뒤에 쌓인 것) — GameHouse#total 과 같은 기준
  def season_points
    since = GameSeason.points_since
    scope = @house.points
    since ? scope.where(created_at: since..) : scope
  end

  # 점수를 받은(gain) / 잃은(loss) 합계가 가장 큰 캐릭터 한 명
  def top(kind, people)
    scope = season_points.where.not(account_id: nil)
    scope = kind == :gain ? scope.where(amount: 1..) : scope.where(amount: ...0)
    sums = scope.group(:account_id).sum(:amount)
    account_id, amount = (kind == :gain ? sums.max_by { |_, value| value } : sums.min_by { |_, value| value })
    return if account_id.nil?

    person_json(people[account_id], amount)
  end

  def top_accounts
    Account.where(id: season_points.where.not(account_id: nil).group(:account_id).select(:account_id)).to_a
  end

  def people_for(accounts)
    accounts.uniq.index_by(&:id).transform_values do |account|
      { account: account, name: GameCharacter.for(account).display_name }
    end
  end

  def person_json(person, amount)
    return if person.nil?

    { name: person[:name], acct: person[:account].acct, avatar: full_asset_url(person[:account].avatar_static_url), points: amount }
  end

  def record_json(point, people)
    {
      id: point.id.to_s,
      amount: point.amount,
      reason: reason_text(point.reason),
      counter: point.counter&.name,
      created_at: point.created_at.iso8601,
      character: point.account && person_json(people[point.account_id], point.amount),
    }
  end

  # 'jellybean' 같은 컨텐츠 키는 컨텐츠 이름으로, 그 밖의 사유(운영진 조정 등)는 그대로
  def reason_text(reason)
    key = reason.to_s.split(':').last
    Game::Kinds.keys.include?(key) ? Game::Kinds.fetch(key).display_name : reason.to_s
  end
end
