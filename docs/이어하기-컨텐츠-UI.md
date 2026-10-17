# 이어하기: 컨텐츠(게임) 웹 UI 작업 (2026-10-17)

다른 계정·다른 PC의 Claude Code 에서 이어 작업할 때 먼저 읽을 문서.
기본 규칙과 구조는 저장소 루트 `CLAUDE.md` 에 있다. 사용자와는 **한국어**로 이야기한다.

## 지켜야 할 것

- UI를 고치면 PC 미리보기에 반영해서 사용자에게 보여 주고, 확인받은 뒤 커밋·푸시한다. 사용자가 "커밋푸시해줘"라고 하면 바로 한다.
- 커밋 전에 `git fetch` 로 원격이 앞서 있는지 확인한다 (여러 PC에서 작업함).
  - 푸시: `GIT_TERMINAL_PROMPT=0 timeout 60 git push`
- 서버 반영은 사용자가 직접 한다. 명령만 알려 준다:
  `cd ~/mastodon && git pull && docker compose build && docker compose up -d`
  (마이그레이션은 web 컨테이너 시작 때 자동)
- 토큰·SMTP·.env 내용은 달라고 하지 않는다. 로그인은 사용자가 한다.
  - 대신 로그인해도 되는 계정은 미리보기 계정 `owner@preview.test` 하나뿐이다. 비밀번호는 `dev/preview/.owner_password`.
- 관리 화면은 `app/views/admin/ui/` 공통 컴포넌트만 쓴다 (`docs/관리화면-컴포넌트.md`).
- 화면·툿 문구는 '컨텐츠'·'시스템'이라고 쓴다 ('게임'이라고 쓰지 않는다).
- `\n` 이 들어가는 코드는 Edit 도구로 고친다 (node 템플릿 리터럴로 쓰면 줄바꿈이 깨진다).
- 마이그레이션 타임스탬프는 현재 UTC 이하로 한다.

## 지금 상태

### 커밋·푸시됨 (`20aa720`)

- 마법 수업·자습·성적표 삭제.
  - `Game::Lessons` 를 지웠다.
  - 남아 있던 수업 판은 마이그레이션 `20261016165000_cancel_lesson_sessions` 로 취소한다.
  - 예전 판 기록은 남는다: `GameSession.current_kinds` 로 거르고, `kind_class` 는 없으면 nil 이다.
- 비행 수업을 여럿이 하는 컨텐츠 **비행 대결**로 옮겼다 (`app/lib/game/kinds/flying.rb`, 2~6명).
  - 라운드마다 DM `[비행/번호]` 로 경로를 고른다. 혼자 고르면 통과, 겹치면 충돌.
- 컨텐츠 세부 화면 (`features/system/game.tsx`):
  - 소개, 룰, 순위(5명).
  - [시작하기] → 상대 고르기 모달 (`challenge_modal.tsx`, 모달 이름 `CHALLENGE`).
  - 방 목록: 진행 중 / 완료 탭, 내 방이 아니면 관전.
- 컨텐츠 방 (`features/system/session.tsx`): DM 채팅처럼 보인다.
  - API `GET /api/v1/system/sessions/:id` 의 `messages` 는 판 스레드 + 내 DM 스레드의 비밀 메시지다.
- 전적 화면 (`record.tsx`): 재화 화면과 같은 짜임 (카드 → 전체/승리/패배/무승부 탭 → 날짜별 기록).
  - API `GET /api/v1/system/history?filter=win|lose|draw`
- 재화·전적·기숙사 점수 카드를 글쓰기 패널 재화 줄과 같은 양피지 칸 카드로 맞췄다.
- 웹에서만 컨텐츠 툿을 숨긴다. 앱에서는 기록용으로 그대로 보인다.
  - 홈·타임라인: `utils/game_status.ts`, `actions/timelines.js`
  - 알림: `exclude_game` 파라미터 → `Notification.without_game`, 스트리밍(`actions/streaming.js`)도 막는다.
  - 채팅: `DmRoomsController#game_room_ids`
  - 대신 컨텐츠 메뉴에 받은 신청 수를 배지로 띄운다 (`wallet.invites`, `navigation_panel.jsx` 의 `ContentsLink`).
  - `initial_state` 에 `system_acct` 를 넣었다.

