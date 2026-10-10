# ssmastodon

연합 기능을 끈 폐쇄형 커뮤니티용 마스토돈 커스텀 버전입니다. (Mastodon 4.4 기반)

## 주요 특징

- **비공개 서버** — 로그인·가입하지 않은 사용자에게 툿이 보이지 않고, 연합이 제한되어 외부 서버로 콘텐츠가 나가지 않습니다.
- **다중계정 로그인** — 웹에서 여러 계정을 동시에 로그인하고 전환할 수 있습니다.
- **DM 채팅** — DM을 채팅방 형태로 주고받고, 운영진은 서버 내 DM을 한 페이지에서 확인할 수 있습니다.
- **트위터풍 UI** — Bird UI 기반 인터페이스, KoPub 돋움 폰트.
- **마크다운** — `*기울임*`, `**볼드**`, `~~취소선~~` 등 지원.
- **알림 탭 분리** — 모든 알림 / 멘션 / DM.
- **글자수 1,000자**

> 고급 인터페이스(Advanced UI)와 커스텀 이모지는 지원하지 않습니다.

## 설치

Docker Compose로 배포합니다. 자세한 설치 방법은 [마스토돈 공식 문서](https://docs.joinmastodon.org/admin/install/)를 참고하세요.

```bash
docker compose build
docker compose run --rm web bundle exec rake mastodon:setup
docker compose up -d
```

## 라이선스

Copyright (c) 2016-2025 Eugen Rochko (+ [`mastodon authors`](AUTHORS.md))

[LICENSE](LICENSE) 파일에 명시된 대로 GNU Affero General Public License(AGPL) 하에 라이선스가 부여됩니다:

```text
Copyright (c) 2016-2025 Eugen Rochko & other Mastodon contributors

This program is free software: you can redistribute it and/or modify it under
the terms of the GNU Affero General Public License as published by the Free
Software Foundation, either version 3 of the License, or (at your option) any
later version.

This program is distributed in the hope that it will be useful, but WITHOUT
ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
FOR A PARTICULAR PURPOSE. See the GNU Affero General Public License for more
details.

You should have received a copy of the GNU Affero General Public License along
with this program. If not, see https://www.gnu.org/licenses/
```
