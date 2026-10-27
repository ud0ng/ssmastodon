// 효과(상점 설정 > 효과 목록) 그리기. 모양은 styles/mastodon/_game_fx.scss, 관리 화면 미리보기(admin/game_effects/_layer)와 같은 마크업.
//   캐릭터 효과는 한 곳(/api/v1/system/fx, 지금 효과가 붙은 캐릭터 목록)에서만 받아 모든 화면이 같은 것을 본다.
//   1분마다·창으로 돌아올 때·재화·아이템이 바뀌었을 때(아이템 사용 등) 새로 받는다.
//   데코(아바타 둘레)는 components/avatar, 칭호(이름 글자)는 components/display_name 이 알아서 붙인다.
import { useSyncExternalStore } from 'react';

import { apiRequestGet } from 'mastodon/api';
import { me } from 'mastodon/initial_state';

export interface GameFxShape {
  title?: string;
  deco?: string;
  skin?: string;
}

// 기숙사전 승리 보상은 흰 반짝이를 더 많이 그린다 (18개, Game::Fx.particle_count 와 같다)
const MANY_PARTICLES = new Set(['gryffindor', 'hufflepuff', 'slytherin', 'ravenclaw']);
const particleIndexes = (preset: string) => Array.from({ length: MANY_PARTICLES.has(preset) ? 18 : 6 }, (_, index) => index);

// 떠다니는 그림 겹 (보통 6개). slot: card(소속 카드) · title(칭호) · deco(데코) · skin(스킨)
export const GameFx: React.FC<{ slot: 'card' | 'title' | 'deco' | 'skin'; preset: string }> = ({ slot, preset }) => (
  <span className={`game-fx game-fx--${slot} game-fx--${preset}`} aria-hidden>
    {particleIndexes(preset).map((index) => <span key={index} className='game-fx__p' />)}
  </span>
);

// ── 효과 목록 저장소 (계정 번호 → 효과) ──
const REFRESH_MS = 60_000;
const CHANGED_EVENT = 'ssm:wallet-changed'; // features/system/use_wallet 의 재화·아이템 바뀜과 같은 이벤트
const EMPTY: Record<string, GameFxShape> = {};
const NONE: GameFxShape = {};

let snapshot: Record<string, GameFxShape> = EMPTY;
let started = false;
const listeners = new Set<() => void>();

const load = () => {
  apiRequestGet<{ accounts: Record<string, GameFxShape> }>('v1/system/fx')
    .then(({ accounts }) => {
      snapshot = accounts;
      listeners.forEach((listener) => { listener(); });
      return accounts;
    })
    .catch(() => {
      // 시스템 기능이 없거나 잠깐 실패하면 그대로 둔다
    });
};

const start = () => {
  if (started || !me) return;
  started = true;
  load();
  window.setInterval(load, REFRESH_MS);
  window.addEventListener('focus', load);
  window.addEventListener(CHANGED_EVENT, load);
};

const subscribe = (listener: () => void) => {
  start();
  listeners.add(listener);
  return () => { listeners.delete(listener); };
};

const getSnapshot = () => snapshot;

// 이 계정에 붙은 효과 (없으면 {})
export const useAccountFx = (accountId: string | undefined | null): GameFxShape => {
  const all = useSyncExternalStore(subscribe, getSnapshot, getSnapshot);
  return (accountId ? all[accountId] : undefined) ?? NONE;
};

// 스킨: 그 캐릭터가 쓴 툿·멘션 알림의 배경 전체를 채우는 겹 (위 칸의 맨 앞 자식으로 넣는다. 안 칸은 CSS 가 그 위로 올린다)
export const SkinLayer: React.FC<{ accountId: string | undefined | null }> = ({ accountId }) => {
  const fx = useAccountFx(accountId);

  return fx.skin ? (
    <span className={`game-fx-skin game-fx-skin--${fx.skin}`} aria-hidden>
      <GameFx slot='skin' preset={fx.skin} />
    </span>
  ) : null;
};

// 이름 글자를 칭호로 감싼다 (DisplayName 을 쓰지 않는 이름 줄: 알림 이름 목록, 프로필 머리, DM 목록 등)
export const FxTitle: React.FC<{ accountId: string | undefined | null; children: React.ReactNode }> = ({ accountId, children }) => {
  const fx = useAccountFx(accountId);

  return fx.title ? (
    <span className={`game-fx-title game-fx-title--${fx.title}`}>
      <span className='game-fx-name'>{children}</span>
      <GameFx slot='title' preset={fx.title} />
    </span>
  ) : (
    <>{children}</>
  );
};
