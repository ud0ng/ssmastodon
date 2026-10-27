# frozen_string_literal: true

module Admin
  # 관리 > 시스템 > 캐릭터 관리 > 활동: 일일 활동 스냅샷(Game::ActivitySnapshot)으로 보는 일자별 통계.
  #   전체: 일자별 모든 캐릭터 합계 / 소속별 / 캐릭터별 (전체 툿·DM 툿·퍼블 툿·답 툿 수와 글자 수, 답 횟수, 미디어 툿 수, 재화)
  #   기간은 오늘·어제·최근 7일·30일·전체·직접 입력. 캐릭터별 머리 칸을 누르면 정렬, 줄을 누르면 그 캐릭터의 일자별 통계와 상대 캐릭터와의 통계.
  #   위의 [지급]으로 재화나 아이템을 여러 캐릭터에게 준다.
  class GameActivitiesController < BaseController
    include Admin::GameGiveForm

    RECORDS = 30
    VIEWS = %w(character house season total).freeze
    RANGES = %w(all today yesterday week month custom).freeze
    SORTS = %w(name posts chars dms dm_chars replies media last_reply partners public_posts public_chars reply_posts reply_chars skipped).freeze
    # 표 칸 → 스냅샷 열
    SORT_FIELDS = { 'posts' => :posts, 'chars' => :post_chars, 'dms' => :dms, 'dm_chars' => :dm_chars, 'replies' => :reply_turns, 'media' => :media,
                    'public_posts' => :public_posts, 'public_chars' => :public_chars, 'reply_posts' => :reply_posts, 'reply_chars' => :reply_chars, 'skipped' => :skipped }.freeze
    # 일자별·소속별·상대 캐릭터별 표의 정렬 (머리 칸을 누르면 그 칸 기준, 표마다 따로 기억한다)
    DAY_SORTS = %w(date posts dms public_posts reply_posts replies media skipped).freeze
    HOUSE_SORTS = (%w(name members) + SORT_FIELDS.keys).freeze
    PAIR_FIELDS = { 'reply_posts' => :reply_posts, 'reply_chars' => :reply_chars, 'media' => :reply_media, 'replies' => :reply_turns,
                    'dms' => :dms, 'dm_chars' => :dm_chars, 'skipped' => :skipped }.freeze
    PAIR_SORTS = (%w(rank name overall) + PAIR_FIELDS.keys).freeze
    PAIR_DAY_SORTS = (%w(date) + PAIR_FIELDS.keys).freeze
    helper_method :sort_state, :sort_column, :sort_direction, :view_name, :range_name, :range_from, :range_to

    def index
      authorize :settings, :show?

      GameCharacter.sync!
      Game::ActivityBackfillWorker.perform_async if Game::ActivitySnapshot.built_through.nil?
      @characters = GameCharacter.visible.includes(:house, :faction, :account).joins(:account)
                                 .order(Arel.sql('accounts.username')).to_a
      @filter_house = GameHouse.find_by(id: params[:house]) if params[:house].present?
      scope = @filter_house ? @characters.select { |character| character.group == @filter_house } : @characters
      ids = scope.map(&:account_id)
      @criteria = Game::Activity.criteria
      load_season_context
      case view_name
      when 'total'
        @daily = Game::ActivitySnapshot.daily(ids, from: range_from, to: range_to)
        @total = @daily.reduce(Game::ActivitySnapshot::Totals.empty) { |sum, (_, row)| sum + row }
        @chart_days = chart_days(@daily)
        @daily = sort_table(:days, @daily, DAY_SORTS, default: 'date', default_dir: 'desc') { |(day, row), key| key == 'date' ? day : [row[SORT_FIELDS.fetch(key)].to_i, day] }
      when 'season'
        load_season_rows(ids)
      when 'house'
        load_house_rows(Game::ActivitySnapshot.totals(@characters.map(&:account_id), from: range_from, to: range_to))
      else
        @totals = Game::ActivitySnapshot.totals(ids, from: range_from, to: range_to)
        staff_ids = Account.where('lower(username) IN (?)', GameCharacter.staff_usernames.presence || ['']).pluck(:id)
        @alerts = Game::Activity.alerts(ids, hours: @criteria[:hours], staff_ids: staff_ids)
        sorted = scope.sort_by { |character| sort_value(character) }
        @characters = sort_direction == 'desc' ? sorted.reverse : sorted
      end
      load_give_form
    end

    # 한 캐릭터: 탭 일자별(그래프·표) / 상대 캐릭터별(비율 그래프·표, 상대를 고르면 그 상대와의 일자별 그래프·표) / 활동 기록(검색 화면으로)
    def stats
      authorize :settings, :show?

      @tab = params[:tab] == 'pairs' ? 'pairs' : 'days'
      @character = GameCharacter.visible.find(params[:id])
      @characters = GameCharacter.visible.includes(:account, :house, :faction).to_a
      @daily = Game::ActivitySnapshot.daily([@character.account_id], from: range_from, to: range_to)
      @total = @daily.reduce(Game::ActivitySnapshot::Totals.empty) { |sum, (_, row)| sum + row }
      by_account = @characters.index_by(&:account_id)
      load_fairness
      @opponent = by_account[params[:opponent].to_i]
      @chart_days = chart_days(@daily)
      @daily = sort_table(:days, @daily, DAY_SORTS, default: 'date', default_dir: 'desc') { |(day, row), key| key == 'date' ? day : [row[SORT_FIELDS.fetch(key)].to_i, day] }
      @pairs = sort_table(:pairs, @pairs, PAIR_SORTS, default: 'rank', param: :psort, dir_param: :pdir) do |(other, row), key|
        case key
        when 'rank' then @ranks[other.account_id]
        when 'name' then other.display_name.downcase
        when 'overall' then [@scores[other.account_id].overall || -1, other.display_name.downcase]
        else [row[PAIR_FIELDS.fetch(key)].to_i, other.display_name.downcase]
        end
      end
      load_pair_days if @opponent
    end

    # 과거 툿 활동을 스냅샷으로 다시 올린다 (처음 한 번, 또는 지운 툿을 반영해 전부 다시)
    def backfill
      authorize :settings, :update?

      Game::ActivityBackfillWorker.perform_async(true)
      redirect_to admin_game_activities_path, notice: t('admin.games.activity.backfill_started')
    end

    def show
      authorize :settings, :show?

      @character = GameCharacter.visible.find(params[:id])
      @stats = Game::Activity.stats([@character.account_id])[@character.account_id]
      @records = GameReward.where(account_id: @character.account_id).order(id: :desc).limit(RECORDS)
      @item_images = GameShopItem.by_key
      @shop_item_names = GameShopItem.pluck(:name)
      @currency = Game::Config.for('common')['currency_name']
      @rule = Game::Activity.reward_rule
    end

    # 활동 화면 맨 위: 활동 기준 시간(1~24시간)과 최소 교류 캐릭터 수
    def criteria
      authorize :settings, :update?

      Game::Config.merge!('common', 'activity_hours' => params[:activity_hours].to_i.clamp(1, 24), 'activity_min_partners' => [params[:activity_min_partners].to_i, 0].max)
      redirect_to admin_game_activities_path, notice: t('generic.changes_saved_msg')
    end

    # 지급: 재화(kind money) 또는 아이템(kind items)을 고른 캐릭터들에게
    def give
      authorize :settings, :update?

      accounts = GameCharacter.visible.where(id: Array(params[:character_ids])).includes(:account).map(&:account)
      return give_counter(accounts) if params[:give_kind] == 'counter'

      money = params[:give_kind] == 'money' ? params[:money].to_i : 0 # 마이너스면 차감
      items = params[:give_kind] == 'items' ? picked_items : {}
      if accounts.empty? || (money.zero? && items.empty?)
        redirect_to give_return_path(modal: 'activity-give'), alert: t('admin.games.activity.give_nothing')
        return
      end

      changes = accounts.map { |account| { account: account, money: money, items: items } }
      begin
        Game::Wallet.apply!(changes, kind: 'admin', detail: params[:reason].to_s.strip.presence || t('admin.games.activity.give'), actor: current_account.username)
      rescue Game::Wallet::Error => e
        return redirect_to(give_return_path(modal: 'activity-give'), alert: e.message)
      end
      notify_given(accounts, money, items) unless money.negative?
      redirect_to give_return_path, notice: t('admin.games.activity.given', count: accounts.size)
    end

    private

    # 누적 수치 지급: 고른 캐릭터마다 +/- 만큼 (누적 효과·누적 수치 기록이 함께 맞춰진다). DM 은 보내지 않는다
    def give_counter(accounts)
      counter = GameCounter.find_by(id: params[:counter_id])
      amount = params[:counter_amount].to_i
      return redirect_to(give_return_path(modal: 'activity-give'), alert: t('admin.games.activity.give_nothing')) if accounts.empty? || counter.nil? || amount.zero?

      reason = params[:reason].to_s.strip.presence || t('admin.games.activity.give')
      accounts.each { |account| counter.add!(GameCharacter.for(account), amount, reason: reason, actor: current_account.username) }
      redirect_to give_return_path, notice: t('admin.games.activity.given', count: accounts.size)
    end

    # 받은 캐릭터마다 시스템 계정이 DM 으로 알린다 (여러 명이면 한 명씩 따로). 하나가 실패해도 나머지는 보낸다.
    # 지급은 이미 끝난 뒤라(트랜잭션 밖) 멘션 알림이 바로 간다.
    def notify_given(accounts, money, items)
      common = Game::Config.for('common')
      rewards = Game::Rewards.describe(money, items.map { |name, count| { 'name' => name, 'count' => count } }, common['currency_name'])
      text = Game::Text.render(common['msg_admin_give'], rewards: rewards)
      accounts.each do |account|
        Game::Poster.post(text, mentions: [account], thread: nil, visibility: 'direct')
      rescue StandardError => e
        Rails.logger.warn { "admin give notice to #{account.username} failed: #{e.class} #{e.message}" }
      end
    end

    CHART_DAYS = 60

    # 그래프용 날짜별 합계: 빈 날 포함, 최근 CHART_DAYS 일까지 [[날짜, Totals]] (오래된 날부터)
    def chart_days(daily)
      by_day = daily.to_h
      last = range_to || Game::ActivitySnapshot.today
      first = range_from || by_day.keys.min || last
      first = [first, last - (CHART_DAYS - 1)].max
      (first..last).map { |day| [day, by_day[day] || Game::ActivitySnapshot::Totals.empty] }
    end

    # 상대 캐릭터별 (편애·차별 보기, Game::Fairness): 다른 모든 캐릭터를 (한 번도 안 주고받았어도) 줄로 세우고
    # 이 캐릭터의 평균과 견준 지수·순위를 매긴다. 아래 줄(상대 → 이 캐릭터)은 그 상대 자신의 평균과 견준다.
    def load_fairness
      others = @characters.reject { |character| character.account_id == @character.account_id }
      ids = others.map(&:account_id)
      empty = Game::ActivitySnapshot::PairTotals.empty
      mine = Game::ActivitySnapshot.pairs(@character.account_id, from: range_from, to: range_to)
      @pairs = others.map { |other| [other, mine[other.account_id] || empty] }
      @pairs_back = Game::ActivitySnapshot.pairs_to(@character.account_id, from: range_from, to: range_to) # 상대 → 이 캐릭터
      @my_total = @pairs.reduce(empty) { |sum, (_, row)| sum + row }
      people = others.size
      @scores = @pairs.to_h { |other, row| [other.account_id, Game::Fairness.score(row, @my_total, people)] }
      @ranks = Game::Fairness.ranks(@pairs.map { |other, row| [other.account_id, row, @scores[other.account_id]] })
      everyone = ids + [@character.account_id]
      back_totals = Game::ActivitySnapshot.pair_sums(ids, everyone, from: range_from, to: range_to)
      @back_scores = ids.index_with { |id| Game::Fairness.score(@pairs_back[id] || empty, back_totals[id] || empty, people) }
    end

    # 이 캐릭터(A)와 고른 상대(B)의 일자별: [[날짜, A→B, B→A]] 최근 날짜가 위 (두 쪽 중 한쪽이라도 기록이 있는 날)
    def load_pair_days
      mine = Game::ActivitySnapshot.pair_daily(@character.account_id, @opponent.account_id, from: range_from, to: range_to).to_h
      theirs = Game::ActivitySnapshot.pair_daily(@opponent.account_id, @character.account_id, from: range_from, to: range_to).to_h
      empty = Game::ActivitySnapshot::PairTotals.empty
      @pair_days = (mine.keys | theirs.keys).sort.reverse.map { |day| [day, mine[day] || empty, theirs[day] || empty] }
      @pair_days = sort_table(:pair_days, @pair_days, PAIR_DAY_SORTS, default: 'date', default_dir: 'desc', param: :dsort, dir_param: :ddir) { |(day, row, _), key| key == 'date' ? day : [row[PAIR_FIELDS.fetch(key)].to_i, day] }
      @pair_mine = @pair_days.reduce(empty) { |sum, (_, row, _)| sum + row }
      @pair_theirs = @pair_days.reduce(empty) { |sum, (_, _, row)| sum + row }
    end

    def sort_column
      SORTS.include?(params[:sort]) ? params[:sort] : 'name'
    end

    def view_name
      VIEWS.include?(params[:view]) ? params[:view] : 'character'
    end

    def range_name
      RANGES.include?(params[:range]) ? params[:range] : 'all'
    end

    # 기간 (한국 시간 날짜). 전체면 둘 다 nil
    def range_from
      today = Game::ActivitySnapshot.today
      case range_name
      when 'today' then today
      when 'yesterday' then today - 1
      when 'week' then today - 6
      when 'month' then today - 29
      when 'custom' then parse_day(params[:from])
      end
    end

    def range_to
      today = Game::ActivitySnapshot.today
      case range_name
      when 'today' then today
      when 'yesterday' then today - 1
      when 'week', 'month' then today
      when 'custom' then parse_day(params[:to])
      end
    end

    def parse_day(value)
      Date.parse(value.to_s)
    rescue Date::Error
      nil
    end

    # 시즌별 합계 (캐릭터 관리 > 소속 > 시즌): 시즌의 날짜 범위만큼의 일일 활동 스냅샷을 더한다 → 시즌마다 0부터 시작한다.
    # 진행 중인 시즌(또는 끝나는 날이 없는 시즌)은 오늘 쓰는 툿까지 실시간으로 쌓인다. 시작·종료 날짜를 안 적은 시즌은 앞 시즌이 끝난 다음 날부터, 끝난 시즌은 끝낸 날까지.
    # 값: [[시즌, 시작일, 종료일, Totals]] 최근 시즌이 위
    # 시즌 줄에서 들어온 캐릭터별: 그 시즌의 날짜 범위를 기간으로 쓴다
    def load_season_context
      return unless view_name == 'character' && params[:season].present?

      @season, @season_from, @season_to = GameSeason.dated.find { |each, *| each.id == params[:season].to_i }
    end

    def load_season_rows(ids)
      @season_rows = Game::ActivitySnapshot.by_season(ids).reverse
    end

    # 소속별 합계 (소속 없음 포함): [[소속 또는 nil, 인원, Totals]]
    def load_house_rows(totals)
      groups = @characters.group_by(&:group)
      # 새로 만든 소속도 인원이 0명이어도 바로 보인다
      GameHouse.active.each { |house| groups[house] ||= [] }
      @house_rows = groups.map do |house, members|
        [house, members.size, members.reduce(Game::ActivitySnapshot::Totals.empty) { |sum, character| sum + totals[character.account_id] }]
      end
      @house_rows.sort_by! { |house, _, _| [house ? 0 : 1, house&.position.to_i, house&.id.to_i] }
      @house_rows = sort_table(:houses, @house_rows, HOUSE_SORTS, default: nil) do |(house, count, totals), key|
        case key
        when 'name' then [house ? 0 : 1, house&.name.to_s.downcase]
        when 'members' then count
        else totals[SORT_FIELDS.fetch(key)].to_i
        end
      end
    end

    # rows 를 표의 정렬대로 세운다 (같은 값이면 원래 순서). 표마다 [고른 칸, 방향]을 @sort_states 에 기억해 머리 칸이 읽는다.
    def sort_table(table, rows, keys, default:, default_dir: 'asc', param: :sort, dir_param: :dir)
      key = keys.include?(params[param]) ? params[param] : default
      direction = %w(asc desc).include?(params[dir_param]) ? params[dir_param] : (params[param] ? 'asc' : default_dir)
      (@sort_states ||= {})[table] = [key, direction]
      return rows if key.nil?

      sorted = rows.each_with_index.sort_by { |row, index| [yield(row, key), index] }.map(&:first)
      direction == 'desc' ? sorted.reverse : sorted
    end

    def sort_state(table)
      (@sort_states || {}).fetch(table, [nil, 'asc'])
    end

    def sort_direction
      params[:dir] == 'desc' ? 'desc' : 'asc'
    end

    def sort_value(character)
      return [character.display_name.downcase] if sort_column == 'name'
      return [@alerts[character.account_id].last_reply_at&.to_i.to_i, character.display_name.downcase] if sort_column == 'last_reply'
      return [@alerts[character.account_id].partners, character.display_name.downcase] if sort_column == 'partners'

      [@totals[character.account_id][SORT_FIELDS.fetch(sort_column)].to_i, character.display_name.downcase]
    end

    # 아이템 고르기(admin/ui/_item_picker): items[][name], items[][count] → { 이름 => 개수 } (상점에 있는 아이템만, 같은 이름은 더한다)
    def picked_items
      known = GameShopItem.pluck(:name).to_set
      Array(params[:items]).each_with_object(Hash.new(0)) do |item, total|
        name = item[:name].to_s.strip
        count = item[:count].to_i
        total[name] += count if known.include?(name) && count.positive?
      end
    end
  end
end
