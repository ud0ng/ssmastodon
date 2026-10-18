# frozen_string_literal: true

module Admin
  # 관리 > 시스템 > 캐릭터 관리 > 활동 기록: 캐릭터들이 쓴 툿을 한 줄씩 (시간 · 종류 · 상대 캐릭터 · 내용). 지운 툿·부스트는 없다.
  #   종류: 퍼블(답·미디어가 아닌 툿) / 답 / DM / 미디어(사진 등을 붙인 툿). 한 툿이 여럿에 해당하면 DM > 답 > 미디어 > 퍼블 순.
  #   상대 캐릭터: 답이면 답한 상대, DM 이면 받는 사람 (퍼블·미디어는 없음).
  # 검색: 캐릭터 · 상대 캐릭터 · 종류. 캐릭터 하나를 고르면(활동 기록 상세) 그 캐릭터의 툿만 보인다.
  class GameActivityLogsController < BaseController
    PER_PAGE = 30
    KINDS = %w(public reply dm media).freeze
    CONTENT_LENGTH = 120
    SummaryRow = Struct.new(:character, :replies, :chars, :media, :turns, keyword_init: true)

    helper_method :status_kind, :status_counterparts

    def index
      authorize :settings, :show?

      @characters = GameCharacter.visible.includes(:account).joins(:account).order(Arel.sql('accounts.username')).to_a
      @single = single_character
      @statuses = filtered.includes(:account, :media_attachments, mentions: :account).page(params[:page]).per(PER_PAGE)
      account_ids = @statuses.flat_map { |status| [status.account_id, status.in_reply_to_account_id, *status.mentions.map(&:account_id)] }.compact.uniq
      @characters_by_account = GameCharacter.where(account_id: account_ids).includes(:account).index_by(&:account_id)
      @accounts = Account.where(id: account_ids).index_by(&:id)
      @reply_summary = reply_summary(@single) if @single
    end

    private

    # 캐릭터 하나를 골랐을 때의 요약 카드: 종류가 답인 툿만, 운영진 계정을 뺀 모든 캐릭터와의
    # 답 툿 수 · 툿 글자 수 · 미디어(사진을 붙인 답 툿 수) · 답 횟수(같은 툿에는 1회, 답 툿에 단 답 제외)
    def reply_summary(character)
      others = @characters.reject { |each| each.account_id == character.account_id }
      ids = others.map(&:account_id)
      replies = Status.where(account_id: character.account_id, reblog_of_id: nil, in_reply_to_account_id: ids).where.not(visibility: :direct).where.not(in_reply_to_id: nil).reorder(nil)
      counts = replies.group(:in_reply_to_account_id).pluck(:in_reply_to_account_id, Arel.sql('COUNT(*)'), Arel.sql('COALESCE(SUM(char_length(text)), 0)')).to_h { |id, count, chars| [id, [count, chars.to_i]] }
      media = replies.where(id: media_ids).group(:in_reply_to_account_id).count
      turns = replies.joins('INNER JOIN statuses parents ON parents.id = statuses.in_reply_to_id')
                     .where('parents.in_reply_to_id IS NULL AND parents.visibility <> ?', Status.visibilities[:direct])
                     .group('statuses.in_reply_to_account_id').pluck(Arel.sql('statuses.in_reply_to_account_id'), Arel.sql('COUNT(DISTINCT statuses.in_reply_to_id)')).to_h
      others.map do |other|
        count, chars = counts.fetch(other.account_id, [0, 0])
        SummaryRow.new(character: other, replies: count, chars: chars, media: media.fetch(other.account_id, 0), turns: turns.fetch(other.account_id, 0))
      end.sort_by { |row| [-row.replies, row.character.display_name.downcase] }
    end

    def status_kind(status)
      return 'dm' if status.direct_visibility?
      return 'reply' if status.in_reply_to_id.present?

      status.media_attachments.any? ? 'media' : 'public'
    end

    # 답이면 답한 상대, DM 이면 받는 사람들 (자기 자신은 뺀다)
    def status_counterparts(status)
      ids = case status_kind(status)
            when 'reply' then [status.in_reply_to_account_id]
            when 'dm' then status.mentions.map(&:account_id)
            else []
            end
      ids.compact.uniq.reject { |id| id == status.account_id }.filter_map { |id| @accounts[id] }
    end

    def single_character
      return GameCharacter.find_by(account_id: params[:character]) if params[:character].present?
      return if params[:q].blank?

      matches = @characters.select { |character| [character.display_name, character.account.username].any? { |name| name.casecmp?(params[:q].to_s.strip) } }
      matches.first if matches.one?
    end

    def filtered
      scope = Status.where(account_id: author_ids, reblog_of_id: nil).reorder(id: :desc)
      scope = by_kind(scope, params[:kind].to_s) if KINDS.include?(params[:kind].to_s)
      scope = scope.where(in_reply_to_account_id: counterpart_ids).or(scope.where(id: Mention.where(account_id: counterpart_ids).select(:status_id))) if params[:opponent].present?
      scope
    end

    def media_ids
      MediaAttachment.where.not(status_id: nil).select(:status_id)
    end

    def by_kind(scope, kind)
      case kind
      when 'dm' then scope.where(visibility: :direct)
      when 'reply' then scope.where.not(visibility: :direct).where.not(in_reply_to_id: nil)
      when 'media' then scope.where.not(visibility: :direct).where(in_reply_to_id: nil, id: media_ids)
      else scope.where.not(visibility: :direct).where(in_reply_to_id: nil).where.not(id: media_ids)
      end
    end

    # 글쓴 캐릭터: 한 사람이면 그 사람, 이름 검색이 있으면 맞는 사람들, 없으면 명단 전체
    def author_ids
      return [@single.account_id] if @single

      params[:q].present? ? matching_account_ids(params[:q]) : @characters.map(&:account_id)
    end

    def counterpart_ids
      matching_account_ids(params[:opponent])
    end

    def matching_account_ids(query)
      like = "%#{ActiveRecord::Base.sanitize_sql_like(query.to_s.strip.downcase)}%"
      GameCharacter.visible.joins(:account).where('lower(accounts.username) LIKE ? OR lower(game_characters.name) LIKE ?', like, like).pluck(:account_id)
    end
  end
end