### 그다음 커밋 (이 문서와 같은 커밋)

- 카운트다운(`components/countdown.tsx`, 1분 안 남으면 빨강), 진행 중인 컨텐츠 카드 줄(`features/system/index.tsx`), 신청하면 바로 그 방으로(`board.waitForSession`), 하는 법 문구 짧게(`app/lib/game/guide.rb`).
- 컨텐츠 세부 화면(`game.tsx`): 탭 **룰 / 진행중 / 완료** ("방 목록" 제목 없음).
  - 룰 탭 = 하는 법(한 줄씩, [명령어]는 `CommandText badge` → `.command-badge`) + 보상 3칸 + 최다 승리(한 줄씩).
- 동시 진행 막기(`one_game_per_person`)가 켜져 있고 다른 컨텐츠를 하는 중이면 [시작하기]가 신청하지 않고 바로 안내(`.system-busy`).
  - API `GET /api/v1/system/games/:key` 의 `busy` { message, session_id, name }. 문구는 공통 설정 `msg_busy_web` (명령어 탭 '이미 진행 중 (웹 시작하기)').
- 컨텐츠 방(`session.tsx`)은 DM 채팅과 같은 짜임: body 클래스 `layout-game-room` 으로 화면 높이를 고정.
  - 위 상태(`.game-room__status`)·아래 입력창(`.game-room__dock`) 고정, 가운데 `.game-room` 만 스크롤.
  - 입력창은 DM `Composer` 를 그대로 쓴다 (`placeholder` prop 추가). 보내기 버튼이 낮/밤 테마를 따른다.
  - 내 차례(`myActions(card)` 가 비어 있지 않음)면 `.game-room__dock--turn` 강조 + 입력칸 포커스, 입력창 위 `TurnPanel` 에 남은 시간·할 일 버튼. 아니면 "○○ 차례예요".
  - 방 고정 카드(`variant='room'`)는 버튼을 그리지 않고 LIVE 표시도 없다. 카드 안 배지 테두리는 테마색.
- 세부 화면·모달·방은 금색·양피지 변수(`--sys-gold` 등)를 커뮤니티 테마 변수(`--ct-point`, `--ct-line`, `--ct-panel-raised`)로 바꿔 끼워 테마 색을 따른다.

검증: 미리보기 캡처로 룰 탭·동시 진행 안내·방(상대 차례/내 차례)을 확인. 로컬에 node_modules 가 없어 tsc·eslint 는 못 돌렸다 (미리보기 빌드는 통과).

### 그다음 커밋: 방 화면 DM 디자인, 명령어 배지, 방 카드

- 방 메시지(`session.tsx` `RoomLog`)는 DM 채팅 마크업 그대로: `dm-room__scroll` 스크롤, `DateDivider`, 참가자는 `dm-message`(같은 사람 연속이면 묶음).
  - 시스템 메시지만 전체 너비 박스(`.game-room__host`). 입력창 위 안내(`.game-room__turn`)는 가운데 정렬.
- `CommandText` 는 항상 배지(`.command-badge`, 대괄호 뗌). 색은 디자인 탭 [대괄호] 색(`--ct-bracket`), 내 말풍선 안에서는 글자색. 일반 툿의 [괄호](`utils/dialogue.ts`)는 그대로.
- 진행중/완료 탭은 방 카드(`.system-room-card`): 아바타 VS 아바타, 승리자 금빛 테두리·👑·승리 배지, 패배자 흐리게, 무승부 배지.
  - API `games/:key` 의 players 에 `avatar` 추가 (`RoutingHelper` include).

