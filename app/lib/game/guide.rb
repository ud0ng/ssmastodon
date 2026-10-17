# frozen_string_literal: true

module Game
  # 웹 시스템 메뉴의 컨텐츠별 화면에 보여 줄 소개: 한 줄 소개 / 룰 / 역할과 승리 조건 / 아이템 / 진행 방법.
  # %{이름} 은 그 컨텐츠 설정(명령어 등)과 공통 설정 값으로 채운다.
  #   rules: 알아야 할 규칙 (icon · title · text) — 명령어 쓰는 법은 넣지 않는다
  #   roles: 역할마다 승리 조건과 다른 점 (역할이 하나면 name 을 비운다), items: [이름, 효과, 아이콘]
  #   steps: 신청부터 끝까지 하는 방법 (룰에 있는 설명은 되풀이하지 않는다)
  module Guide
    # 웹 컨텐츠 메뉴 묶음: 1:1 / 팀(여럿이 하는 컨텐츠 + 서버 이벤트)
    GROUPS = %w(duel group).freeze

    TEXT = {
      'jellybean' => {
        summary: '젤리빈을 번갈아 먹다가 최악의 맛을 먹으면 지는 1:1 대결',
        rules: [
          { icon: 'gift', title: '젤리빈', text: '젤리빈 %{beans}개 중에 최악의 맛(%{worst_flavor})이 섞여 있습니다. 먹기 전에는 어떤 맛인지 알 수 없습니다.' },
          { icon: 'star', title: '차례', text: '번갈아 먹습니다. 한 번에 몇 개를 먹을지는 내가 정합니다.' },
        ],
        roles: [{ win: '상대가 %{worst_flavor}{을를} 먹으면 승리, 내가 먹으면 패배합니다.' }],
        steps: ['[%{command}] @상대 로 신청 → 상대가 [%{cmd_accept}] 하면 시작', '내 차례에 [%{cmd_eat}] (여러 개는 [%{cmd_eat}/개수])', '결과가 나올 때까지 번갈아 진행'],
      },
      'gobstones' => {
        summary: '강도를 골라 상대 구슬을 맞히는 1:1 구슬 대결',
        rules: [
          { icon: 'sparkle', title: '강도', text: '약·중·강 중 하나를 고릅니다. 셀수록 점수가 크지만 빗나가기 쉽습니다.' },
        ],
        roles: [{ win: '정해진 차례가 끝났을 때 총점이 더 높은 쪽이 승리합니다. (같으면 무승부)' }],
        steps: ['[%{command}] @상대 로 신청', '차례마다 [%{cmd_weak}] [%{cmd_mid}] [%{cmd_strong}] 중 하나', '정해진 차례가 끝나면 총점으로 결정'],
      },
      'duel' => {
        summary: '주문 셋의 상성으로 겨루는 마법 결투',
        rules: [
          { icon: 'sword', title: '주문 상성', text: '화살표가 가리키는 주문을 이깁니다. 같은 주문이면 피해가 없습니다.', visual: 'triangle', nodes: ['%{cmd_attack}', '%{cmd_disarm}', '%{cmd_defend}'] },
          { icon: 'heart', title: 'HP', text: '각자 HP %{hp}로 시작하고, 이기면 상대가 피해 %{damage}를 입습니다. 두 사람이 고른 주문은 동시에 공개됩니다.' },
        ],
        roles: [{ win: '상대 HP 를 먼저 0 으로 만들면 승리합니다. 최대 %{max_turns}턴이 지나면 HP 가 더 많은 쪽이 승리합니다. (같으면 무승부)' }],
        items: [['%{cmd_special}', '한 판에 한 번. 이기면 피해 %{special_multiplier}배, 지면 내가 %{special_multiplier}배 피해를 입습니다.', 'sword']],
        steps: ['[%{command}] @상대 로 신청', '턴마다 DM 으로 [%{cmd_attack}] [%{cmd_disarm}] [%{cmd_defend}] 중 하나', '필살기는 주문 뒤에 붙여 보냅니다: [%{cmd_attack}/%{cmd_special}]'],
      },
      'potion' => {
        summary: '재료 순서를 추리해 마법약을 먼저 완성하는 대결',
        rules: [
          { icon: 'sparkle', title: '재료와 순서', text: '정해진 재료를 정해진 순서로 넣어야 합니다. 0번 재료는 첫 번째 자리에 놓을 수 없습니다.' },
          { icon: 'check', title: '결과 표시', text: '[P] 재료와 순서가 모두 맞음 · [T] 재료는 맞지만 순서가 틀림. 두 사람이 모두 조합을 보내면 결과가 함께 공개됩니다.' },
        ],
        roles: [{ win: '정답 조합을 상대보다 먼저 맞히면 승리합니다. 아무도 못 맞히고 %{max_tries}라운드가 지나면 무승부입니다.' }],
        items: [
          ['%{cmd_shield}', '이번 라운드에 공개되는 내 결과 중 하나를 상대에게 가립니다. (한 판에 %{shield_count}개)', 'shield'],
          ['%{cmd_retry}', '이번 라운드에 재료를 한 번 더 조합할 수 있습니다. (한 판에 %{retry_count}개)', 'retry'],
        ],
        steps: ['[%{command}] @상대 로 신청', '라운드마다 DM 으로 [%{cmd_brew}] 재료 번호를 보냄', '아이템은 조합을 보내기 전에 [%{cmd_shield}] · [%{cmd_retry}] 로 사용'],
      },
      'quidditch' => {
        summary: '두 팀이 겨루는 미니 퀴디치 (%{min_people}~%{max_people}명, 양 팀 인원 같게)',
        rules: [
          { icon: 'foot', title: '행동', text: '추격은 득점, 몰이는 상대 행동 하나를 막기, 수색은 골든 스니치를 노리는 행동입니다. 모두 고르면 동시에 공개됩니다.' },
          { icon: 'hands', title: '팀전', text: '신청할 때 우리 팀을 먼저, 이어서 상대 팀을 고릅니다. 양 팀 인원이 같아야 합니다.' },
        ],
        roles: [{ win: '골든 스니치를 잡으면 큰 점수와 함께 경기가 끝납니다. 마지막 턴(%{max_turns}턴)까지 점수가 더 높은 팀이 승리하고, 팀원 모두가 함께 이깁니다.' }],
        steps: ['[%{command}] 로 신청: 우리 팀(@같은편 …) 먼저, 이어서 상대 팀(@상대편 …)', '턴마다 DM 으로 [%{cmd_chase}] · [%{cmd_beat}] · [%{cmd_seek}] 중 하나', '정해진 턴이 끝나거나 스니치를 잡으면 종료'],
      },
      'flying' => {
        summary: '겹치지 않는 경로로 날아 가장 많이 통과하는 사람이 이기는 비행 대결 (%{min_people}~%{max_people}명)',
        rules: [
          { icon: 'compass', title: '경로', text: '라운드마다 참가자보다 조금 적은 경로가 주어집니다. 혼자 고른 경로는 통과, 같은 경로를 고른 사람끼리는 충돌합니다.' },
        ],
        roles: [{ win: '%{rounds}라운드가 끝났을 때 통과 횟수가 가장 많은 사람이 승리합니다. (여럿이면 함께 승리, 모두 같으면 무승부)' }],
        steps: ['[%{command}] @상대 … 로 신청', '라운드마다 DM 으로 [%{cmd_fly}/번호] 경로 고르기', '모두 고르면 결과가 공개되고 다음 라운드로'],
      },
      'maze' => {
        summary: '안개 속 미로에서 우승컵을 먼저 찾는 웹 전용 컨텐츠 (최대 4명)',
        rules: [
          { icon: 'compass', title: '지도와 시야', text: '%{width}×%{height}칸 미로입니다. 내 주변 %{vision}칸만 보이고, 지나온 길은 지도에 기록됩니다. 우승컵 위치는 알 수 없습니다.' },
          { icon: 'foot', title: '이동', text: '턴마다 시야 안에서 최대 %{steps}칸을 움직입니다. 갈 수 있는 칸이 지도에 표시되고, 누르면 DM 으로 자동 전송됩니다.' },
          { icon: 'stun', title: '함정', text: '밟으면 1턴 쉽니다. 밟아 봐야 알 수 있고, 밟은 사람의 지도에만 표시됩니다.' },
          { icon: 'foot', title: '마법 생물', text: '마주치면 주문 대결(공격 > 무장해제 > 방어 > 공격). 이기면 다음 턴 한 칸 더, 지면 부상으로 1턴 쉼, 비기면 그냥 지나갑니다.' },
          { icon: 'hands', title: '다른 참가자', text: '같은 칸이거나 옆 칸이면 각자 몰래 %{cmd_cooperate}/%{cmd_hinder} 중 하나를 고릅니다. 결과는 아래 표와 같고, 방해한 쪽은 상대에게 적대로 표시됩니다.',
            table: { head: ['상대 선택 ↓ / 내 선택 →', '%{cmd_cooperate}', '%{cmd_hinder}'], rows: [['%{cmd_cooperate}', '서로 지도 공유', '나만 1턴 쉼'], ['%{cmd_hinder}', '상대만 1턴 쉼', '둘 다 1턴 쉼']] } },
          { icon: 'sword', title: '적대', text: '한 번 방해한 상대는 모두에게 적대로 표시됩니다. 적대자와 다시 만나면 협력/방해 대신 주문 대결(공격 > 무장해제 > 방어 > 공격)을 합니다.',
            table: { head: ['결과', '내가 이김', '내가 짐', '비김'], rows: [['효과', '상대 지도를 얻음', '부상, 2턴 쉼', '둘 다 1턴 쉼']] } },
        ],
        roles: [{ win: '우승컵 칸에 먼저 닿으면 승리합니다. 같은 턴에 둘 이상 닿으면 공동 우승(점수는 나눔), 최대 %{max_turns}턴이 지나도록 아무도 못 닿으면 무승부입니다.' }],
        items: [
          ['%{cmd_portkey}', '우승컵이 있는 방향을 한 번 알려 줍니다. (시작할 때 %{portkey}개)', 'compass'],
          ['%{cmd_lumos}', '%{lumos_turns}턴 동안 시야가 %{lumos_bonus}칸 넓어집니다. (시작할 때 %{lumos}개)', 'bulb'],
        ],
        steps: ['[%{command}] @상대 … 로 신청 (최대 4명)', '턴마다 지도에서 이동할 칸을 눌러 보내기 (제자리는 [%{cmd_stay}])', '마주친 상황은 아래 버튼에서 주문 또는 협력/방해 고르기', '모두 고르면 그 턴의 일이 공개되고 다음 턴으로'],
      },
      'marauders_map' => {
        summary: '%{student_name} 한 명과 %{prefect_name}들의 숨바꼭질, 웹 전용',
        rules: [
          { icon: 'compass', title: '지도', text: '호그와트의 방들이 복도와 계단으로 이어진 지도입니다 (%{width}×%{height}). 일부 길은 막혀 있습니다.' },
          { icon: 'moon', title: '비밀 통로', text: '멀리 떨어진 두 방을 바로 잇는 통로로, %{student_name}만 쓸 수 있습니다. 판마다 후보 중 %{secret_passages}곳만 열리고, 통로를 쓴 턴에는 도착한 방에 발자국이 남습니다.' },
          { icon: 'retry', title: '움직이는 계단', text: '%{stairs_every}턴마다 일부 연결이 바뀝니다. 지도에 점선으로 그려진 길이 계단이며, 바뀌기 전에 건너야 할 수도 있습니다.' },
          { icon: 'hourglass', title: '턴 진행', text: '%{student_name}{이가} 먼저 이동을 정하고, 이어서 %{prefect_name} 팀이 동시에 정합니다. 모두 정하면 결과가 반영되고 중요한 사건만 공개됩니다.' },
          { icon: 'foot', title: '발자국과 힌트', text: '목표 장소에 도착한 턴과 비밀 통로를 쓴 턴에는 정확한 방에 발자국이 남고, %{hint_every}턴마다 대략적인 구역만 공개됩니다.' },
          { icon: 'scope', title: '체포', text: '%{prefect_name}{이가} %{student_name}{과와} 같은 방에 들어가거나 길에서 엇갈리면 붙잡힙니다.' },
          { icon: 'shield', title: '밸런스', text: '%{prefect_name}{이가} %{balance_prefects}명 이상이면 목표 장소가 %{targets_reduced}곳으로 줄고 투명 망토가 %{cloaks_bonus}개 늘어납니다.' },
        ],
        roles: [
          { name: '%{student_name}', win: '목표 장소 %{targets}곳을 모두 다녀오면 승리합니다.', notes: ['내 위치는 %{prefect_name}에게 비밀이고, %{prefect_name}들의 위치는 모두 볼 수 있습니다.', '붙어 있는 방으로 한 칸(또는 제자리), 비밀 통로로는 먼 방까지 이동합니다.'] },
          { name: '%{prefect_name}', win: '%{student_name}{을를} 붙잡거나, 최대 턴(%{max_turns}턴)이 지날 때까지 막으면 승리합니다.', notes: ['서로의 위치는 공개되지만 %{student_name} 위치는 모릅니다. 발자국·구역 힌트로 추리합니다.', '매 턴 한 칸만 이동합니다. 팀 채팅([%{cmd_team}/내용])으로 %{prefect_name}끼리만 몰래 상의할 수 있습니다.'] },
        ],
        items: [
          ['%{cmd_cloak}', '%{cloak_turns}턴 동안 발자국과 구역 힌트가 남지 않습니다. (%{cloaks}개, %{prefect_name}이 %{balance_prefects}명 이상이면 %{cloaks_bonus}개 추가)', 'cloak'],
          ['%{cmd_revelio}', '주변 %{revelio_range}칸 안에 %{student_name}{이가} 있는지만 알려 줍니다. 한 사람이 %{revelio}번.', 'bulb'],
        ],
        steps: ['[%{command}] @사감1 @사감2 … 로 신청 (신청자가 %{student_name})', '지도에서 붙어 있는 방을 눌러 이동 (DM 으로 자동 전송, 제자리는 [%{cmd_hide}])', '아이템은 이동을 정하기 전에 지도 아래 버튼으로 사용'],
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
      values = Game::Config.for('common').merge(kind.config).merge('name' => kind.display_name, 'max_people' => kind.max_opponents + 1, 'min_people' => kind.min_opponents + 1)
      text = TEXT.fetch(kind.key, { summary: '', steps: [] })
      items = text[:items] || text[:roles].to_a.flat_map { |role| role[:items].to_a }
      {
        # 관리 > 컨텐츠 설정의 설명을 쓰고, 비어 있으면 기본 소개
        summary: kind.config['description'].presence || fill(text[:summary], values),
        steps: text[:steps].map { |step| fill(step, values) },
        rules: text[:rules].to_a.map { |rule| { icon: rule[:icon], title: rule[:title], text: fill(rule[:text], values), visual: rule[:visual], nodes: rule[:nodes].to_a.map { |node| fill(node, values) }, table: rule[:table] && { head: rule[:table][:head].map { |cell| fill(cell, values) }, rows: rule[:table][:rows].map { |row| row.map { |cell| fill(cell, values) } } } } },
        roles: text[:roles].to_a.map do |role|
          {
            name: role[:name] && fill(role[:name], values),
            win: fill(role[:win], values),
            notes: role[:notes].to_a.map { |note| fill(note, values) },
          }
        end,
        items: items.map { |name, effect, icon| { name: fill(name, values), effect: fill(effect, values), icon: icon } },
      }
    end

    def fill(template, values)
      Game::Text.render(template, **values.transform_keys(&:to_sym))
    end
  end
end
