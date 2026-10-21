# frozen_string_literal: true

module Game
  # 웹 시스템 메뉴의 컨텐츠별 화면에 보여 줄 소개: 한 줄 소개 / 룰 / 역할과 승리 조건 / 아이템 / 진행 방법.
  # %{이름} 은 그 컨텐츠 설정(명령어 등)과 공통 설정 값으로 채운다.
  #   rules: 알아야 할 규칙 (icon · title · text) — 명령어 쓰는 법은 넣지 않는다
  #   roles: 역할마다 승리 조건과 다른 점 (역할이 하나면 name 을 비운다), items: [이름, 효과, 아이콘]
  #   steps: 신청부터 끝까지 하는 방법 (룰에 있는 설명은 되풀이하지 않는다)
  module Guide
    # 웹 컨텐츠 메뉴 묶음: 1:1 / 팀(여럿이 하는 컨텐츠: 비행 대결·미로·도둑 지도·비밀의 방)
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
          ['%{cmd_shield}', '이번 라운드에 공개되는 상대의 결과 중 하나를 가립니다. (한 판에 %{shield_count}개)', 'shield'],
          ['%{cmd_retry}', '이번 라운드에 재료를 한 번 더 조합할 수 있습니다. (한 판에 %{retry_count}개)', 'retry'],
        ],
        steps: ['[%{command}] @상대 로 신청', '라운드마다 DM 으로 [%{cmd_brew}] 재료 번호를 보냄', '아이템은 조합을 보내기 전에 [%{cmd_shield}] · [%{cmd_retry}] 로 사용'],
      },
      'flying' => {
        summary: '방해물을 피해서 가장 멀리 날아요!',
        rules: [
          { icon: 'compass', title: '경로', text: '라운드마다 참가자보다 조금 적은 경로가 주어집니다. 혼자 고른 경로는 통과, 같은 경로를 고른 사람끼리는 충돌합니다.' },
        ],
        roles: [{ win: '방해물을 피해 최후까지 남는 사람만이 승리합니다. (최대 2인)' }],
        steps: ['이벤트가 열렸을 때 참가하기', '라운드가 진행되면 경로를 선택하기', '결과를 확인하기'],
      },
      'maze' => {
        summary: '안개 속 미로에서 우승컵을 찾아라!',
        rules: [
          { icon: 'compass', title: '지도와 시야', text: '%{width}×%{height}칸 미로입니다. 내 주변 %{vision}칸만 보이고, 지나온 길은 지도에 기록됩니다. 우승컵 위치는 알 수 없습니다.' },
          { icon: 'foot', title: '이동', text: '턴마다 시야 안에서 최대 %{steps}칸을 움직일 수 있으며, 제자리 걸음도 가능합니다.' },
          { icon: 'stun', title: '함정', text: '밟으면 1턴 쉽니다. 밟아 봐야 알 수 있고, 밟은 사람의 지도에만 표시됩니다.' },
          { icon: 'foot', title: '마법 생물', text: '마주치면 주문 대결(공격 > 무장해제 > 방어 > 공격)을 합니다.',
            table: { head: ['결과', '이김', '짐', '비김'], rows: [['효과', '다음 턴 한 칸 더', '부상, 1턴 쉼', '그냥 지나감']] } },
          { icon: 'hands', title: '다른 참가자', text: '같은 칸이거나 옆 칸이면 각자 몰래 %{cmd_cooperate}/%{cmd_hinder} 중 하나를 고릅니다. 결과는 아래 표와 같고, 방해한 쪽은 상대에게 적대로 표시됩니다.',
            table: { head: ['상대 선택 ↓ / 내 선택 →', '%{cmd_cooperate}', '%{cmd_hinder}'], rows: [['%{cmd_cooperate}', '서로 지도 공유', '나만 1턴 쉼'], ['%{cmd_hinder}', '상대만 1턴 쉼', '둘 다 1턴 쉼']] } },
          { icon: 'sword', title: '적대', text: '한 번 방해한 상대는 모두에게 적대로 표시됩니다. 적대자와 다시 만나면 협력/방해 대신 주문 대결(공격 > 무장해제 > 방어 > 공격)을 합니다.',
            table: { head: ['결과', '내가 이김', '내가 짐', '비김'], rows: [['효과', '상대 지도를 얻음', '부상, 2턴 쉼', '둘 다 1턴 쉼']] } },
        ],
        roles: [{ win: '우승컵 칸에 먼저 닿으면 승리합니다.', win_notes: ['같은 턴에 2인 이상이 닿을 경우, 공동 우승합니다.', '최대 %{max_turns}턴이 지나도록 아무도 못 닿으면 무승부입니다.'] }],
        items: [
          ['%{cmd_portkey}', '우승컵이 있는 방향을 한 번 알려 줍니다.', 'compass', '%{portkey}개'],
          ['%{cmd_lumos}', '%{lumos_turns}턴 동안 시야가 %{lumos_bonus}칸 넓어집니다.', 'bulb', '%{lumos}개'],
        ],
        steps: ['이벤트가 열렸을 때 참가하기', '라운드가 진행되면 지도에서 이동할 칸을 선택하기', '결과를 확인하기'],
      },
      'marauders_map' => {
        summary: '호그와트에서 진행되는 숨바꼭질! 꼭꼭 숨어라.',
        cast: [
          { name: '%{student_name}팀', lines: ['당신은 기숙사 통금 시간에 나온 장난꾸러기 학생입니다.', '사감한테 붙잡히지 않게 목적을 달성하고 돌아가세요!'] },
          { name: '%{prefect_name}팀', lines: ['당신은 기숙사 사감 교수님을 도와 통금을 지키지 않은 학생을 잡으러 왔습니다.', '기숙사를 탈출한 학생을 붙잡으세요!'] },
        ],
        rules: [
          { icon: 'compass', title: '지도', text: '호그와트의 방들이 복도와 계단으로 이어진 지도입니다 (%{width}×%{height}). 일부 길은 막혀 있습니다.' },
          { icon: 'moon', title: '비밀 통로', text: '멀리 떨어진 두 방을 바로 잇는 통로로, %{student_name}만 쓸 수 있습니다. 판마다 후보 중 %{secret_passages}곳만 열리고, 통로를 쓴 턴에는 도착한 방에 발자국이 남습니다.' },
          { icon: 'retry', title: '움직이는 계단', text: '%{stairs_every}턴마다 일부 연결이 바뀝니다. 지도에 점선으로 그려진 길이 계단이며, 바뀌기 전에 건너야 할 수도 있습니다.' },
          { icon: 'hourglass', title: '턴 진행', text: '%{student_name} 팀이 먼저 이동을 정하고, 이어서 %{prefect_name} 팀이 동시에 정합니다. %{student_name} 팀은 한 덩어리로 움직이며, 팀원이 고른 방 중 가장 많이 고른 방(같으면 먼저 고른 방)으로 갑니다. 모두 정하면 결과가 반영되고 중요한 사건만 공개됩니다.' },
          { icon: 'foot', title: '발자국과 힌트', text: '목표 장소에 도착한 턴과 비밀 통로를 쓴 턴에는 정확한 방에 발자국이 남고, %{hint_every}턴마다 대략적인 구역만 공개됩니다.' },
          { icon: 'scope', title: '체포', text: '%{prefect_name} 중 한 명이라도 %{student_name} 팀과 같은 방에 들어가거나 길에서 엇갈리면 팀 전체가 붙잡힙니다.' },
          { icon: 'hands', title: '팀 인원', text: '%{student_name} 팀은 1명부터 %{prefect_name} 팀 인원 수까지, %{prefect_name} 팀은 1~%{max_opponents}명입니다.' },
          { icon: 'shield', title: '밸런스', text: '%{prefect_name}{이가} %{balance_prefects}명 이상이면 목표 장소가 %{targets_reduced}곳으로 줄고 투명 망토가 %{cloaks_bonus}개 늘어납니다.' },
        ],
        roles: [
          { name: '%{student_name}', win: '목표 장소 %{targets}곳을 모두 다녀오면 승리합니다.', notes: ['팀의 위치는 %{prefect_name}에게 비밀이고, %{prefect_name}들의 위치는 모두 볼 수 있습니다.', '붙어 있는 방으로 한 칸(또는 제자리), 비밀 통로로는 먼 방까지 이동합니다.', '팀 채팅([%{cmd_team}/내용])으로 %{student_name}끼리만 몰래 상의할 수 있습니다.'] },
          { name: '%{prefect_name}', win: '%{student_name}{을를} 붙잡거나, 최대 턴(%{max_turns}턴)이 지날 때까지 막으면 승리합니다.', notes: ['서로의 위치는 공개되지만 %{student_name} 위치는 모릅니다. 발자국·구역 힌트로 추리합니다.', '매 턴 한 칸만 이동합니다. 팀 채팅([%{cmd_team}/내용])으로 %{prefect_name}끼리만 몰래 상의할 수 있습니다.'] },
        ],
        items: [
          ['%{cmd_cloak}', '%{cloak_turns}턴 동안 발자국과 구역 힌트가 남지 않습니다. (%{prefect_name}{이가} %{balance_prefects}명 이상이면 %{cloaks_bonus}개 추가)', 'cloak', '%{cloaks}개'],
          ['%{cmd_revelio}', '주변 %{revelio_range}칸 안에 %{student_name}{이가} 있는지만 알려 줍니다.', 'bulb', '%{revelio}개'],
        ],
        steps: ['이벤트가 열렸을 때 참가하기', '라운드가 진행되면 이동하기', '결과를 확인하기'],
      },
      'secret_chamber' => {
        summary: '우리들 중에 비밀의 방을 연 사람이 있다! 방주를 찾아라!',
        cast: [
          { name: '%{role_traitor}', lines: ['당신은 전설로만 전해지던 비밀의 방을 열었습니다.', '들키지 않고 마음에 들지 않는 모두를 돌로 만들어버립시다!'] },
          { name: '%{role_auror}', lines: ['당신은 호그와트 석화 사건의 범인을 찾으러 왔습니다.', '학생들 중 방주를 찾아봅시다!'] },
          { name: '%{role_healer}', lines: ['당신은 학생들을 보호하기 위해 왔습니다.', '학생들이 석화되지 않도록 지켜주세요!'] },
          { name: '%{role_seer}', lines: ['당신은 방주의 정체에 대한 예언을 듣습니다.', '방주를 찾는 것에 도움을 주세요!'] },
          { name: '%{role_student}', lines: ['당신은 학생입니다.', '방주를 찾아 호그와트를 지킵시다!'] },
        ],
        rules: [
          { icon: 'hands', title: '인원과 시간', text: '%{event_min_players}~%{event_max_players}명이 참가합니다. 최대 %{total_minutes}분, %{max_phases}페이즈 안에 끝납니다. (낮 하나, 밤 하나가 각각 1페이즈)' },
          { icon: 'sun', title: '낮', text: '최대 %{day_minutes}분간 방주의 정체에 토론할 수 있습니다. 가장 많이 고발된 사람은 퇴학당하며 진영이 공개됩니다.' },
          { icon: 'moon', title: '밤', text: '최대 %{night_minutes}분간 역할이 있는 사람이 능력을 쓸 수 있습니다. 모두 정하면(또는 시간이 되면) 낮에 결과가 공개됩니다.' },
          { icon: 'sparkle', title: '예언', text: '%{role_seer}{은는} 밤마다 예언을 받습니다. 예언의 내용은 %{role_traitor}들이 상의해서 정해 전달하지만, 언제나 사실만 전할 수 있습니다.' },
          { icon: 'stun', title: '탈락', text: '석화되거나 퇴학된 사람은 진영이 공개되고 이후 관전만 합니다. 모든 역할을 볼 수 있습니다.' },
        ],
        roles: [
          { name: '%{role_traitor}', win: '%{role_traitor} 수가 남은 생존자 수 이상이 되면 승리합니다. 시간·페이즈가 다 되어도 승리합니다.', notes: ['밤마다 동료와 상의해 한 사람을 석화시킵니다. (탈락)', '사실인 예언만 골라 %{role_seer}에게 전합니다.'] },
          { name: '%{role_auror}', win: '%{role_traitor} 전원을 퇴학시키면 승리합니다.', notes: ['밤마다 한 사람을 조사해 어둠 진영인지 확인합니다. 결과는 기록 노트에 남습니다.'] },
          { name: '%{role_healer}', win: '%{role_traitor} 전원을 퇴학시키면 승리합니다.', notes: ['밤마다 한 사람을 보호해 석화를 막습니다. 같은 사람을 연속으로 보호할 수 없습니다.'] },
          { name: '%{role_seer}', win: '%{role_traitor} 전원을 퇴학시키면 승리합니다.', notes: ['직접 쓰는 능력은 없고, 밤마다 %{role_traitor}들이 전한 예언을 받습니다. 예언은 언제나 진실이며 기록 노트에 쌓입니다.', '예언을 공개할지 말지는 자유입니다.'] },
          { name: '%{role_student}', win: '%{role_traitor} 전원을 퇴학시키면 승리합니다.', notes: ['능력은 없습니다. 토론과 투표로 승부합니다.'] },
        ],
        steps: ['이벤트가 열렸을 때 참가하기', '배정된 역할을 확인하기', '낮에는 토론하고 투표하며, 밤에는 능력을 사용하기', '끝날 때까지 낮과 밤을 번갈아 진행하기'],
      },
    }.freeze

    module_function

    def group_of(kind)
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
        cast: text[:cast].to_a.map { |member| { name: fill(member[:name], values), lines: member[:lines].map { |line| fill(line, values) } } },
        rules: text[:rules].to_a.map { |rule| { icon: rule[:icon], title: rule[:title], text: fill(rule[:text], values), visual: rule[:visual], nodes: rule[:nodes].to_a.map { |node| fill(node, values) }, table: rule[:table] && { head: rule[:table][:head].map { |cell| fill(cell, values) }, rows: rule[:table][:rows].map { |row| row.map { |cell| fill(cell, values) } } } } },
        roles: text[:roles].to_a.map do |role|
          {
            name: role[:name] && fill(role[:name], values),
            win: fill(role[:win], values),
            win_notes: role[:win_notes].to_a.map { |note| fill(note, values) },
            notes: role[:notes].to_a.map { |note| fill(note, values) },
          }
        end,
        items: items.map { |name, effect, icon, count| { name: fill(name, values), effect: fill(effect, values), icon: icon, count: count && fill(count, values) } },
      }
    end

    def fill(template, values)
      Game::Text.render(template, **values.transform_keys(&:to_sym))
    end
  end
end