### 그다음 커밋: 젤리빈 방 다듬기, 컨텐츠 툿 숨김, 이모티콘 → Tabler 아이콘

- **이모티콘 금지**: 컨텐츠 화면은 아이콘만 쓴다 (`components/game_icons.tsx` `GameIcon`, Tabler outline MIT 를 `images/tabler/` 에 골라 둠). 서버 문구 안 이모티콘은 `stripEmoji` 가 화면에서만 지운다. 예외: 젤리빈 최악의 맛 칸의 💩 (사용자 요청).
- 컨텐츠 툿은 웹에서 **모든** 타임라인(프로필 포함)·알림에서 숨긴다 (`utils/game_status.ts`). 시스템에게 한 답글도 (`initial_state.system_account_id`, `in_reply_to_account_id`). 툿에 붙던 컨텐츠 카드 디자인(`ContentCard`)은 삭제. 한 페이지가 통째로 숨겨지면 `expandTimeline` 이 다음 페이지를 이어 읽는다.
- 관리자 전체 채팅(`Api::V1::Admin::DmRoomsController`)·운영자 DM 관리(`Admin::DirectMessagesController`)에서도 시스템 계정 DM 을 뺀다.
- 세부 화면: 진행중/완료 카드 — 보더 없이 옅은 박스색, 내 방은 테마색 바탕(내 방/관전 표시 삭제), 이긴 사람 이름은 테마색.
- 방 메시지: [명령어]만 보낸 말은 보낸 사람에 따라 DM 말풍선 색 배지, 시스템 메시지는 보더 없는 옅은 바탕 + 문구 속 캐릭터 이름은 아바타|굵은 이름(`CommandText people`), (대사)는 커뮤니티 테마 (소괄호) 모양.
- 방 입력: 버튼을 누르면 입력칸 앞에 [명령어] 배지가 붙고(`Composer prefix`) 대사를 덧붙여 보낸다. `commands#create` 는 `text` 를 받아 그대로 올린다 (명령어 없는 말은 시스템이 답하지 않고, 다음 명령어에서 이어진다).
- **젤리빈 방** 상단: 박스·구분선 없음, 아바타 | 소속 배지(문장만) | 이름 | 결과, 둘째 줄 상태·점수(끝난 판은 작은 보상 배지), VS 아래 "n라운드"(끝난 판은 "n라운드 종료"). 게임판은 한 가지 색 동그라미, 먹은 칸은 옅게 + 먹은 사람 아바타, 최악의 맛은 아바타 + 💩, 호버하면 먹은 사람·맛(`data-tip`). 서버는 `eaten_log`(seat·worst·flavor) 를 카드 data 로 준다. 끝난 카드의 보상에는 `account_id`·`item_list`(아이템 그림)이 들어간다.
- 다른 컨텐츠 방(곱스톤·마법결투 등)은 하나씩 같은 식으로 다듬을 예정 (사용자가 게임별로 요청).

### 그다음 커밋: 컨텐츠 해금, 곱스톤 방 상단, 대표 아이콘 삭제

- **컨텐츠 대표 아이콘은 쓰지 않는다** (허브 카드·시작하기 모달·전적·카드 머리줄 모두 삭제). `GameIcon` 은 상태·보상·행동 표시용만. 캐릭터가 입력한 말의 이모티콘은 그대로 두고, 서버가 쓴 문구(시스템 메시지·룰)만 `CommandText noEmoji` 로 지운다.
- **컨텐츠 해금**: 공통 설정 `contents_open` (컨텐츠 설정 > 설정 > 공통룰). 꺼지면 서버원 화면에서 컨텐츠 메뉴가 사라지고 `/system/(games|sessions)` 와 `/system` 은 홈으로, 컨텐츠 API 는 403 (`Api::GameGate`, `before_action :require_contents_open!` 을 `require_user!` 다음에 건다).
  - 상점 해금(`shop_open`)도 같은 방식. **운영진은 항상 다 보인다**: `Game::Staff.web?(user)` = `manage_settings` 권한. `initial_state` 의 `shop_enabled`·`contents_enabled` 가 운영진이면 true.
  - 개별 컨텐츠 '켜기' 가 꺼진 카드는 서버원에게 숨기고, 운영진에게만 흐리게 '꺼짐 (운영진만 보임)' 표시 (`catalog[].enabled`, `.system-tile--off`).
  - 아직 안 막은 것: 해금이 꺼져도 툿으로 `[곱스톤]` 을 보내면 엔진은 처리한다.
