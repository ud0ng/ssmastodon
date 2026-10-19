# frozen_string_literal: true

module Admin::GameHelper
  # 컨텐츠 관리 화면 문구: 소속 이름(기숙사/진영 등)을 %{term} 에 넣는다
  def game_t(key, **options)
    t(key, term: Game::Config.for('common')['house_term'], **options)
  end

  # 컨텐츠·과목 그림 (웹 컨텐츠 카드 content_card.tsx 와 같게)
  GAME_ICONS = {
    'jellybean' => '🍬', 'gobstones' => '🔮', 'duel' => '⚡', 'potion' => '⚗️', 'quidditch' => '🧹',
    'levitation' => '🪶', 'flying' => '🧹', 'transfiguration' => '🐈', 'practice' => '✨', 'secret_chamber' => '🐍', 'maze' => '🏆', 'marauders_map' => '🗺️',
  }.freeze

  # 보상 사유 'game:jellybean' → 컨텐츠 이름
  EMOJI = /[🀀-🫿←-⯿️‍]/

  # 앞의 그림 문자는 붙이지 않는다 (예전에 남은 사유에 들어 있어도 지워서 보인다)
  def game_reward_reason(reason)
    key = reason.to_s.split(':').last
    text = Game::Kinds.keys.include?(key) ? Game::Kinds.fetch(key).display_name : reason.to_s
    text.gsub(EMOJI, '').squeeze(' ').strip
  end

  # 효과가 얼마나 남았나: '1일 3시간 남음', 영구면 '영구'
  def game_fx_remaining(entry)
    return t('admin.games.fx.forever') if Game::Fx.permanent?(entry)

    seconds = (Time.zone.parse(entry['until'].to_s) - Time.current).to_i
    return t('admin.games.fx.ended') if seconds <= 0

    days, rest = seconds.divmod(86_400)
    hours, rest = rest.divmod(3600)
    parts = [(days.positive? ? "#{days}일" : nil), (hours.positive? ? "#{hours}시간" : nil), (days.zero? && (rest / 60).positive? ? "#{rest / 60}분" : nil)].compact
    "#{parts.join(' ').presence || '1분 미만'} #{t('admin.games.fx.left')}"
  end

  # datetime-local 칸 값 (UTC). 마스토돈 관리 화면 스크립트가 datetime-local 칸을 UTC 값으로 보고
  # 열 때 브라우저 시각으로 바꿔 보여 주고, 저장할 때 다시 UTC 로 바꿔 보내므로 여기서는 UTC 로 주고받는다.
  # (한국 시각을 그대로 주면 저장할 때마다 9시간씩 앞당겨져 효과가 사라진다)
  def game_fx_input_value(entry)
    Time.zone.parse(entry['until'].to_s).utc.strftime('%Y-%m-%dT%H:%M')
  end

  # 캐릭터에 지금 붙은 칭호·데코·스킨 { 'title' => 모양, ... } (효과를 끄면 비어 있다)
  def game_fx_of(character)
    return {} unless Game::Fx.enabled?

    character.fx_entries.each_with_object({}) do |(_, entry), result|
      result[entry['slot']] = entry['preset'] if Game::Fx::SLOTS['character'].include?(entry['slot'])
    end
  end

  # 누적 수치를 상성끼리 묶는다: [[수치, 상성 수치 또는 nil], ...] (명단·상세의 '벌점/상점' 표시)
  def game_counter_groups(counters)
    seen = []
    counters.filter_map do |counter|
      next if seen.include?(counter.id)

      seen << counter.id
      seen << counter.opposite_id if counter.opposite_id
      [counter, counter.opposite]
    end
  end

  # 표 칸용: 붙은 효과 이름과 남은 시간 (slot 이 없으면 전부)
  def game_fx_badges(owner, slots = nil)
    effects = (@fx_by_id ||= GameEffect.unscoped.index_by(&:id))
    items = owner.fx_entries.filter_map do |_, entry|
      next if slots && !Array(slots).include?(entry['slot'])

      effect = effects[entry['effect_id'].to_i]
      next if effect.nil?

      content_tag(:span, safe_join([effect.name, ' ', content_tag(:small, game_fx_remaining(entry), class: 'hint')]), class: 'game-badge game-fx-badge')
    end
    items.empty? ? '—' : safe_join(items, ' ')
  end

  # 상대 시간 (n분 전). 없으면 —
  def game_ago(time)
    time ? "#{time_ago_in_words(time)} 전" : '—'
  end

  # '툿 수 / 글자 수' 를 한 칸에
  def game_pair(count, chars)
    safe_join([number_with_delimiter(count), content_tag(:span, ' / ', class: 'game-pair__sep'), number_with_delimiter(chars)])
  end

  # 눌러서 정렬하는 표 머리: 같은 칸을 다시 누르면 오름차순 ↔ 내림차순
  # param/dir_param: 한 화면에 정렬하는 표가 둘이면 서로 다른 이름을 쓴다
  def game_sort_header(label, key, column, direction, param: 'sort', dir_param: 'dir')
    active = column == key
    next_direction = active && direction == 'asc' ? 'desc' : 'asc'
    arrow = active ? (direction == 'asc' ? '▲' : '▼') : ''
    link_to url_for(request.query_parameters.merge(param => key, dir_param => next_direction)), class: ['game-sort', ('game-sort--active' if active)] do
      safe_join([label, content_tag(:span, arrow, class: 'game-sort__arrow')])
    end
  end

  def game_kind_icon(key)
    GAME_ICONS.fetch(key, '📜')
  end

  # 문구 미리보기에 넣을 견본 값 (한글 명령어 → 견본). 없는 명령어는 미리보기에서 이름표로 보인다.
  GAME_PREVIEW_PEOPLE = {
    '' => %w(해리 harry), '상대 ' => %w(드레이코 draco), '승자 ' => %w(해리 harry), '패자 ' => %w(드레이코 draco),
    '다음 차례 ' => %w(드레이코 draco), '대상 ' => %w(론 ron), 'A ' => %w(해리 harry), 'B ' => %w(드레이코 draco),
  }.freeze

  GAME_PREVIEW_VALUES = {
    '턴' => '3', '턴 수' => '10', '라운드' => '2', '라운드 수' => '5', '분' => '5', '경기 번호' => '1',
    '점수' => '5', '우승 점수' => '30', '이번 점수' => '2', '개수' => '10', '남은 개수' => '7', '최대 개수' => '3',
    '최악의 맛 수' => '1', '맛' => '딸기 맛', '먹은 젤리빈' => '해리가 젤리빈을 먹습니다. [딸기 맛]', '소속' => '그리핀도르',
    '소속 이모지' => '🦁', '과목' => '변신술', '마법약 이름' => '진실의 약', '정답' => '용의 피 → 박쥐 날개 → 월계수',
    '재료 수' => '3', '정답 수' => '1', '순서 틀림 수' => '2', '남은 시도' => '4', '시도 번호' => '2', '시도 횟수' => '6',
    'HP' => '5', '피해' => '1', '배수' => '2', '하트' => "해리 ♥♥♥♡♡
드레이코 ♥♥♡♡♡", '등급' => 'E', '등급 이름' => '기대 이상',
    '순위' => '1', '승리 수' => '3', '패배 수' => '1', '무승부 수' => '0', '스니치 확률' => '20', '점수판' => '해리 3점 · 드레이코 2점',
  }.freeze

  def game_preview_samples(game_name)
    people = GAME_PREVIEW_PEOPLE.each_with_object({}) do |(prefix, (name, acct)), samples|
      samples["#{prefix}계정명"] = name
      samples["#{prefix}계정아이디"] = "@#{acct}"
      samples["#{prefix}계정 아바타"] = '🖼'
    end
    common = Game::Config.for('common')
    people.merge(GAME_PREVIEW_VALUES).merge('컨텐츠' => game_name, '소속 이름' => common['house_term'])
  end
end
