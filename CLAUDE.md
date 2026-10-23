# ssmastodon 작업 안내 (Claude Code 용)

마스토돈 4.4.26 포크(원본 long-while/longwhile-mastodon, 연합 끔)를 커뮤니티용으로 고친 서버.
GCP VM 한 대에서 약 40명이 2026-10 부터 두 달쯤 쓰고 닫을 예정. 사용자와는 한국어로 이야기한다.

## 지켜 온 결정

- 원 작성자(한참/longwhile) 출처 표기는 모두 지웠고 기본 마스토돈 문구를 쓴다. 내부 식별자는 `commu`.
- 공지 계정 아이디는 `manager` (관리자이기도 함). 서버는 공개/조용한 공개 툿을 막고 manager 만 조용한 공개 가능.
- 서버 설정 화면은 탭 3개: **서버 정보**(branding+about) / **운영**(registrations+글자수·검색+발견하기+보존기한)
  / **디자인**(community_theme+로고+외관). 예전 탭 주소는 합쳐진 탭으로 redirect.
- UI 를 고치면 사용자에게 화면으로 보여 주고(미리보기 캡처), 확인되면 커밋·푸시한다.
- 관리 화면은 공통 컴포넌트(`app/views/admin/ui/`, `ui-*` 클래스)만으로 만든다. 규칙: `docs/관리화면-컴포넌트.md` (입력칸·날짜·모달·고르기·여러 개 고르기·아이템 고르기).

## 커뮤니티 테마 (디자인 탭) 구조

- 사이트 테마 목록의 `community-light`(낮) / `community-dark`(밤). 켜짐 여부·기본값·꺼졌을 때 대체는 `app/lib/themes.rb`.
  꺼지면 유사 트위터(밝음/어두움)로 보인다. Bird UI 밝은 변수 선택자에 `body.theme-community-light` 도 넣어 둠.
- 색 계산: `app/lib/community_theme.rb` — 메인/서브색 두 개로 세부 색(바깥 배경·박스·글쓰기·고른 항목·호버·테두리·
  글자·메뉴·메뉴 호버·흐린 글자·링크 호버·[대괄호]·(소괄호)·게시 버튼 등)을 자동으로 만들고, 정한 세부 색이 있으면 그걸 쓴다.
  같은 계산이 관리 화면 실시간 미리보기용으로 `app/javascript/mastodon/admin/community_theme_editor.ts` 에도 있다 (둘 다 고칠 것).
- `ThemeHelper#community_theme_tags` 가 `--community-theme-<항목>-<light|dark>` 를 `:root` 에 넣고,
  `app/javascript/styles/entrypoints/community_theme.scss` 가 그걸 Bird UI 변수에 연결한다 (`body.community-theme:not(.admin)`).
  관리자·환경설정 화면(`body.community-theme.admin`)은 같은 파일 아래쪽에서 따로 칠하고(배경·메뉴·입력칸 등),
  드롭다운 목록은 `app/javascript/mastodon/admin/community_select.ts` 가 검색창 드롭다운 모양으로 띄운다.