- 곱스톤 방 상단: 방 게임판 공통으로 구분선 없음, 던진 횟수 문구·마지막 던진 기록 삭제, 캐릭터 아래에 점수만 (`RoomScore`, 'n점'). 진행 막대는 남겼다.

### 그다음 커밋: 커밋 알림(내 차례 소리), 해리포터 스타일 삭제, 메뉴 별 아이콘

- **컨텐츠 알림**: `GET /api/v1/system/wallet` 이 `todo`(내가 행동해야 하는 판: 수락 대기·내 차례, `Game::Card.actions_for` 에 내 자리 버튼이 있는 판)를 준다. `invites` 는 todo 개수.
  - 스트리밍으로 시스템 계정이 나를 부르는 알림이 오면 `actions/game_alerts.ts` `notifyGameTurn` 이 todo 를 다시 읽어, **새로 생긴 판**이면 소리(`meta.sound`)와 데스크톱 알림을 낸다. 알림 설정과 상관없이 항상 (데스크톱 알림은 브라우저 권한이 있을 때만).
  - 지금 그 방(`/system/sessions/:id`)에 있으면 알리지 않고 메뉴 배지에서도 뺀다 (DM 채팅과 같은 '바로 읽음'). 이미 알린 판은 `features/system/game_todo.ts` 에 기억하고, 할 일에서 빠지면 지워 다음 차례에 다시 알린다. 처음 읽을 때 있던 할 일은 기준(알림 없음).
  - 시스템과의 DM(비밀 선택)은 DM 채팅 소리·목록에서 빼고 이 알림이 처리한다 (`streaming.js` conversation/notification 순서).
- 시스템 화면의 양피지·금색·명조 스타일을 **커뮤니티 낮/밤 테마**로 바꿨다: `--sys-gold/-soft/-parchment/-serif` 변수를 테마 값(`--ct-point` 등)의 별명으로 재정의, `%system-parchment`·컨텐츠 카드·소속 방패·지도 색 포함. 글쓰기 패널 재화 줄·소속 점수 줄도 같은 테마.
- 메뉴 '컨텐츠' 별 아이콘: id 를 `star` 로 두면 Bird UI `.icon-star` 마스크 규칙이 겹쳐 깨져서 `contents` 로 바꾸고 `layout-single-column.scss` 에 상점(`icon-shop`)과 같은 방식의 규칙을 추가.
- 인벤토리 개수 배지 둥글게.
- 미리보기 테스트 계정: `dev/preview/.test_accounts.txt` (luna·draco·cedric·neville·ron·goyle, git 에 안 올라감), 운영진은 `.owner_password`.

### 그다음 커밋: 마법결투·마법약 방, 공통 방 상단

