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

## 다음에 할 일

1. 사용자 피드백 대기.
2. 확인 못 한 것: 3명 이상 컨텐츠(퀴디치 팀전·비행 대결)의 방 상단(`room-head--many`), 휴대폰 폭 방 화면, 아주 긴 판(비밀의방·도둑 지도)의 고정 영역(`max-height: 45%`).
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