- 기본 스타일에 박힌 파란색(#1d9bf0 계열)은 `config/vite/postcss-community-theme.ts` 가 community-*.scss 빌드 때
  `var(--ct-point, #1d9bf0)` 로 바꾼다. 새 파란색이 보이면 대부분 이걸로 잡히고, 아이콘 SVG data URL 안 색은 못 바꾼다.
- 툿의 `[...]`·`(...)` 꾸미기: `app/javascript/mastodon/utils/dialogue.ts` (StatusContent 에서 호출).
- 기본 프로필 사진·헤더: SiteUpload `default_avatar`/`default_header`, Paperclip default_url → `app/lib/default_account_image.rb`.
- 관리자·설정 사이드바 로고: `BrandingHelper#render_themed_wordmark` (라이트 테마=낮 로고 `wordmark_light`, 다크=밤 로고).

## 시트 설정 (관리 > 시스템 > 시트 설정, /admin/sheets)

- 자동봇 구글 시트 4개(기본·예약 툿·스토리·조사)를 탭으로 보여 주고, 기본 시트의 '설정' 워크시트(항목|값|설명)는 폼으로 고쳐 시트에 바로 쓴다.
  나머지 워크시트는 아직 읽기 전용 표 (다음 단계: 표 칸 수정, 나중에 서버원용 인벤토리 창).
- 시트 ID 는 서버 설정 `bot_sheet_<main|reservation|story|investigation>_id` (연결 탭, 주소째 넣어도 됨).
- `app/lib/bot_sheets.rb`: 구글 시트 API 를 GCP VM 서비스 계정(메타데이터 서버 토큰)으로 부른다 — 자동봇과 같은 계정.
  저장할 때 처음 본 값과 지금 시트 값을 비교해 그사이 바뀌었으면 저장하지 않는다. 수식 칸은 읽기 전용.
- 미리보기는 `BOT_SHEETS_LOCAL_DIR` 로 구글 대신 `dev/preview/sheets/<시트>/<워크시트>.csv` (`bot-sheets-sample` 을 복사, 자동봇 tests/fixtures 와 같음).

> 다음 작업 계획: `docs/컨텐츠-다음-계획.md` (PC 웹 컨텐츠 카드 UI + 관리 화면 UI 개선 → 비밀의방 → 웹 전용 → 정기 툿)

## 컨텐츠(게임) — 시스템 계정 @system 이 진행 (관리 > 시스템 > 컨텐츠 설정 /admin/games, 캐릭터 관리 /admin/characters)

- **화면·툿에 보이는 이름은 '컨텐츠', 진행 계정은 '시스템'** ('게임'이라고 쓰지 않는다). 코드 이름은 Game 그대로.
- 해리포터 세계관 게임. 기획: 2인 대결(젤리빈·곱스톤·마법결투·물약), 여럿이(비행 대결·미로·도둑 지도·비밀의 방, 모두 웹 전용).
  1:1 네 가지·비행 대결·비밀의방·미로·도둑 지도·주간 결산까지 됨 (퀴디치는 2026-10-21 에 없앴다, docs/컨텐츠-다음-계획.md). 게임 데이터는 마스토돈 DB (구글 시트 아님), 엔진은 서버 안 (Python 자동봇 아님).
- 흐름: PostStatusService#enqueue_game_command! → `Game::MentionWorker` → `Game::Engine` (첫 [명령어]).
  모르는 명령어는 조용히 넘긴다 (자동봇 ssbot 과 겹치지 않게). 시간 제한은 `Game::TimeoutWorker` (deadline_token 으로 묵은 작업 무시).
- 시스템 답장은 방금 명령어를 보낸 툿에 단다 (한 스레드로 이어지게). 공개 범위는 신청 툿 (팔로워 공개 / DM). 앱에서도 멘션 알림만으로 알 수 있게 툿 텍스트로 진행.
- 문구는 한글 명령어 (`Game::Text`): {계정명} {계정아이디} {계정 아바타}(사진 첨부, `Game::Poster`), 앞에 상대·승자·패자 등, {이가} 조사. 예전 %{player} 도 됨. 문구에 이름 대신 GamePlayer/Account 를 넘긴다.
- 모든 규칙·명령어·시간·문구는 `Game::Config` (항목 정의 + game_configs 에 바뀐 값만). 새 게임: `app/lib/game/kinds/<게임>.rb` (Base 상속, KEY·FIELDS·start!·handle·timeout!) + `Game::Kinds.registry`.
- 소속 점수: `Game::Points`. 점수 방식(공통 `scoring_mode`) 점수제 = 컨텐츠마다 승리·무승부·패배 점수 / 판수제 = 이긴 판마다 1점.
  시즌(`GameSeason`, 캐릭터 관리 > 소속): 중간 결산·시즌 종료 툿(`Game::Summary`). 소속 점수(`GameHouse#total`)는 마지막으로 끝난 시즌 뒤의 점수만 센다.
- 캐릭터는 `GameCharacter` (회원 목록에서 자동 생성·탈퇴 시 삭제·정지 시 숨김, `GameRoster`).
- 일일 활동 스냅샷 (`Game::ActivitySnapshot`, 테이블 `game_activity_days`·`game_activity_pairs`): 하루(한국 시간 00시 기준)마다 캐릭터의 전체·DM·퍼블·답 툿 수/글자 수, 답 횟수, 미디어 툿 수와 상대 캐릭터와의 수(답·DM)를 저장. 오늘 것은 툿이 저장될 때마다 쌓고(`Game::ActivitySnapshotWorker`), 매일 00:05(KST) `Scheduler::GameActivitySnapshotScheduler` 가 어제 것을 툿에서 다시 계산해 맞추고 빠진 날을 채운다. 답 횟수(reply_turns)는 상대의 첫 툿(남에게 단 답이 아닌 툿, 자기 툿에 이어 쓴 것 포함)에 단 첫 답을 같은 대화에서 한 번만 센다(며칠에 걸쳐도 1, 시스템·상점봇 제외). 스루(skipped)는 상대가 나만 태그한 툿 뒤로 내가 그 대화에 아무 툿도 안 쓴 것(연달아 쓴 툿은 첫 툿 하나, 한 대화에 많아야 1)이라 스루 합 - 답 횟수 합 = 아무도 답하지 않은 첫 툿 수. 두 캐릭터 사이를 대화마다 풀어 보려면 `bin/rails "game:activity_explain[아이디A,아이디B]"`. 상대 캐릭터별 탭은 `Game::Fairness`(자기 평균 대비 관심·정성·응답·종합 지수와 순위). 활동 화면의 일자별·소속별·상대 캐릭터별 표는 머리 칸을 눌러 정렬한다(표마다 sort/psort/dsort 따로). 과거 일괄 올리기는 `bin/rails game:activity_backfill` 또는 활동 화면의 [과거 기록 올리기]. 재화 화면·소속 점수 화면의 툿 합계와 캐릭터 관리 > 활동(전체·소속별·캐릭터별, 캐릭터 상세에 일자별·상대 캐릭터별)이 이 데이터를 쓰고 활동 기록은 검색만 한다.
- 캐릭터 관리 탭: 명단(상세: 소속·스탯·메모·전적) / 활동(퍼블·답 툿 수와 글자 수, 재화 내역, 인벤토리, 지급) / 소속(점수 기준 소속, 시즌, 목록) / 스탯(`GameCharacterField` stat·status 수식).
- 툿 보상(컨텐츠 설정 > 설정 > 재화 설정): 툿이 저장될 때 `Status` after_create_commit → `Game::ActivityWorker` → `Game::Activity.reward!` (웹·앱 모두). 자동봇의 툿 보상은 끔 (/api/v1/bot/config 가 0).
- 컨텐츠 설정 탭: 설정(봇 계정·재화·공통룰) / 명령어(기본 명령어·일반 문구) — 둘 다 공통 설정, `Game::Config::LAYOUT` 의 [common, 화면] / 컨텐츠 / 상점. 마법 수업·자습·성적표는 2026-10 에 없앴다 (비행 수업만 `Kinds::Flying` 비행 대결로, game_grades 테이블은 남김).
- 누적 수치(`GameCounter`, 상점 설정 > 누적 수치 목록): 기본 벌점↔상점(최대 5, 서로 상쇄). 캐릭터 `counters` 는 누적치(최대치를 넘어도 올라감), 결과값 = 누적치 - 상성 누적치. 누적 효과(`GameCounterRule`)는 횟수/최대치(영구), 기록은 `GameCounterLog`.
- 효과(`GameEffect`, 상점 설정 > 효과 목록): 소속 카드 / 캐릭터 칭호·데코·스킨(툿·멘션 알림 배경). 모양은 `Game::Fx::PRESETS` + `_game_fx.scss`, 웹은 `components/game_fx.tsx`. 붙은 효과는 캐릭터 상세·소속 화면에서 고치고 지운다.
- 소속: `GameHouse.category` house/faction. 공통 설정 `group_mode` 로 점수를 모을 쪽을 고른다 (`GameHouse.active`, `GameCharacter#group`). {소속 이름}(house_term)은 그 이름.
- 컨텐츠 보상: `Game::Rewards` (돈·아이템, game_rewards). 시스템 툿은 판 잠금 트랜잭션 안에서 올라가므로 `Game::Poster` 가 커밋 뒤 DistributionWorker 를 다시 넣는다 (안 그러면 멘션 알림이 빠짐).
- 웹 전용 컨텐츠(미로·도둑 지도·비밀의 방, `Game::Web::*`): 운영진이 이벤트로 연다(웹 [이벤트 열기] 모달·관리 화면: 모집 / 고르기 / 테스트 플레이). 모집·참가 수락 DM 만 툿(앱에도 보임), 시작한 뒤의 진행·결과·비밀 안내는 툿 없이 `GameMessage`(웹 전용 채널, `GameSession#web_channel?`) 로만 가고, 행동은 웹에서 `v1/system/commands` 로 보내면 `Game::WebCommand` 가 툿 없이 처리한다. 테스트 플레이는 목록에 안 보이고(운영진은 자물쇠로 관전) 점수·보상·전적에 안 들어간다 (`GameSession.real`). 서버 이벤트라는 구분은 없앴다.
- 이벤트 설정 (관리 > 시스템 > 이벤트 설정): 탭 설정 / 문구 / 목록 / 이벤트 내역. 공통 값은 `Game::Events::Settings`(설정 키 'events': 해금·열 수 있는 사람과 유형·모집 시간·동시 진행 제한·하루 제한·하루 보상 횟수·참가 명령어·공통 문구),
  이벤트별 인원은 각 컨텐츠 설정, 점수·보상은 설정 탭의 표. 이벤트 알림은 툿 대신 웹 알림 배지·소리(`Game::EventNotice.alert!` → 스트리밍 `game.alert`): 모집은 모두에게, 초대는 초대받은 사람에게.
  툿: 운영진이 연 모집의 팔로워 공개 모집 툿 하나뿐 (문구도 이것만 설정). 시작·종료·참가 확인·정원 초과·하루 제한·인원 부족 취소는 멘션 없이 웹으로 안내(참가 막힘은 모달, 인원 부족 취소는 방에 있던 사람에게 모달 → 확인하면 이벤트 메인). 캐릭터가 연 모집과 초대(초대하기·테스트 플레이)는 툿·DM 없음. 초대한 대기방에는 운영진·연 사람이 캐릭터를 더 초대할 수 있다 (`invite_more`).
- 비행 대결 규칙: 내구도(기본 2, 충돌·미선택 -1, 0이면 추락), 매 라운드 금빛 고리 경로(혼자 통과하면 +1, 처음 값까지), 전원 추락이면 라운드 무효, 생존자 2명 이하면 종료(남은 사람은 내구도 순 공동 순위, 나머지는 추락 라운드 역순).
- 도둑 지도 (2026-10-22 개편, `Game::Web::MaraudersMap` + `MaraudersLayout`): 3~24명, 학생 팀≈1/3(대기실에서 무작위·[팀 변경], 정원 차면 비활성), 인원별 지도(방 25~60·층·탑·움직이는 계단·비밀 통로), 모두 동시에 고르고 결과 반영(비행과 동일). 사감 역할 감시자/정찰자/추격자, 투명 망토(팀 공용), 체포→필치의 사무실→구출(1번까지, 두 번째 체포는 탈락). 화면 `features/system/marauders_stage.tsx` (양피지·잉크·발자국·말풍선·채팅 전체/팀·리플레이), 손글씨 폰트 `app/javascript/fonts/marauders`. 팀 채팅은 GameMessage payload team. 밸런스는 컨텐츠 설정의 목표 장소 ±·구역 공개 주기·망토 개수.
- PC 웹 카드: 시스템 툿마다 `GameEvent`(payload = `Game::Card.build`) → `REST::StatusSerializer#game_card` → `components/content_card.tsx`. 새 컨텐츠는 Kinds 에 `card_data`·`card_actions` 를 만든다 (공개된 것만, 정답·비밀 선택은 끝난 뒤).
- 미리보기에서 시험: `bin/rails runner /dev/stdin "owner|@system @luna [젤리빈]" "luna|@system [수락]|reply" < dev/preview/play.rb` (sidekiq 이 처리, `|dm` 은 DM). Engine 을 직접 부르면 sidekiq 과 두 번 처리된다.
- 컨텐츠 전체 점검: `docker compose -f dev/preview/docker-compose.yml exec -T web bin/rails runner /dev/stdin < dev/preview/smoke.rb` (진짜 툿으로 컨텐츠마다 신청→끝 또는 첫 턴, 결과·보상·알림 확인, 설정은 끝나면 되돌림).

- 마니또 (관리 > RP > 마니또 설정 /admin/rp/manito, `Game::Manito`, 테이블 `game_manito_words`·`game_manito_logs`): 운영진이 캐릭터(A)마다 상대(B)에게 몰래 말할 단어를 정한다. A가 B를 태그한 툿에 단어가 있으면 툿 하나에 1회(`Game::ManitoWorker`, DM 은 설정), 하루 최대 보상 횟수 안이면 보상(소속 점수·재화·아이템)을 주고 상점봇이 A에게만 DM. B가 상점봇에게 [마니또/단어/캐릭터] → 자동봇 ssbot 이 `POST /api/v1/bot/manito/guess` 로 묻고 서버가 판정: 맞으면 A가 B에게서 받은 보상을 B가 가져가고(남은 만큼) A는 B에게서만 더 못 받는다, 틀리면 벌금·하루 추측 횟수 제한. 설정은 Game::Config 'manito' (컨텐츠 설정과 같은 편집기), 명단에서 들킴을 풀 수 있다.

## 이벤트·컨텐츠 서버 부하 줄이기 (2026-10-22, 20명 동시 접속에서 502 났던 일)

본서버(GCE e2-standard-2, 2코어)에서 비행 대결 20명이 방에 들어오자 웹이 502 를 냈다. 원인은 방 정보 요청(`GET /api/v1/system/sessions/:id`) 하나가 1.2~2.4초(DB 1초 이상)씩 걸리는데 20명이 2~3초마다 보내서 puma(프로세스 2×스레드 5=동시 10개)가 밀린 것. 아래 규칙으로 요청당 비용을 10배 이상 줄였다 (11명 기준 방 정보 30~55ms, /view 40~57ms, 웹 CPU 145%→10~30%). **새 이벤트·컨텐츠 화면을 만들 때 지킬 것:**

- **자주 읽는(폴링) 요청은 가볍게**: 대기방·게임방은 2.5초마다 읽는다. 요청 하나에서 툿·카드·사람별 조회를 하지 않는다. 이벤트 방은 `SessionsController#show` 가 `event_stage?` 면 툿·GameEvent 조회를 건너뛰고(`lean`) 채팅·안내 메시지만 준다.
- **방 전체가 같이 쓰는 값은 한 번만 계산해 잠깐 저장**: `lean_messages` 는 `Rails.cache` 에 [방, 마지막 메시지 번호, 상태] 키로 2초 저장하고 `race_condition_ttl` 로 만료 순간 여러 요청이 동시에 다시 만들지 않게 한다. 사람마다 달라지는 것(내 글·비밀 안내·팀 채팅 가림)만 요청마다 거른다. 끝난 판의 `/view` 는 사람별로 60초 저장.
- **N+1 금지**: 참가자 목록은 계정·캐릭터·소속을 한 번에 읽는다 (`Lobby.preload_characters`, `GamePlayer#preload_character`). 20명이면 사람마다 조회하는 코드가 수십 번 쿼리가 된다. 새 목록을 만들 때 `includes` 와 `index_by` 를 쓴다.
- **게임 화면(/view)**: 24명 도둑 지도는 화면 하나에 쿼리 77개였다. 컨트롤러 `build_view` 가 참가자 계정·캐릭터를 미리 읽어(`Lobby.preload_characters`) 요청 전체 41개로 줄였다. 새 컨텐츠 화면도 사람 목록을 만들기 전에 이걸 부른다.
- **설정 읽기**: `Game::Config.for` 는 저장된 값을 프로세스에서 2초 기억한다 (저장하면 바로 비움, 다른 웹 프로세스에는 최대 2초 늦게 반영, 시험 환경은 기억 안 함). 한 요청이 설정을 수십 번 읽어도 DB 는 한 번.
- **무거운 합계는 저장**: 툿 전체를 세는 `Game::Activity.overview`(재화 화면의 툿 합계 5분, 소속 점수 화면 합계 2분)처럼 테이블 전체를 훑는 값은 요청마다 계산하지 않는다. 재화 화면은 자주 읽힌다.
- **읽는 간격**: 방 정보·게임 화면 2.5초 (`session.tsx` LOBBY_REFRESH_MS, `flying.tsx`·`marauders_stage.tsx` REFRESH_MS). 줄이지 말 것. 즉시 반영이 필요한 건 스트리밍 알림(`game.alert`)을 쓴다.
- **확인 방법**: 미리보기에서 `ActionDispatch::Integration::Session` 으로 요청해 쿼리 수·시간을 센다(예: 방 정보 76→31 쿼리). 본서버는 `docker compose logs --tail=60 web | grep "sessions/"` 의 duration/db 와 `docker stats --no-stream` 의 웹 CPU 로 본다. 기준: 방 정보·/view 요청 200ms 아래, 20명에서 웹 CPU 100% 아래.
- **서버 쪽 여유**: 본서버는 e2-standard-4(4코어, 16GB) + `.env.production` 의 `WEB_CONCURRENCY=4` 로 쓰는 중. 코어 수와 프로세스 수는 같이 바꾼다 (코어 2개에 프로세스 4개는 오히려 느림). 사양을 내리면 `WEB_CONCURRENCY` 도 내린다.

## 로컬에서 확인하기

Docker Desktop, Node.js, Chrome 이 있으면 된다 (PC 에 Ruby/Python 없음).

```bash
bash dev/preview/setup.sh            # 처음 한 번 (이미지 빌드·DB·관리자 owner@preview.test)
bash dev/preview/setup.sh rebuild    # 코드 고친 뒤 다시 빌드·재시작
node dev/preview/shot.js dev/preview/shots 1280 900 /home:home /admin/settings/community_theme:design
```

- http://127.0.0.1:8080, 관리자 비밀번호는 `dev/preview/.owner_password` (git 에 안 올라감). 사용자 대신 로그인할 때는 이 미리보기 계정만.
- 저장소가 OneDrive 안이면 docker build 가 실패해서 setup.sh 가 `%LOCALAPPDATA%/ssmastodon-build` 에 복사해서 빌드한다.
- `PROBE=파일.js node dev/preview/shot.js ...` 로 페이지에서 JS 를 실행해 계산된 색 등을 찍어 볼 수 있다.
- 미리보기 계정을 더 만들 땐 `rails runner` 로 `user.save!(validate: false)` + `update_columns(approved: true)` (preview.test 는 메일 검사에 걸림).
- redis 를 FLUSHALL 하면 홈 타임라인도 비니 프로필 페이지(/@아이디)로 확인.

Ruby 테스트는 컨테이너로 (sstest-db/sstest-redis/sstest-gems 가 없으면 만든다):

```bash
docker network create sstest
docker run -d --name sstest-db --network sstest -e POSTGRES_HOST_AUTH_METHOD=trust postgres:14-alpine
docker run -d --name sstest-redis --network sstest redis:7-alpine
MSYS_NO_PATHCONV=1 docker run --rm --network sstest -v "$PWD:/app" -v sstest-gems:/usr/local/bundle -w /app \
  -e RAILS_ENV=test -e DB_HOST=sstest-db -e DB_USER=postgres -e REDIS_HOST=sstest-redis -e BUNDLE_WITHOUT=development -e DISABLE_SIMPLECOV=true \
  ruby:3.4.4-slim sh -c "apt-get update -qq && apt-get install -y -qq libpq-dev libicu-dev libidn-dev libyaml-dev git build-essential zlib1g-dev >/dev/null; bundle install --quiet; bin/rails db:create db:migrate >/dev/null; bundle exec rspec spec/lib/community_theme_spec.rb"
git checkout db/schema.rb Gemfile.lock   # 테스트가 바꿔 놓으니 되돌린다
```

- `db/schema.rb` 에 DM 마이그레이션 13개가 빠져 있어서 테스트 DB 도 `db:migrate` 가 필요하다.
- 화면을 그리는 spec(system, request 일부)은 Vite 빌드가 없어 컨테이너에서 실패한다. 미리보기 서버로 확인한다.
- 원래부터 실패하는 spec: `spec/requests/admin/settings/{about,branding}_spec.rb` 의 잘못된 파라미터 처리, theme_helper 의 wordmark 이스케이프.

## 서버 (GCP VM, https://antagonism.site)

```bash
cd ~/mastodon && git pull && docker compose build && docker compose up -d
```

- 마이그레이션은 web 컨테이너가 시작할 때 자동으로 돈다 (docker-compose.yml 의 web command). 서버 반영은 사용자가 직접 한다 (명령만 알려 준다).
- docker compose (build: .) + 호스트 Caddy 로 HTTPS. 새로 설치할 땐 `bin/docker-setup` (업로드 폴더 991 권한 포함).
- 토큰·SMTP 키·.env 내용은 채팅에 붙여 달라고 하지 않는다.

## git

- 커밋 전 `git fetch` 로 원격이 앞서 있는지 확인 (여러 PC 에서 작업).
- remote 는 `https://ud0ng@github.com/ud0ng/ssmastodon.git`, 푸시는 `GIT_TERMINAL_PROMPT=0 timeout 60 git push`.
- Windows 에서 커밋하면 실행 권한이 빠질 수 있다: `bin/*`, `dev/preview/setup.sh` 는 `git update-index --chmod=+x`.

## 자동봇

별도 저장소 `ud0ng/ssbot` (공개, Python). 구글 시트로 명령어·상점·조사·예약 툿·스토리 운영. VM 에 systemd `ssbot` 으로 돈다.

## 남은 일

- 디자인 세부 조정 (사용자가 예시 이미지와 비교하며 요청)
- 두 달 뒤 종료: 공지 → 사용자 아카이브 내려받기 안내 → 마지막 DB·미디어 백업 → GCP 프로젝트 삭제 → 결제 해지 → 도메인 자동 갱신 끄기