- **공통**: 카드에 `max_turns`(`Kinds::Base#max_turns`, 결투·마법약·곱스톤·비행·퀴디치가 값을 준다) → 방 맨 위 '1라운드 / 10라운드'. 시스템 DM(비밀 안내)은 `.game-room__host--secret` 다른 바탕. 내 캐릭터는 항상 오른쪽(`RoomHead`가 정렬). 버튼은 `action.row` 로 줄을 나눈다(`Game::Card.action(row:)`), 줄 사이 여백.
- **마법결투**: 방 상단 HP는 Tabler 하트(남은 것 채움 `heart-fill`, 잃은 것 선 `heart`), 방 맨 위 보드(고른 주문·최대 턴)는 없다. 필살기 버튼은 `row: 2`. 피해 문구는 💔 마커(`CommandText noEmoji` 가 ❤·🖤·💔 만 하트 아이콘으로 바꾼다).
- **마법약** (이름·명령어 '물약' → '마법약'): `Kinds::Potion` 전면 개편.
  - 재료는 **0번부터** 10개, 0번은 첫 자리 불가. 각자 DM `[조합] 번호…`(웹은 `조합`(DM) 버튼 → 입력창 배지 → 번호 입력). 두 사람이 모두 내면 공개 스레드에 라운드 결과 — `[P ×n]` 완벽(초록)·`[T ×n]` 조금 노력(주황) 배지(`CommandText` 가 P/T 로 시작하는 배지를 색칠).
  - 아이템(`shield_count`·`retry_count`, 한 판 사람마다 같은 개수): `[방어권]` 이번 라운드 **내** 공개 결과 숫자 하나를 `?` 로 가림, `[재시도권]` 이번 라운드에 두 번 조합. 둘 다 조합하기 전에 라운드마다 한 번.
  - 방 상단: '재료 N개' 배지 + 아이템 소지 아이콘 `0/1`. 이번 라운드 시도 결과는 카드에 싣지 않는다(먼저 낸 사람 결과 노출 방지).
  - `Game::Text::LEGACY_LABELS`: 이름을 바꾼 한글 토큰(`{물약 이름}`·`{시도 횟수}`)을 저장해 둔 문구도 계속 읽힌다. 단 DB 에 저장된 옛 문구는 새 안내(버튼·아이템)가 안 들어가니 관리 화면에서 문구를 초기화해야 한다.
- 모든 Tabler 아이콘의 맨 앞 24×24 배경 `path` 는 숨긴다(`.game-icon path[d='M0 0h24v24H0z']`). 안 그러면 선 아이콘에 네모 테두리가 그려진다.

### 그다음 커밋: 신청 취소·항복, 기본 문구 정리

- **신청 취소**: 새 시스템 명령 `[신청취소]`(`cmd_cancel`, 공통 설정·도움말·`msg_cancelled`). 수락 대기 중 신청한 사람이 보낼 수 있고 카드 버튼(`Game::Card.meta_actions`)으로도 뜬다 (방 입력창 위 맨 아래 줄).
- **항복**: 기존 `[기권]`(`cmd_forfeit`)을 방 헤더 오른쪽 끝(`ColumnHeader extraButton`, `.game-room__forfeit`)의 버튼으로. 1:1·팀전에서 내 차례일 때만(`Kinds::Base#forfeit_winners`, 퀴디치 팀전은 상대 팀 승리). 3명 이상 각자 겨루는 판·서버 이벤트는 버튼 없음.
  - 두 버튼은 카드 action 의 `meta: true`. 내 차례 알림(`wallets#todo_sessions`)·메뉴 배지·'내 차례예요' 강조에는 세지 않는다.
- **기본 문구 정리**: 공통(신청·수락 시간 초과·점수·보상·선물·시즌·토너먼트)·젤리빈·곱스톤·마법결투·퀴디치·비행 대결을 '친절하지만 시스템적인' 존댓말 톤으로. 화면(상단 점수·하트·차례)이 보여 주는 줄(점수판·다음 차례·HP 하트·통과 횟수)과 이모티콘은 뺐다. 결투 HP 표시 설정(`heart`·`heart_lost`)과 비행 `msg_board` 삭제. 피해 문구의 💔 만 남겨 웹에서 깨진 하트 아이콘으로 바꾼다.
  - DB 에 저장해 둔 문구는 기본값보다 우선하니 서버에서 새 문구가 안 보이면 컨텐츠 설정에서 초기화.
