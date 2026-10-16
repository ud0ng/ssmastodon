# frozen_string_literal: true

module Game
  # 웹 시스템 메뉴의 컨텐츠별 화면에 보여 줄 한 줄 소개와 하는 법.
  # %{이름} 은 그 컨텐츠 설정(명령어 등)과 공통 설정 값으로 채운다.
  module Guide
    # 웹 컨텐츠 메뉴 묶음: 1:1 / 팀(여럿이 하는 컨텐츠 + 서버 이벤트)
    GROUPS = %w(duel group).freeze

    TEXT = {
      'jellybean' => {
        summary: '젤리빈을 번갈아 먹다가 최악의 맛을 먹으면 지는 1:1 대결',
        steps: ['[%{command}] @상대 로 신청 → 상대가 [%{cmd_accept}] 하면 시작', '내 차례에 [%{cmd_eat}] (여러 개는 [%{cmd_eat}/개수])', '%{worst_flavor}{을를} 먹으면 패배'],
      },
      'gobstones' => {
        summary: '강도를 골라 상대 구슬을 맞히는 1:1 구슬 대결',
        steps: ['[%{command}] @상대 로 신청', '차례마다 [%{cmd_weak}] [%{cmd_mid}] [%{cmd_strong}] 중 하나 (셀수록 점수가 크고 빗나가기 쉬움)', '총점이 높은 쪽 승리'],
      },
      'duel' => {
        summary: '주문 셋의 상성으로 겨루는 마법 결투',
        steps: ['[%{command}] @상대 로 신청', '턴마다 DM 으로 [%{cmd_attack}] [%{cmd_disarm}] [%{cmd_defend}] 중 하나', '필살기는 한 번만: [%{cmd_attack}/%{cmd_special}]', 'HP 가 먼저 0 이 되면 패배'],
      },
      'potion' => {
        summary: '재료 순서를 추리해 마법약을 먼저 완성하는 대결',
        steps: ['[%{command}] @상대 로 신청', '라운드마다 DM 으로 [%{cmd_brew}] 재료 번호 (0번은 첫 자리 불가, 두 사람이 모두 보내면 결과 공개)', '[P] 재료·순서 맞음 · [T] 순서만 틀림. 아이템: [%{cmd_shield}] 결과 하나 가림 · [%{cmd_retry}] 두 번 조합, 정답을 먼저 맞히면 승리'],
      },
      'quidditch' => {
        summary: '1:1 또는 팀전(2·4·6명) 미니 퀴디치',
        steps: ['[%{command}] @상대 로 신청 (팀전은 @같은편 … @상대편 …)', '턴마다 DM 으로 [%{cmd_chase}] 득점 · [%{cmd_beat}] 방해 · [%{cmd_seek}] 스니치', '스니치를 잡거나 마지막 턴에 점수가 높은 팀 승리'],
      },
      'flying' => {
        summary: '겹치지 않는 경로로 날아 가장 많이 통과하는 사람이 이기는 비행 대결 (최대 %{max_people}명)',
        steps: ['[%{command}] @상대 … 로 신청', '라운드마다 DM 으로 [%{cmd_fly}/번호] 경로 고르기', '혼자 고른 경로는 통과, 겹치면 충돌 → 통과가 가장 많은 사람 승리'],
      },
      'maze' => {
        summary: '안개 속 미로에서 우승컵을 먼저 찾는 웹 전용 컨텐츠 (최대 4명)',
        steps: ['[%{command}] @상대 … 로 신청 (최대 4명)', '진행 화면에서 경로와 태도(협력/방해) 고르기', '우승컵에 먼저 닿으면 승리'],
      },
      'marauders_map' => {
        summary: '%{student_name} 한 명과 %{prefect_name}들의 숨바꼭질, 웹 전용',
        steps: ['[%{command}] @사감1 @사감2 … 로 신청 (신청자가 %{student_name})', '%{student_name}: 목표 장소 돌기 · %{prefect_name}: 같은 방에서 붙잡기', '진행 화면에서 방을 눌러 이동 (투명 망토·호메눔 레벨리오는 한 번씩)'],
      },
      'secret_chamber' => {
        summary: '서버 전체가 함께하는 마피아형 이벤트',
        steps: ['운영진이 [%{command}] 으로 열면 [%{cmd_join}] 으로 참가', '낮: [%{cmd_accuse}] @누구 로 투표 · 밤: DM 으로 역할 행동', '%{faction_light}: %{role_traitor} 모두 퇴학 / %{faction_dark}: %{role_traitor} 수가 남은 사람 이상'],
      },
    }.freeze

    module_function

    def group_of(kind)
      return 'group' if kind.event?

      kind.max_opponents > 1 ? 'group' : 'duel'
    end

    def for(kind)
      values = Game::Config.for('common').merge(kind.config).merge('name' => kind.display_name, 'max_people' => kind.max_opponents + 1)
      text = TEXT.fetch(kind.key, { summary: '', steps: [] })
      {
        # 관리 > 컨텐츠 설정의 설명을 쓰고, 비어 있으면 기본 소개
        summary: kind.config['description'].presence || fill(text[:summary], values),
        steps: text[:steps].map { |step| fill(step, values) },
      }
    end

    def fill(template, values)
      Game::Text.render(template, **values.transform_keys(&:to_sym))
    end
  end
end
