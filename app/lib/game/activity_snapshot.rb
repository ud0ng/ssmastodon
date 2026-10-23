# frozen_string_literal: true

module Game
  # 일일 활동 스냅샷: 하루(한국 시간 00시 기준)마다 캐릭터가 쓴 툿의 수와 글자 수를 저장해 두고,
  # 캐릭터 관리 > 활동·활동 기록과 재화 화면·소속 점수 화면의 툿 합계가 이 표만 읽게 한다 (툿 전체를 매번 세지 않게).
  #
  #   game_activity_days   캐릭터×날짜: 전체(퍼블+답, DM 제외)·DM·퍼블·답 툿 수·글자 수, 답 횟수, 미디어 툿 수
  #   game_activity_pairs  캐릭터×상대 캐릭터×날짜: 답 툿 수·글자 수·미디어·답 횟수, DM 툿 수·글자 수, 스루 수
  #
  # 스루 수(skipped): 상대 캐릭터(B)가 이 캐릭터(A) 한 명만 태그해서 쓴 툿(팔로워 공개·조용한 공개, DM 제외) 뒤로 A가 그 대화에 아무 툿도 쓰지 않은 것.
  # B가 연달아 쓴 툿(그 사이 A의 툿이 없는 것)은 첫 툿 하나로 센다. A가 그중 어느 툿에 답하든, 다른 가지에 이어 쓰든 대화를 이었으면 스루가 아니다.
  # 그래서 한 대화에서 스루는 '마지막에 답을 못 받은 쪽'에 많아야 1이다 (예: A 멘션 - B 답 - A - B - B 로 끝나면 A의 스루 1).
  # 하트를 눌러도 답이 아니니 센다. 시스템·상점봇 계정이 쓰거나 태그된 툿, 태그가 둘 이상(셋 이상이 함께하는 툿)인 툿은 뺀다 (웹 '답장할 멘션'과 비슷한 조건).
  # 날짜는 그 첫 툿을 쓴 날이고, 나중에 A가 그 대화에 쓰면 그 날 것에서 하나 줄인다.
  # 두 사람 사이의 대화 하나는 '찾아간' 쪽의 답 횟수 1(아무도 답하지 않았으면 0)과 끝에 남은 쪽의 스루 1 을 만든다.
  # 그래서 스루 합이 답 횟수 합보다 많은 만큼이 '아무도 답하지 않은 첫 툿' 수다. 대화마다 맞는지는 game:activity_explain 으로 본다.
  #
  # 세는 법은 예전 활동 화면과 같다 (Game::Activity): 부스트·지운 툿은 빼고, 퍼블은 답이 아닌 툿, 답 툿은 답글, 글자 수는 본문 길이,
  # 답 횟수는 다른 사람의 (답이 아닌 퍼블) 툿에 답을 단 것을 같은 툿에는 1회로 센다 (날짜마다 따로), 미디어는 사진 등을 붙인 툿 (DM 제외).
  #
  # 답 횟수(reply_turns): 상대에게 '찾아간' 횟수. 상대(B)가 쓴 첫 툿(남에게 단 답이 아닌 툿, B가 자기 툿에 이어 쓴 툿 포함)에 이 캐릭터(A)가
  # 처음 답을 단 것을 한 번으로 센다. 같은 대화에서는 며칠에 걸쳐 여러 번 답해도 처음 한 번만 (날짜는 처음 답한 날).
  # 시스템·상점봇 계정과의 답은 세지 않는다 (스루 수와 같은 조건).
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

      # 절대 수가 아니라 비율로 보는 값 (분모가 0이면 nil). 답 툿 수는 타래에 따라 달라서 '답 횟수'(찾아간 횟수)를 기준으로 본다
      # 답 횟수당 평균 툿 수: 한 번 찾아가면 평균 몇 번 말을 이었나
      def posts_per_turn
        reply_turns.to_i.positive? ? (reply_posts.to_f / reply_turns).round(1) : nil
      end

      # 툿당 평균 글자 수: 답 툿 하나에 평균 몇 글자를 썼나
      def avg_chars
        reply_posts.to_i.positive? ? (reply_chars.to_f / reply_posts).round : nil
      end

      # 스루율: 스루 ÷ (답 횟수 + 스루). 같은 스루 수라도 찾아간 횟수가 많으면 낮다
      def skip_rate
        total = reply_turns.to_i + skipped.to_i
        total.positive? ? (skipped * 100.0 / total).round(1) : nil
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

      turn_scope = first_visit_scope(open)
      turn_scope.group('statuses.account_id').pluck(Arel.sql('statuses.account_id'), Arel.sql('COUNT(*)')).each { |id, count| days[id][:reply_turns] = count }

      # 상대 캐릭터와: 답 툿(수·글자·미디어·답 횟수), DM(수·글자)
      replies = open.where.not(in_reply_to_id: nil).where.not(in_reply_to_account_id: nil).where('statuses.in_reply_to_account_id <> statuses.account_id')
      replies.group(:account_id, :in_reply_to_account_id).pluck(:account_id, :in_reply_to_account_id, Arel.sql('COUNT(*)'), chars).each do |id, other, count, sum|
        pairs[[id, other]].merge!(reply_posts: count, reply_chars: sum.to_i)
      end
      replies.where(id: media_ids).group(:account_id, :in_reply_to_account_id).count.each { |(id, other), count| pairs[[id, other]][:reply_media] = count }
      turn_scope.group('statuses.account_id', 'parents.account_id')
                .pluck(Arel.sql('statuses.account_id'), Arel.sql('parents.account_id'), Arel.sql('COUNT(*)')).each { |id, other, count| pairs[[id, other]][:reply_turns] = count }
      skipped_scope(id_range(date)).group('mentions.account_id', 'statuses.account_id').count.each do |(id, author), count|
        days[id][:skipped] += count
        pairs[[id, author]][:skipped] = count
      end
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

    # 상대의 '첫 툿' 조건: 다른 사람에게 단 답이 아닌 툿 (답이 아니거나, 자기 툿에 이어 쓴 툿), DM 아님
    FIRST_TOOT = "%<t>s.visibility <> #{Status.visibilities[:direct]} AND (%<t>s.in_reply_to_id IS NULL OR %<t>s.in_reply_to_account_id = %<t>s.account_id)"

    # 그 날 쓴 답 툿 중 '찾아간' 것: 상대의 첫 툿에 단 답이고, 같은 대화에서 이 캐릭터가 그 상대에게 먼저 단 답이 없는 것
    def first_visit_scope(scope)
      excluded = excluded_account_ids
      visit = scope.where.not(in_reply_to_id: nil)
                   .joins('INNER JOIN statuses parents ON parents.id = statuses.in_reply_to_id')
                   .where('parents.account_id <> statuses.account_id AND parents.deleted_at IS NULL')
                   .where(format(FIRST_TOOT, t: 'parents'))
                   .where(<<~SQL.squish)
                     NOT EXISTS (
                       SELECT 1 FROM statuses prior
                         INNER JOIN statuses prior_parents ON prior_parents.id = prior.in_reply_to_id
                        WHERE prior.account_id = statuses.account_id AND prior.conversation_id = statuses.conversation_id AND prior.id < statuses.id
                          AND prior.deleted_at IS NULL AND prior.reblog_of_id IS NULL AND prior.visibility <> #{Status.visibilities[:direct]}
                          AND prior_parents.account_id = parents.account_id AND prior_parents.deleted_at IS NULL AND #{format(FIRST_TOOT, t: 'prior_parents')}
                     )
                   SQL
      excluded.any? ? visit.where.not(account_id: excluded).where.not(parents: { account_id: excluded }) : visit
    end

    # 스루 후보 툿: 멘션 줄 (받은 사람 mentions.account_id, 쓴 사람 statuses.account_id).
    # 연달아 쓴 툿은 첫 툿만: 같은 대화에서 같은 사람이 받은 사람만 태그한 툿이 앞에 있고 그 뒤로 받은 사람이 그 대화에 쓴 툿이 없으면 앞 툿의 연속이다
    SKIP_FIRST_OF_RUN = <<~SQL.squish
      NOT EXISTS (
        SELECT 1
          FROM statuses prev
          INNER JOIN mentions prev_mentions ON prev_mentions.status_id = prev.id AND prev_mentions.account_id = mentions.account_id AND prev_mentions.silent = FALSE
         WHERE prev.account_id = statuses.account_id
           AND prev.conversation_id = statuses.conversation_id
           AND prev.id < statuses.id
           AND prev.deleted_at IS NULL
           AND prev.reblog_of_id IS NULL
           AND prev.visibility IN (#{Status.visibilities[:unlisted]}, #{Status.visibilities[:private]})
           AND (SELECT COUNT(*) FROM mentions others WHERE others.status_id = prev.id AND others.account_id <> prev.account_id AND others.silent = FALSE) = 1
           AND NOT EXISTS (SELECT 1 FROM statuses mine WHERE mine.account_id = mentions.account_id AND mine.conversation_id = statuses.conversation_id AND mine.id > prev.id AND mine.id < statuses.id AND mine.deleted_at IS NULL AND mine.reblog_of_id IS NULL)
      )
    SQL

    # 그 뒤로 받은 사람이 그 대화에 쓴 툿이 없다 (:until 을 주면 그 툿 전까지만 본다)
    SKIP_UNANSWERED = <<~SQL.squish
      NOT EXISTS (
        SELECT 1 FROM statuses later
         WHERE later.account_id = mentions.account_id AND later.conversation_id = statuses.conversation_id
           AND later.id > statuses.id AND later.id < :until AND later.deleted_at IS NULL AND later.reblog_of_id IS NULL
      )
    SQL

    # 한 사람만 태그한 팔로워 공개·조용한 공개 툿의 멘션 줄 (시스템·상점봇 빼고), 연달아 쓴 것은 첫 툿만
    def skip_candidates(status_ids)
      excluded = excluded_account_ids
      scope = Mention.joins(:status).where(silent: false)
                     .where(statuses: { id: status_ids, visibility: %i(unlisted private), reblog_of_id: nil, local: true })
                     .where('mentions.account_id <> statuses.account_id')
                     .where('(SELECT COUNT(*) FROM mentions others WHERE others.status_id = statuses.id AND others.account_id <> statuses.account_id AND others.silent = FALSE) = 1')
                     .where(SKIP_FIRST_OF_RUN)
      excluded.any? ? scope.where.not(account_id: excluded).where.not(statuses: { account_id: excluded }) : scope
    end

    # 스루: 후보 중 그 뒤로 받은 사람이 그 대화에 쓴 툿이 없는 것. status_ids: 툿 번호 범위(그 날) 또는 툿 번호 하나
    def skipped_scope(status_ids, until_id: nil)
      skip_candidates(status_ids).where(SKIP_UNANSWERED, until: until_id || Mastodon::Snowflake.id_at(1.year.from_now, with_random: false))
    end

    # 스루에서 뺄 계정: 시스템 계정, 상점봇 계정
    def excluded_account_ids
      [Game::System.account, *Game::Gift.bot_accounts].compact.map(&:id)
    end

    # 이 툿이 스루 후보면 받은 사람의 계정 번호 (한 명만 태그한 팔로워 공개·조용한 공개 툿)
    def skip_target(status)
      return if status.reblog_of_id.present? || !status.local? || status.direct_visibility? || status.public_visibility?

      mentions = status.mentions.reject { |mention| mention.silent? || mention.account_id == status.account_id }
      return unless mentions.size == 1

      target = mentions.first.account_id
      (excluded_account_ids & [target, status.account_id]).empty? ? target : nil
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
      record_skips!(status, date)
      pairs.each { |other, values| bump!(GameActivityPair, :index_game_activity_pairs_on_day_and_accounts, [{ day: date, account_id: status.account_id, other_account_id: other, **values }], values.keys) }
    end

    # 새 툿이 한 사람만 태그한 스루 후보면 그 사람의 스루 +1 (연달아 쓴 둘째 툿부터는 세지 않는다).
    # 그리고 이 툿을 쓴 사람이 받아 두고 아직 답하지 않은 같은 대화의 스루는 이제 이어졌으니 그 날 것에서 -1
    def record_skips!(status, date)
      target = skip_target(status)
      if target && skipped_scope(status.id, until_id: status.id).exists?(mentions: { account_id: target }) # 뒤의 답은 그 답을 쌓을 때 뺀다
        bump!(GameActivityDay, %i(day account_id), [{ day: date, account_id: target, skipped: 1 }], %i(skipped))
        bump!(GameActivityPair, :index_game_activity_pairs_on_day_and_accounts, [{ day: date, account_id: target, other_account_id: status.account_id, skipped: 1 }], %i(skipped))
      end
      return if status.conversation_id.nil?

      earlier = Status.where(conversation_id: status.conversation_id).where('statuses.id < ?', status.id).select(:id)
      skipped_scope(earlier, until_id: status.id).where(mentions: { account_id: status.account_id })
                                                 .pluck(Arel.sql('statuses.id'), Arel.sql('statuses.account_id')).each do |id, author|
        day = Mastodon::Snowflake.to_time(id).in_time_zone(ZONE).to_date
        bump!(GameActivityDay, %i(day account_id), [{ day: day, account_id: status.account_id, skipped: -1 }], %i(skipped))
        bump!(GameActivityPair, :index_game_activity_pairs_on_day_and_accounts, [{ day: day, account_id: status.account_id, other_account_id: author, skipped: -1 }], %i(skipped))
      end
    end

    # 이 답 툿이 그 상대에게 '찾아간' 것인가: 상대의 첫 툿에 단 답이고, 같은 대화에서 이 캐릭터가 그 상대에게 먼저 단 답이 없다 (워커가 늦거나 다시 돌아도 같은 값)
    def new_reply_turn?(status, _date)
      parent = Status.find_by(id: status.in_reply_to_id)
      return false if parent.nil? || parent.account_id == status.account_id || parent.direct_visibility? || (excluded_account_ids & [status.account_id, parent.account_id]).any?
      return false unless parent.in_reply_to_id.nil? || parent.in_reply_to_account_id == parent.account_id

      earlier = Status.where(account_id: status.account_id, conversation_id: status.conversation_id, reblog_of_id: nil).where('statuses.id < ?', status.id).where.not(visibility: :direct)
                      .where.not(in_reply_to_id: nil)
      earlier_parents = Status.where(id: earlier.select(:in_reply_to_id), account_id: parent.account_id).where.not(visibility: :direct)
                              .where('in_reply_to_id IS NULL OR in_reply_to_account_id = account_id')
      !earlier_parents.exists?
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

    # 상대 캐릭터 id => PairTotals (상대들이 이 캐릭터에게 한 것: 상대 → 이 캐릭터, 기간 합계)
    def pairs_to(account_id, from: nil, to: nil)
      result = {}
      range_scope(GameActivityPair.where(other_account_id: account_id), from, to).group(:account_id)
                                                                                  .pluck(:account_id, *PAIR_COLUMNS.map { |column| Arel.sql("SUM(#{column})") })
                                                                                  .each { |other, *values| result[other] = PairTotals.new(**PAIR_COLUMNS.zip(values.map(&:to_i)).to_h) }
      result
    end

    # 캐릭터 id => PairTotals (그 캐릭터가 other_ids 의 상대들에게 한 것의 합계)
    def pair_sums(account_ids, other_ids, from: nil, to: nil)
      result = {}
      range_scope(GameActivityPair.where(account_id: account_ids, other_account_id: other_ids), from, to).group(:account_id)
                                                                                                         .pluck(:account_id, *PAIR_COLUMNS.map { |column| Arel.sql("SUM(#{column})") })
                                                                                                         .each { |id, *values| result[id] = PairTotals.new(**PAIR_COLUMNS.zip(values.map(&:to_i)).to_h) }
      result
    end

    # 날짜 => PairTotals (캐릭터와 상대 캐릭터 사이, 최근 날짜가 위)
    def pair_daily(account_id, other_id, from: nil, to: nil)
      rows = range_scope(GameActivityPair.where(account_id: account_id, other_account_id: other_id), from, to).order(day: :desc)
      rows.map { |row| [row.day, PairTotals.new(**PAIR_COLUMNS.to_h { |column| [column, row[column].to_i] })] }
    end
  end
end
