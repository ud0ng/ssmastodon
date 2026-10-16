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

## 다음에 할 일

1. 사용자 피드백 대기.
2. 확인 못 한 것: 서버원(비운영진) 계정으로 본 해금 off 화면, 관리 화면의 '컨텐츠 해금' 항목, 미로·도둑 지도 화면의 아이콘 위치, 프로필·홈에서 그냥 대사 숨김(마지막 빌드), tsc·eslint(node_modules 없음), 3명 이상 컨텐츠(퀴디치 팀전·비행 대결)의 방 상단(`room-head--many`), 휴대폰 폭 방 화면, 아주 긴 판(비밀의방·도둑 지도)의 고정 영역(`max-height: 45%`).
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
