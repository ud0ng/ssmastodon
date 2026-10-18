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