- 컨텐츠 설정 문구 칸의 명령어 배지에서 `{계정아이디}`·`{계정 아바타}` 를 뺐다 (`Game::Text.tokens_for`). 저장된 문구에서는 계속 동작.
- Ruby 스펙은 컨테이너로 실제 실행했다 (`spec/lib/game`, 관리 화면 설정, `spec/requests/api/v1/system` 119개 통과). 위 `로컬에서 확인하기` 의 명령 앞에 `bin/rails db:create db:migrate` 가 필요하다.

### 그다음 커밋: 문구 초기화 버튼, 승리 아이템 검색 고르기, 퀴디치·비행 방

- **문구 초기화**: 컨텐츠 설정 각 묶음 소제목 오른쪽 `이 묶음 기본값으로`(바뀐 칸이 있을 때만 보임, `game_config_editor.ts` `.game-group__reset`). 누르면 그 묶음에서 기본값과 다른 칸이 기본값으로 채워지고 저장 줄에 '저장하지 않은 변경'이 뜬다 (되돌리기 가능). 칸마다 '기본값으로' 는 원래 있었다.
- **저장 버그 수정**: 폼으로 오는 줄바꿈(`\r\n`)을 `Game::Config.coerce` 가 `\n` 으로 맞추지 않아, 기본값과 같은 문구도 '바뀐 값'으로 저장돼 코드의 기본 문구를 고쳐도 반영되지 않았다. 이제 같으면 저장하지 않는다 (스펙 추가). 서버에 이미 저장된 문구는 위 `이 묶음 기본값으로` 로 되돌린 뒤 저장해야 새 문구가 보인다.
- **컨텐츠 승리 아이템**: 드롭다운 표 대신 `admin/ui/_item_picker` 카드(개수·확률)로. `chance: true` 면 카드에 확률칸. 목록 맨 위에 **검색칸**(상점 지급 모달에도 같이 생김), 고르면 카드가 붙는다. 값은 숨은 글(줄마다 `아이템|개수|확률`)로 보낸다 (`game_config_editor.ts` `setupRewardPickers`, 공통 동작은 `admin/item_picker.ts`). 목록 글자색이 흰색으로 덮이던 것도 고침.
- **퀴디치·비행 대결 방**: 방 맨 위 보드(고른 주문·스니치 확률·최대 턴·경로 목록·고른 경로·'n/m 선택') 삭제 → 캐릭터·점수·'n라운드 / 최대'만. 동시에 고르는 컨텐츠(결투·퀴디치·비행)는 상태 배지 '선택 중/선택 완료', 이미 고른 사람은 버튼·'내 차례'가 사라진다 (`Kinds::Base#pending_seats`). 퀴디치 팀전은 이름 옆 팀 배지. 퀴디치 `max_turns` 가 중복 정의(뒤쪽 private)라 안 나오던 것도 고침.
- 문서의 '`로컬에서 확인하기`' Docker Desktop 이 꺼져 있으면 `dev/preview/setup.sh rebuild` 전에 먼저 켠다.

### 그다음 커밋: 퀴디치·비행 대결 방 그래픽 게임판

- **퀴디치**(`QuidditchBoard`): 점수 대결 막대(왼쪽 팀 색 ↔ 오른쪽 팀 색, 점수 비율) + 턴 트랙(지난 턴은 득점한 쪽 색·양쪽이면 반반·무득점은 옅게, 지금 턴은 고리). 서버가 `history`(턴별 팀 득점)와 `sides`(자리별 팀 키, 1:1 도 A/B)를 카드 data 로 준다.
- **비행 대결**(`FlyingBoard`): 사람마다 한 줄 레인(아바타 + 라운드 칸), 통과(체크)·충돌(엑스)·미선택(빼기), 지금 라운드는 고리. 서버가 라운드마다 `history`(자리별 pass/crash/idle)를 쌓는다 (고른 경로는 담지 않는다).
- 두 방 모두 글자 줄(고른 주문·경로 목록·n/m 선택)은 없고, 왼쪽/오른쪽 순서는 상단 캐릭터와 같다 (내 캐릭터가 오른쪽, `orderPlayers`).
- 마법약 스펙: 0 으로 시작하는 조합은 거부되므로 테스트가 가끔 실패하던 것을 0 으로 시작하지 않는 순서로 고침.

