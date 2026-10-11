# ssmastodon 작업 안내 (Claude Code 용)

마스토돈 4.4.26 포크(원본 long-while/longwhile-mastodon, 연합 끔)를 커뮤니티용으로 고친 서버.
GCP VM 한 대에서 약 40명이 2026-10 부터 두 달쯤 쓰고 닫을 예정. 사용자와는 한국어로 이야기한다.

## 지켜 온 결정

- 원 작성자(한참/longwhile) 출처 표기는 모두 지웠고 기본 마스토돈 문구를 쓴다. 내부 식별자는 `commu`.
- 공지 계정 아이디는 `manager` (관리자이기도 함). 서버는 공개/조용한 공개 툿을 막고 manager 만 조용한 공개 가능.
- 서버 설정 화면은 탭 3개: **서버 정보**(branding+about) / **운영**(registrations+글자수·검색+발견하기+보존기한)
  / **디자인**(community_theme+로고+외관). 예전 탭 주소는 합쳐진 탭으로 redirect.
- UI 를 고치면 사용자에게 화면으로 보여 주고(미리보기 캡처), 확인되면 커밋·푸시한다.

## 커뮤니티 테마 (디자인 탭) 구조

- 사이트 테마 목록의 `community-light`(낮) / `community-dark`(밤). 켜짐 여부·기본값·꺼졌을 때 대체는 `app/lib/themes.rb`.
  꺼지면 유사 트위터(밝음/어두움)로 보인다. Bird UI 밝은 변수 선택자에 `body.theme-community-light` 도 넣어 둠.
- 색 계산: `app/lib/community_theme.rb` — 메인/서브색 두 개로 세부 색(바깥 배경·박스·글쓰기·고른 항목·호버·테두리·
  글자·메뉴·메뉴 호버·흐린 글자·링크 호버·[대괄호]·(소괄호)·게시 버튼 등)을 자동으로 만들고, 정한 세부 색이 있으면 그걸 쓴다.
  같은 계산이 관리 화면 실시간 미리보기용으로 `app/javascript/mastodon/admin/community_theme_editor.ts` 에도 있다 (둘 다 고칠 것).
- `ThemeHelper#community_theme_tags` 가 `--community-theme-<항목>-<light|dark>` 를 `:root` 에 넣고,
  `app/javascript/styles/entrypoints/community_theme.scss` 가 그걸 Bird UI 변수에 연결한다 (`body.community-theme:not(.admin)`).
- 기본 스타일에 박힌 파란색(#1d9bf0 계열)은 `config/vite/postcss-community-theme.ts` 가 community-*.scss 빌드 때
  `var(--ct-point, #1d9bf0)` 로 바꾼다. 새 파란색이 보이면 대부분 이걸로 잡히고, 아이콘 SVG data URL 안 색은 못 바꾼다.
- 툿의 `[...]`·`(...)` 꾸미기: `app/javascript/mastodon/utils/dialogue.ts` (StatusContent 에서 호출).
- 기본 프로필 사진·헤더: SiteUpload `default_avatar`/`default_header`, Paperclip default_url → `app/lib/default_account_image.rb`.
- 관리자·설정 사이드바 로고: `BrandingHelper#render_themed_wordmark` (라이트 테마=낮 로고 `wordmark_light`, 다크=밤 로고).

## 로컬에서 확인하기

Docker Desktop, Node.js, Chrome 이 있으면 된다 (PC 에 Ruby/Python 없음).

```bash
bash dev/preview/setup.sh            # 처음 한 번 (이미지 빌드·DB·관리자 owner@preview.test)
bash dev/preview/setup.sh rebuild    # 코드 고친 뒤 다시 빌드·재시작
node dev/preview/shot.js dev/preview/shots 1280 900 /home:home /admin/settings/community_theme:design
```

- http://127.0.0.1:8080, 관리자 비밀번호는 `dev/preview/.owner_password` (git 에 안 올라감). 사용자 대신 로그인할 때는 이 미리보기 계정만.
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
  ruby:3.4.4-slim sh -c "apt-get update -qq && apt-get install -y -qq libpq-dev libicu-dev libidn-dev libyaml-dev git >/dev/null; bundle install -q; bin/rails db:create db:migrate >/dev/null; bundle exec rspec spec/lib/community_theme_spec.rb"
git checkout db/schema.rb Gemfile.lock   # 테스트가 바꿔 놓으니 되돌린다
```

- `db/schema.rb` 에 DM 마이그레이션 13개가 빠져 있어서 테스트 DB 도 `db:migrate` 가 필요하다.
- 화면을 그리는 spec(system, request 일부)은 Vite 빌드가 없어 컨테이너에서 실패한다. 미리보기 서버로 확인한다.
- 원래부터 실패하는 spec: `spec/requests/admin/settings/{about,branding}_spec.rb` 의 잘못된 파라미터 처리, theme_helper 의 wordmark 이스케이프.

## 서버 (GCP VM, https://antagonism.site)

```bash
cd ~/mastodon && git pull && docker compose build && docker compose run --rm web bundle exec rails db:migrate && docker compose up -d
```

- 마이그레이션이 없으면 `db:migrate` 는 빼도 된다. 서버 반영은 사용자가 직접 한다 (명령만 알려 준다).
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
