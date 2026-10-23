# frozen_string_literal: true

module Admin
  # 관리 > RP > 마니또 설정 (Game::Manito): 탭 설정 / 명단 / 기록
  #   설정  해금·제한·보상·명령어·문구 (Game::Config 'manito', 컨텐츠 설정과 같은 편집기)
  #   명단  캐릭터마다 지금 가지고 있는 마니또 보상. 줄을 누르면 그 캐릭터의 상대별 단어·사용 횟수·들킴 (단어는 여기서 고친다)
  #   기록  사용·정답·오답
  class ManitoController < BaseController
    PER_PAGE = 50

    def settings
      authorize :settings, :show?

      @key = Game::Manito::KEY
      @sections = Game::Config.sections(@key, 'settings')
      @values = Game::Config.for(@key)
      @shop_items = GameShopItem.order(:name).map { |item| [item.name, item.image.present? ? item.image.url(:small) : nil] }
    end

    def update
      authorize :settings, :update?

      Game::Config.update!(Game::Manito::KEY, params.fetch(:config, {}).permit!.to_h)
      redirect_to admin_rp_manito_path, notice: t('generic.changes_saved_msg')
    end

    def roster
      authorize :settings, :show?

      @characters = characters.to_a
      ids = @characters.map(&:account_id)
      @holdings = Game::Manito.holdings(ids)
      @word_counts = GameManitoWord.where(account_id: ids).where('jsonb_array_length(words) > 0').group(:account_id).count
      @item_images = GameShopItem.by_key
    end

    def words
      authorize :settings, :show?

      @character = GameCharacter.visible.find(params[:id])
      @others = characters.where.not(id: @character.id).to_a
      @pairs = GameManitoWord.where(account_id: @character.account_id).index_by(&:target_account_id)
      @holding = Game::Manito.holdings([@character.account_id])[@character.account_id]
      @item_images = GameShopItem.by_key
    end

    # 상대마다 단어(줄마다 하나)와 들킴. 들킴을 끄면 다시 보상을 받을 수 있다 (운영진이 되돌릴 때)
    def update_words
      authorize :settings, :update?

      character = GameCharacter.visible.find(params[:id])
      allowed = characters.where.not(id: character.id).pluck(:account_id).to_set
      caught = Array(params[:caught]).map(&:to_i).to_set
      params.fetch(:words, {}).each do |target_id, text|
        target_id = target_id.to_i
        next unless allowed.include?(target_id)

        words = text.to_s.split(/[\r\n]+/).map(&:strip).compact_blank.uniq
        pair = GameManitoWord.find_or_initialize_by(account_id: character.account_id, target_account_id: target_id)
        next if pair.new_record? && words.empty?

        pair.words = words
        pair.caught_at = caught.include?(target_id) ? (pair.caught_at || Time.now.utc) : nil
        pair.save!
      end
      redirect_to admin_rp_manito_words_path(character), notice: t('generic.changes_saved_msg')
    end

    def records
      authorize :settings, :show?

      scope = GameManitoLog.includes(:account, :other_account).order(id: :desc)
      scope = scope.where(kind: params[:kind]) if GameManitoLog::KINDS.include?(params[:kind].to_s)
      @logs = scope.page(params[:page]).per(PER_PAGE)
      @characters_by_account = GameCharacter.where(account_id: @logs.flat_map { |log| [log.account_id, log.other_account_id] }).index_by(&:account_id)
      @item_images = GameShopItem.by_key
    end

    private

    def characters
      GameCharacter.visible.includes(:account, :house, :faction).joins(:account).order(Arel.sql('lower(accounts.username)'))
    end
  end
end