## 다음에 할 일

1. 사용자 피드백 대기.
2. 확인 못 한 것: 곱스톤·비행·퀴디치 방의 'n / 최대' 표시, 밤 테마에서의 시스템 화면, 전적 화면, 비밀 선택 DM 알림(실제 컨텐츠로), 서버원(비운영진) 계정으로 본 해금 off 화면, 관리 화면의 '컨텐츠 해금' 항목, 미로·도둑 지도 화면의 아이콘 위치, 프로필·홈에서 그냥 대사 숨김(마지막 빌드), tsc·eslint(node_modules 없음), 3명 이상 컨텐츠(퀴디치 팀전·비행 대결)의 방 상단(`room-head--many`), 휴대폰 폭 방 화면, 아주 긴 판(비밀의방·도둑 지도)의 고정 영역(`max-height: 45%`).
3. 상대 고르기 모달에서 **상대**가 이미 진행 중일 때는 아직 웹에서 바로 알려 주지 않는다 (시스템 툿 `msg_busy` 로만).

## 미리보기·테스트

```bash
bash dev/preview/setup.sh rebuild
docker compose -f dev/preview/docker-compose.yml up -d proxy   # rebuild 뒤 proxy 가 꺼져 있으면
node dev/preview/shot.js dev/preview/shots 1280 900 /system:hub /system/games/gobstones:gob
# 판 만들기 (sidekiq 이 처리):
docker compose -f dev/preview/docker-compose.yml exec -T web bin/rails runner /dev/stdin "luna|@system @owner [곱스톤]" "owner|@system [수락]|reply" < dev/preview/play.rb
# 컨텐츠 전체 점검:
docker compose -f dev/preview/docker-compose.yml exec -T web bin/rails runner /dev/stdin < dev/preview/smoke.rb
```

- 캡처 전에 JS 실행: `SETUP=파일.js` (예: 버튼 클릭).
- 값 찍어 보기: `PROBE=파일.js` (식 하나를 반환하는 IIFE).
- owner 가 이미 진행 중인 판이 있으면 새 신청이 막힌다. 그때는 `GameSession.open.update_all(status: "cancelled")` 를 runner 로 실행한다.
- Ruby 테스트 컨테이너 명령은 `CLAUDE.md` "로컬에서 확인하기" 참고. 돌린 뒤 `git checkout db/schema.rb Gemfile.lock`.

## 팀전 인원 설정 + 팀 먼저 고르는 신청 (퀴디치·비행)

- 퀴디치·비행 대결 설정(규칙)에 `min_players`/`max_players`(신청자 포함 전체 인원) 추가. 퀴디치는 팀전이라 짝수, 최소 4명(1:1 불가), 최대 12명. 비행은 개인전 2~10명. 조건이 안 맞으면 `Kinds::*.invite_error` 가 문구(`msg_uneven`/`msg_players`)로 거절.
- `Kinds::Base` 에 `min_opponents`, `team_game?` 훅. `GET /system/games/:key` 가 `min_opponents`, `team` 도 내려준다.
- 신청 모달(`challenge_modal.tsx`): 팀전이면 1단계 "우리 팀 고르기"(팀원) → 2단계 "상대 팀 고르기"(팀원 수+1명). `opponents[]` 는 고른 순서(팀원 → 상대 팀)로 보내고, `commands_controller#new_command` 가 그 순서를 지킨다. 서버는 앞쪽 절반(신청자 포함)을 신청 팀으로 나눈다.

