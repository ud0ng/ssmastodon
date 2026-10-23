# frozen_string_literal: true

module Game
  # 일일 활동 스냅샷: 하루(한국 시간 00시 기준)마다 캐릭터가 쓴 툿의 수와 글자 수를 저장해 두고,
  # 캐릭터 관리 > 활동·활동 기록과 글쓰기 패널(어제 + 오늘)이 이 표만 읽게 한다 (툿 전체를 매번 세지 않게).
  #
  #   game_activity_days   캐릭터×날짜: 전체(퍼블+답, DM 제외)·DM·퍼블·답 툿 수·글자 수, 답 횟수, 미디어 툿 수
  #   game_activity_pairs  캐릭터×상대 캐릭터×날짜: 답 툿 수·글자 수·미디어·답 횟수, DM 툿 수·글자 수
  #
  # 세는 법은 예전 활동 화면과 같다 (Game::Activity): 부스트·지운 툿은 빼고, 퍼블은 답이 아닌 툿, 답 툿은 답글, 글자 수는 본문 길이,
  # 답 횟수는 다른 사람의 (답이 아닌 퍼블) 툿에 답을 단 것을 같은 툿에는 1회로 센다 (날짜마다 따로), 미디어는 사진 등을 붙인 툿 (DM 제외).
  #
  # 오늘 것은 툿이 저장될 때마다 쌓고 (record! ← Game::ActivitySnapshotWorker), 하루가 끝나면 그날 것을 툿에서 다시 계산해 맞춘다 (rebuild!, 지운 툿 반영).
  # 지난 날은 한꺼번에 올린다 (catch_up! ← game:activity_backfill, 매일 밤 스케줄러가 빠진 날을 채운다).
  module ActivitySnapshot
    ZONE = 'Asia/Seoul'
    KEY = 'activity_snapshot'

    COLUMNS = GameActivityDay::COLUMNS
    PAIR_COLUMNS = GameActivityPair::COLUMNS

    # 합계 한 줄 (캐릭터 하나·소속·전체 어디든)
    Totals = Struct.new(*COLUMNS, keyword_init: true) do
      def self.empty
        new(**COLUMNS.to_h { |column| [column, 0] })
      end

      def +(other)
        self.class.new(**COLUMNS.to_h { |column| [column, self[column].to_i + other[column].to_i] })
      end

      # 글쓰기 패널·재화 화면에 보여 줄 전체 툿 수 / 글자 수 (DM 포함)
      def all_posts
        posts + dms
      end

      def all_chars
        post_chars + dm_chars
      end
    end

    PairTotals = Struct.new(*PAIR_COLUMNS, keyword_init: true) do
      def self.empty
        new(**PAIR_COLUMNS.to_h { |column| [column, 0] })
      end

      def +(other)
        self.class.new(**PAIR_COLUMNS.to_h { |column| [column, self[column].to_i + other[column].to_i] })
      end
    end

    module_function

    def today
      Time.now.in_time_zone(ZONE).to_date
    end

    def yesterday
      today - 1
    end

    # 그 날(한국 시간)의 툿 번호 범위: 툿 번호가 시간순이라 기본키 범위로 읽는다
    def id_range(date)
      from = date.in_time_zone(ZONE).beginning_of_day
      (Mastodon::Snowflake.id_at(from, with_random: false)...Mastodon::Snowflake.id_at(from + 1.day, with_random: false))
    end

    def statuses_on(date)
      Status.where(id: id_range(date), reblog_of_id: nil).local.reorder(nil)
    end

    # ── 그 날 것을 툿에서 다시 계산해 맞춘다 ──
    def rebuild!(date)
      base = statuses_on(date)
      days = Hash.new { |hash, id| hash[id] = COLUMNS.to_h { |column| [column, 0] } }
      pairs = Hash.new { |hash, key| hash[key] = PAIR_COLUMNS.to_h { |column| [column, 0] } }
      chars = Arel.sql('COALESCE(SUM(char_length(statuses.text)), 0)')
      direct = Status.visibilities[:direct]
      media_ids = MediaAttachment.where.not(status_id: nil).select(:status_id)
      open = base.where.not(visibility: :direct)

      open.group(:account_id).pluck(:account_id, Arel.sql('COUNT(*)'), chars).each { |id, count, sum| days[id].merge!(posts: count, post_chars: sum.to_i) }
      base.where(visibility: :direct).group(:account_id).pluck(:account_id, Arel.sql('COUNT(*)'), chars).each { |id, count, sum| days[id].merge!(dms: count, dm_chars: sum.to_i) }
      open.where(in_reply_to_id: nil).group(:account_id).pluck(:account_id, Arel.sql('COUNT(*)'), chars).each { |id, count, sum| days[id].merge!(public_posts: count, public_chars: sum.to_i) }
      open.where.not(in_reply_to_id: nil).group(:account_id).pluck(:account_id, Arel.sql('COUNT(*)'), chars).each { |id, count, sum| days[id].merge!(reply_posts: count, reply_chars: sum.to_i) }
      open.where(id: media_ids).group(:account_id).count.each { |id, count| days[id][:media] = count }

      turn_scope = open.where.not(in_reply_to_id: nil).joins('INNER JOIN statuses parents ON parents.id = statuses.in_reply_to_id')
                       .where('parents.account_id <> statuses.account_id AND parents.in_reply_to_id IS NULL AND parents.visibility <> ?', direct)
      turn_scope.group('statuses.account_id').pluck(Arel.sql('statuses.account_id'), Arel.sql('COUNT(DISTINCT statuses.in_reply_to_id)')).each { |id, count| days[id][:reply_turns] = count }

      # 상대 캐릭터와: 답 툿(수·글자·미디어·답 횟수), DM(수·글자)
      replies = open.where.not(in_reply_to_id: nil).where.not(in_reply_to_account_id: nil).where('statuses.in_reply_to_account_id <> statuses.account_id')
      replies.group(:account_id, :in_reply_to_account_id).pluck(:account_id, :in_reply_to_account_id, Arel.sql('COUNT(*)'), chars).each do |id, other, count, sum|
        pairs[[id, other]].merge!(reply_posts: count, reply_chars: sum.to_i)
      end
      replies.where(id: media_ids).group(:account_id, :in_reply_to_account_id).count.each { |(id, other), count| pairs[[id, other]][:reply_media] = count }
      turn_scope.where('statuses.in_reply_to_account_id <> statuses.account_id').group('statuses.account_id', 'statuses.in_reply_to_account_id')
                .pluck(Arel.sql('statuses.account_id'), Arel.sql('statuses.in_reply_to_account_id'), Arel.sql('COUNT(DISTINCT statuses.in_reply_to_id)')).each { |id, other, count| pairs[[id, other]][:reply_turns] = count }
      low = id_range(date)
      Mention.joins(:status).where(statuses: { id: low, visibility: :direct, reblog_of_id: nil, local: true }).where('mentions.account_id <> statuses.account_id')
             .group('statuses.account_id', 'mentions.account_id')
             .pluck(Arel.sql('statuses.account_id'), Arel.sql('mentions.account_id'), Arel.sql('COUNT(*)'), Arel.sql('COALESCE(SUM(char_length(statuses.text)), 0)'))
             .each { |id, other, count, sum| pairs[[id, other]].merge!(dms: count, dm_chars: sum.to_i) }

      GameActivityDay.transaction do
        GameActivityDay.where(day: date).delete_all
        GameActivityPair.where(day: date).delete_all
        GameActivityDay.insert_all(days.map { |id, values| { day: date, account_id: id, **values } }) if days.any?
        GameActivityPair.insert_all(pairs.map { |(id, other), values| { day: date, account_id: id, other_account_id: other, **values } }) if pairs.any?
      end
      date
    end

    # ── 툿이 저장될 때 오늘 것에 쌓는다 ──
    def record!(status_id)
      status = Status.find_by(id: status_id)
      return if status.nil? || status.reblog_of_id.present? || !status.local?

      date = status.created_at.in_time_zone(ZONE).to_date
      length = status.text.to_s.size
      day = {}
      pairs = Hash.new { |hash, other| hash[other] = {} }

      if status.direct_visibility?
        day.merge!(dms: 1, dm_chars: length)
        status.mentions.map(&:account_id).uniq.reject { |id| id == status.account_id }.each { |other| pairs[other].merge!(dms: 1, dm_chars: length) }
      else
        day.merge!(posts: 1, post_chars: length)
        media = status.media_attachments.any?
        day[:media] = 1 if media
        if status.in_reply_to_id.present?
          day.merge!(reply_posts: 1, reply_chars: length)
          other = status.in_reply_to_account_id
          turn = new_reply_turn?(status, date)
          day[:reply_turns] = 1 if turn
          if other && other != status.account_id
            pairs[other].merge!(reply_posts: 1, reply_chars: length)
            pairs[other][:reply_media] = 1 if media
            pairs[other][:reply_turns] = 1 if turn
          end
        else
          day.merge!(public_posts: 1, public_chars: length)
        end
      end

      bump!(GameActivityDay, %i(day account_id), [{ day: date, account_id: status.account_id, **day }], day.keys)
      pairs.each { |other, values| bump!(GameActivityPair, :index_game_activity_pairs_on_day_and_accounts, [{ day: date, account_id: status.account_id, other_account_id: other, **values }], values.keys) }
    end

    # 이 답 툿이 그 날 처음으로 그 툿에 단 답인가 (다른 사람의 답이 아닌 퍼블 툿에 단 답만 센다)
    def new_reply_turn?(status, date)
      parent = Status.find_by(id: status.in_reply_to_id)
      return false if parent.nil? || parent.account_id == status.account_id || parent.in_reply_to_id.present? || parent.direct_visibility?

      earlier = id_range(date).begin...status.id # 그 날 이 답보다 먼저 쓴 답만 본다 (워커가 늦거나 다시 돌아도 같은 값)
      !Status.where(id: earlier, account_id: status.account_id, in_reply_to_id: parent.id, reblog_of_id: nil).where.not(visibility: :direct).exists?
    end

    # 있는 줄에는 더하고 없으면 만든다 (동시에 여러 툿이 와도 안전)
    def bump!(model, unique_by, rows, columns)
      table = model.table_name
      model.upsert_all(rows, unique_by: unique_by, on_duplicate: Arel.sql(columns.map { |column| "#{column} = #{table}.#{column} + EXCLUDED.#{column}" }.join(', ')), record_timestamps: true)
    end

    # ── 과거 일괄 올리기 / 매일 밤 맞추기 ──
    def first_day
      id = Status.unscoped.local.minimum(:id)
      id ? Mastodon::Snowflake.to_time(id).in_time_zone(ZONE).to_date : today
    end

    def built_through
      value = GameConfig.find_by(key: KEY)&.data&.dig('built_through')
      value && Date.parse(value)
    end

    def built_through=(date)
      record = GameConfig.find_or_initialize_by(key: KEY)
      record.update!(data: (record.data || {}).merge('built_through' => date.to_s))
    end

    # 빠진 날을 채우고 어제 것을 다시 맞춘다. 처음이면(또는 force) 첫 툿의 날부터 어제까지 전부 + 오늘 지금까지 것도 올린다 (그 뒤로는 툿마다 쌓인다)
    def catch_up!(force: false)
      built = force ? nil : built_through
      start = built ? built + 1 : first_day
      (start..yesterday).each { |date| rebuild!(date) }
      rebuild!(yesterday) if built && start > yesterday
      rebuild!(today) if built.nil?
      self.built_through = yesterday
    end

    # ── 읽기 ──
    def sum_rows(rows)
      rows.reduce(Totals.empty) { |total, row| total + row_totals(row) }
    end

    def row_totals(row)
      Totals.new(**COLUMNS.to_h { |column| [column, row[column].to_i] })
    end

    def range_scope(scope, from, to)
      scope = scope.where(day: from..) if from
      scope = scope.where(day: ..to) if to
      scope
    end

    # account_id => Totals (기간 안 합계, 기간을 안 주면 전체)
    def totals(account_ids, from: nil, to: nil)
      result = Hash.new { |hash, id| hash[id] = Totals.empty }
      range_scope(GameActivityDay.where(account_id: account_ids), from, to).group(:account_id)
                                                                             .pluck(:account_id, *COLUMNS.map { |column| Arel.sql("SUM(#{column})") })
                                                                             .each { |id, *values| result[id] = Totals.new(**COLUMNS.zip(values.map(&:to_i)).to_h) }
      result
    end

    # 날짜 => Totals (여러 캐릭터의 합계), 최근 날짜가 위
    def daily(account_ids, from: nil, to: nil)
      rows = range_scope(GameActivityDay.where(account_id: account_ids), from, to).group(:day).pluck(:day, *COLUMNS.map { |column| Arel.sql("SUM(#{column})") })
      rows.sort_by(&:first).reverse.map { |day, *values| [day, Totals.new(**COLUMNS.zip(values.map(&:to_i)).to_h)] }
    end

    # 상대 캐릭터 id => PairTotals (이 캐릭터 한 명의 기간 합계)
    def pairs(account_id, from: nil, to: nil)
      result = {}
      range_scope(GameActivityPair.where(account_id: account_id), from, to).group(:other_account_id)
                                                                            .pluck(:other_account_id, *PAIR_COLUMNS.map { |column| Arel.sql("SUM(#{column})") })
                                                                            .each { |other, *values| result[other] = PairTotals.new(**PAIR_COLUMNS.zip(values.map(&:to_i)).to_h) }
      result
    end

    # 날짜 => PairTotals (캐릭터와 상대 캐릭터 사이, 최근 날짜가 위)
    def pair_daily(account_id, other_id, from: nil, to: nil)
      rows = range_scope(GameActivityPair.where(account_id: account_id, other_account_id: other_id), from, to).order(day: :desc)
      rows.map { |row| [row.day, PairTotals.new(**PAIR_COLUMNS.to_h { |column| [column, row[column].to_i] })] }
    end

    # 글쓰기 패널: 어제 + 오늘만 읽는다 (DB 부담을 줄이려고 이 이틀 치 줄만). account_id => { yesterday: Totals, today: Totals }
    def recent(account_ids)
      result = Hash.new { |hash, id| hash[id] = { yesterday: Totals.empty, today: Totals.empty } }
      GameActivityDay.where(account_id: account_ids, day: yesterday..today).each do |row|
        result[row.account_id][row.day == today ? :today : :yesterday] = row_totals(row)
      end
      result
    end
  end
end
