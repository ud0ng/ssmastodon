# frozen_string_literal: true

# 자동 기본 데이터: 시즌(1학년 10/19~10/28, 진행 중인 시즌이 없을 때)과 기본 아이템 16개. 이미 있는 것은 건드리지 않는다.
# (출석 5재화·글자수 100자당 1재화·컨텐츠 승/무/패 보상은 Game::Config 기본값)
class SeedGameDefaults < ActiveRecord::Migration[8.0]
  ITEMS = [
    { name: '동물 귀 머리띠', price: 30, use_target: 'character', allow_random: true, wear_label: '동물 귀', stat_minutes: 1440,
      description: '지정 1인/랜덤 1인에게 동물귀머리띠를 씌워주거나, 자신이 쓸 수 있습니다.', effect: '대상에게 동물귀를 착용시킨다. 지속 시간은 24시간이다.' },
    { name: '동물 꼬리 키링', price: 20, use_target: 'character', allow_random: true, wear_label: '동물 꼬리', stat_minutes: 1440,
      description: '지정 1인/랜덤 1인에게 동물꼬리키링을 달아주거나, 자신에게 달 수 있습니다.', effect: '대상에게 동물꼬리를 착용시킨다. 지속 시간은 24시간이다.' },
    { name: '그리핀도르 색잉크', price: 20, use_target: 'character', usable: false, description: '그리핀도르의 색을 닮은 금색 펄이 들어간 붉은 색 잉크입니다.', effect: 'RP용 아이템' },
    { name: '후플푸프 색잉크', price: 20, use_target: 'character', usable: false, description: '후플푸프의 색을 닮은 흑색 펄이 들어간 금색 잉크입니다.', effect: 'RP용 아이템' },
    { name: '래번클로 색잉크', price: 20, use_target: 'character', usable: false, description: '래번클로의 색을 닮은 청동색 펄이 들어간 푸른 색 잉크입니다.', effect: 'RP용 아이템' },
    { name: '슬리데린 색잉크', price: 20, use_target: 'character', usable: false, description: '슬리데린의 색을 닮은 은색 펄이 들어간 녹색 잉크입니다.', effect: 'RP용 아이템' },
    { name: '꽃 한 송이', price: 10, use_target: 'character', usable: false, description: '정성스럽게 포장된 꽃 한 송이입니다. 오히려 한 송이만 담긴 게 더 아름다울 때가 있어요.', effect: 'RP용 아이템' },
    { name: '꽃다발', price: 30, use_target: 'character', usable: false, description: '축하의 의미를 담아서 꽃을 모아, 정성스럽게 포장된 꽃다발입니다. 꽃봉오리의 수만큼 큰 마음을 담았어요.', effect: 'RP용 아이템' },
    { name: '우정 악세사리', price: 100, use_target: 'character', usable: false, description: '친해지고 싶은 상대에게 마음 대신 선물해볼까요? 선물을 받은 상대는 오랫동안 간직하게 될 지도 몰라요.',
      effect: '러닝 중 악세 선물 가능 (선물 줄 상대 1인당 1개씩 구매해야 함)' },
    { name: '일회용 반장뱃지', price: 50, use_target: 'character', description: '[RP 중 사용 가능 아이템] RP 중 비난을 막을 수 있습니다. 해당 아이템을 사용 시 반장 뱃지를 본 교수님이 와서 사용한 타래에서 일어난 말다툼을 강제로 중지합니다.',
      effect: '사용 시 이후 턴에서 말다툼이 와해된 상황으로 넘기시오.' },
    { name: '가짜 허가서', price: 50, use_target: 'character', description: '[RP 중 사용 가능 아이템] RP 중 싸움이 벌어졌을 시 사용이 가능합니다. 사용 시 해당 싸움에서 1회 승리할 수 있게 해줍니다.',
      effect: '어떤 싸움이든 1회 승리합니다. 중첩이 가능합니다.' },
    { name: '불량 리벨리오 주문서', price: 50, use_target: 'character', description: '[RP 중 사용 가능 아이템] 가짜 허가서가 사용된 상황을 무효화할 수 있습니다. 1개당 1개의 허가서만 무효화할 수 있습니다.',
      effect: '가짜 허가서의 효과를 1회 무효화합니다.' },
    { name: '정식 리벨리오 주문서', price: 150, use_target: 'character', description: '[RP 중 사용 가능 아이템] RP 중 싸움이 벌어졌을 때 사용 가능합니다. 가짜 허가서를 완전 무효할 수 있는 정식 리벨리오 주문서입니다! [조건] 상대가 허가서를 사용하기 전 먼저 사용해야 합니다.',
      effect: '해당 싸움에서 사용된 허가서 사용을 완전 무효화합니다.' },
    { name: '교내 신고권', price: 30, use_target: 'special', special_kind: 'report', score_delta: -5, special_limit: 5,
      description: '더 이상 참을 수 없어! 다른 학생을 신고할 수 있습니다. 신고 받은 횟수는 누적됩니다. 일정 횟수 이상 누적 시 봉사활동을 하게 됩니다.',
      effect: '상대 러너 기숙사 점수 차감 (-5), 누적 5회 시 교수님께서 봉사활동을 시킵니다.' },
    { name: '똥폭탄', price: 20, use_target: 'special', special_kind: 'bomb', score_delta: -10,
      description: '지정 기숙사 한 곳에 똥폭탄을 투척합니다. 지나가던 사감 선생님께서 보시면 기숙사 점수를 깎으실 겁니다.', effect: '기숙사 점수 차감 (-10)' },
    { name: '호울러', price: 20, use_target: 'special', special_kind: 'howler', score_delta: -10,
      description: '편지봉투를 열면 호그와트 전체에 소문이 울려 퍼집니다. 이를 무시하고 열지 않는다면 그대로 폭발해버릴 지도 모르니 조심해요.',
      effect: "러닝 중 소문 내기 가능 (무시하면 기숙사 점수가 차감(-10)). 조율 없이 소문 낼 정도의 개그성만 허용\n사용하면 내용 입력창이 뜨고(모바일은 시스템 계정에 DM 으로 [사용/호울러/내용]), 입력한 내용이 모든 인원에게 DM 소문으로 발송됩니다. 보낸 사람은 알 수 없습니다." },
  ].freeze

  def up
    return if Rails.env.test? # 시험 DB 에는 넣지 않는다 (시험이 직접 만든다)

    shop = GameShop.first || GameShop.create!(name: '상점', description: '', position: 0)
    ITEMS.each_with_index do |attributes, index|
      next if GameShopItem.exists?(name: attributes[:name])

      shop.items.create!(attributes.merge(position: shop.items.count + index))
    end

    # 이미 1학년이 있거나 진행 중인 시즌이 있으면 건드리지 않는다 (진행 중인 시즌은 하나만 가능)
    return if GameSeason.exists?(name: '1학년') || GameSeason.all.any?(&:running?)

    GameSeason.create!(name: '1학년', starts_on: Date.new(2026, 10, 19), ends_on: Date.new(2026, 10, 28))
  end

  def down; end
end