## 트라이위저드 미로 개편 (웹 전용, DM 방식)

- `app/lib/game/web/maze.rb` 를 마법 결투처럼 **시스템에게 DM 으로 고르는** 방식으로 다시 씀. 지도에서 칸을 누르면 `POST /api/v1/system/commands` (command=이동, args=동/남…, dm=true) 가 자동으로 나간다 (`features/system/maze.tsx`).
- 설정: 지도 가로·세로(기본 15x15, 7~31), 시야·이동 칸·함정·마법 생물 수, 포트키·루모스 소지 개수(시작 시 지급)·루모스 시야 증가·지속, 명령어(이동/대기/포트키/루모스/협력/방해/공격/무장해제/방어) 모두 컨텐츠 설정에서.
- 턴 단계 `state['phase']`: move(이동) → fight(마법 생물과 주문 대결) → meet(같은 칸·옆 칸 참가자: 협력/방해, 적대자는 주문 대결) → 턴 결과 공개. 단계마다 DM 으로 안내하고 모두 고르면(또는 시간이 되면) 진행.
- 함정은 밟으면 1턴 쉼(밟은 사람만 지도에 기록), 생물 승리=다음 턴 한 칸 더·패배=부상 1턴 쉼·무승부=지나감, 방해한 상대는 `hostile` 쌍으로 공개(카드 칩), 적대자 대결 승리=상대 지도 획득·패배=2턴 쉼·무승부=둘 다 1턴 쉼. 같은 쌍은 3턴 동안 다시 만나지 않는다.
- 우승컵에 닿으면 만남 없이 승패 확인, 같은 턴 여럿이면 공동 우승이고 `Base#finish!(split_points: true)` 로 승리 점수를 나눈다.
- 웹 전용 방(미로·도둑 지도): `layout-game-split` 로 메뉴·작성 패널을 숨기고 지도 | 메시지 2분할 (`session.tsx useRoomLayout`), 방 안에서는 '웹에서 진행하기' 버튼과 로그 중복을 뺐다.

## 도둑 지도 개편 + 컨텐츠 소개·승리 방법 + 아이템 설명

- `Game::Web::MaraudersMap` 도 DM 방식: 학생이 먼저 [이동/방 이름]·[숨기]·[투명망토] → 사감 팀 동시 [이동/…]·[숨기]·[레벨리오] → 결과 공개. 지도에서 방을 누르면 DM 이 자동 전송 (`marauders_map.tsx`).
- 설정: 지도 가로×세로(방, 기본 5×5=25. 요청의 '15×15'는 방 25개 그래프와 어긋나 방 격자 크기로 해석), 목표 장소 수, 사감 N명 이상이면 목표 장소 감소·투명 망토 추가(밸런스), 레벨리오 범위, 열린 비밀 통로 수(후보 중 일부만), 계단 주기. 막힌 길·움직이는 계단·비밀 통로는 판마다 `build_map!` 이 만든다 (두 계단 상태 모두 모든 방이 이어짐).
- 목표 장소는 학생만 안다 (카드·시작 툿에는 방문 수만). 투명 망토 중에는 발자국·구역 힌트·목표 방문 공개가 없다. 레벨리오는 주변 N칸 안에 학생이 있는지만 공개.
- 아이템 설명: `Game::Card.action(hint:)` → 버튼 title (물약 방어권·재시도권, 미로·도둑 지도 아이템 버튼은 `item_info`).
- 컨텐츠 화면 룰 탭: `Game::Guide::TEXT` 에 `about`(컨텐츠 소개)·`win`(승리 방법)을 두고 '컨텐츠 소개 / 승리 방법 / 진행 방법' 순서로 보여 준다. 새 컨텐츠를 만들면 이 둘도 적을 것.
