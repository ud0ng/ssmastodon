#!/usr/bin/env bash
# 로컬 미리보기 서버 만들기 (Docker Desktop 필요). 저장소 루트가 아니라 어디서 실행해도 된다.
#
#   bash dev/preview/setup.sh          처음 한 번: 이미지 빌드 + DB + 관리자 계정 owner@preview.test
#   bash dev/preview/setup.sh rebuild  코드 고친 뒤: 이미지 다시 빌드 + DB 마이그레이션 + web/sidekiq 재시작
#   (둘 다 컨텐츠 시험용 계정 @system·luna·draco·cedric 을 만든다)
#
# 열기: http://127.0.0.1:8080  (관리자 비밀번호는 dev/preview/.owner_password)
# 화면 캡처: node dev/preview/shot.js <폴더> <너비> <높이> /경로:이름 ...
# 끄기: docker compose -f dev/preview/docker-compose.yml down   (-v 를 붙이면 DB 까지 지움)
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
cd "$HERE"
compose() { docker compose -f "$HERE/docker-compose.yml" "$@"; }

# 시트 설정 화면용 가짜 시트 (구글 대신 CSV, BOT_SHEETS_LOCAL_DIR). 고치면 sheets/ 의 CSV 가 바뀐다.
[ -d sheets ] || cp -r bot-sheets-sample sheets

build() {
  # OneDrive 폴더의 파일은 Docker 가 못 읽을 때가 있어서("invalid file request"),
  # git 이 아는 파일(고치는 중인 것 포함)만 OneDrive 밖 폴더에 복사해서 빌드한다.
  local ctx="${LOCALAPPDATA:-${TMPDIR:-/tmp}}/ssmastodon-build"
  echo "== 빌드용 복사본: $ctx =="
  rm -rf "$ctx" && mkdir -p "$ctx"
  git -C "$ROOT" ls-files -co --exclude-standard -z |
    tar -C "$ROOT" --null --ignore-failed-read -T - -cf - | tar -C "$ctx" -xf -

  echo '== 이미지 빌드 (몇 분 걸림) =='
  docker build -t ssmastodon:local "$ctx"
  docker build -f "$ctx/streaming/Dockerfile" -t ssmastodon-streaming:local "$ctx"
}

wait_web() {
  for _ in $(seq 1 60); do
    [ "$(curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:8080/about)" = 200 ] && return 0
    sleep 3
  done
  echo '웹 서버가 뜨지 않았습니다: docker compose -f dev/preview/docker-compose.yml logs web' >&2
  return 1
}

# 컨텐츠 시험용: 시스템 계정(@system)과 서버원 luna·draco·cedric, 기본 소속, 캐릭터 명단 (이미 있으면 넘어감)
seed_content() {
  compose exec -T web bin/rails runner "
    %w(system luna draco cedric).each do |name|
      next if Account.local.exists?(username: name)
      account = Account.new(username: name, display_name: name == 'system' ? '시스템' : name)
      user = User.new(email: \"#{name}@preview.test\", password: SecureRandom.hex(16), agreement: true, account: account, locale: 'ko')
      user.save!(validate: false)
      user.update_columns(approved: true, confirmed_at: Time.now.utc)
    end
    GameHouse.ensure_defaults!
    GameCharacter.sync!
  " >/dev/null 2>&1 || echo '(컨텐츠 시험 계정은 만들지 못했습니다)'
}

if [ "${1:-}" = rebuild ]; then
  build
  echo '== DB 마이그레이션 =='
  compose run --rm -T -e SAFETY_ASSURED=1 web bin/rails db:migrate
  compose up -d --force-recreate web sidekiq streaming
  wait_web && seed_content && echo '다시 띄웠습니다: http://127.0.0.1:8080'
  exit 0
fi

# http 로 띄우기 위한 설정 (저장소 파일을 복사해서 https 강제만 끈다)
mkdir -p override
sed 's/config.force_ssl = true/config.force_ssl = false/' "$ROOT/config/environments/production.rb" > override/production.rb
sed "s/https = Rails.env.production? || ENV\['LOCAL_HTTPS'\] == 'true'/https = ENV['LOCAL_HTTPS'] == 'true'/" "$ROOT/config/initializers/1_hosts.rb" > override/1_hosts.rb

build

if [ ! -f .env.production ]; then
  cat > .env.production <<EOF
LOCAL_DOMAIN=127.0.0.1:8080
RAILS_ENV=production
NODE_ENV=production
RAILS_SERVE_STATIC_FILES=true
DB_HOST=db
DB_USER=postgres
DB_NAME=mastodon_production
DB_PASS=
DB_PORT=5432
REDIS_HOST=redis
REDIS_PORT=6379
SECRET_KEY_BASE=$(openssl rand -hex 64)
OTP_SECRET=$(openssl rand -hex 64)
ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY=$(openssl rand -hex 16)
ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT=$(openssl rand -hex 16)
ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY=$(openssl rand -hex 16)
LIMITED_FEDERATION_MODE=true
AUTHORIZED_FETCH=true
DM_CHAT_ENABLED=true
SMTP_SERVER=localhost
SMTP_FROM_ADDRESS=notifications@127.0.0.1
EOF
  compose run --rm -T -e SECRET_KEY_BASE_DUMMY=1 web bundle exec rails mastodon:webpush:generate_vapid_key | grep '^VAPID_' >> .env.production
fi

echo '== DB 준비 =='
compose up -d db redis
for _ in $(seq 1 30); do
  compose exec -T db pg_isready -U postgres >/dev/null 2>&1 && break
  sleep 2
done
compose run --rm -T web bin/rails db:create db:schema:load
compose run --rm -T -e SAFETY_ASSURED=1 web bin/rails db:migrate
compose run --rm -T web bin/rails db:seed

echo '== 관리자 계정 owner@preview.test =='
# 미리보기용이라 메일 확인 없이 만든다 (preview.test 는 메일 주소 검사를 통과하지 못한다)
compose run --rm -T web bin/rails runner "
  pw = SecureRandom.hex(12)
  account = Account.new(username: 'owner')
  user = User.new(email: 'owner@preview.test', password: pw, agreement: true, account: account, role: UserRole.find_by(name: 'Owner'), confirmed_at: Time.now.utc)
  user.save!(validate: false)
  user.update_columns(approved: true)
  puts 'PW=' + pw
" 2>/dev/null | grep '^PW=' | sed 's/^PW=//' | tr -d '\r\n' > .owner_password

compose up -d
wait_web
seed_content
echo "준비됐습니다: http://127.0.0.1:8080  (owner@preview.test / 비밀번호는 dev/preview/.owner_password)"
