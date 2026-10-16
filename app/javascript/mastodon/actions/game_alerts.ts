// 컨텐츠 알림: 내가 행동해야 하는 판(수락 대기·내 차례)이 새로 생기면 어느 화면에 있든 소리 + 데스크톱 알림.
// 알림 목록에는 넣지 않는다 (컨텐츠 툿은 웹에서 숨긴다) — 컨텐츠 메뉴 배지로 알린다.
//   - 시스템 계정이 나를 부른 알림(스트리밍)이 오면 서버에서 내 할 일(wallet.todo)을 읽어 이미 알린 것과 비교한다.
//   - 지금 그 방(/system/sessions/:id)에 들어와 있으면 알리지 않는다 (방에서는 바로 보이고 읽은 것으로 친다. DM 채팅과 같다).
import { createAction } from '@reduxjs/toolkit';

import { apiRequestGet } from 'mastodon/api';
import { knownTodo, setKnownTodo } from 'mastodon/features/system/game_todo';
import { refreshWallet } from 'mastodon/features/system/use_wallet';
import type { Wallet } from 'mastodon/features/system/use_wallet';
import { getLocale } from 'mastodon/locales';
import type { AppDispatch } from 'mastodon/store';

// 소리는 sounds 미들웨어가 meta.sound 를 보고 낸다 (DM 메시지·알림과 같은 소리)
export const gameAlertSound = createAction('game_alerts/sound', () => ({
  payload: undefined,
  meta: { sound: 'boop' },
}));

const currentRoomId = () => /\/system\/sessions\/(\d+)/.exec(window.location.pathname)?.[1] ?? null;

export const notifyGameTurn = () => (dispatch: AppDispatch) => {
  apiRequestGet<Wallet>('v1/system/wallet')
    .then((wallet) => {
      const todo = wallet.todo ?? [];
      const known = knownTodo();
      const room = currentRoomId();
      const fresh = todo.filter((item) => !known.has(item.session_id) && item.session_id !== room);

      // 알린 것 = 전에 알린 것 중 아직 할 일인 것 + 이번에 알린 것 + 방 안에서 본 것 (할 일에서 빠지면 지워져 다음 차례에 다시 알린다)
      setKnownTodo(new Set(todo.map((item) => item.session_id).filter((id) => known.has(id) || id === room || fresh.some((each) => each.session_id === id))));

      refreshWallet();
      if (fresh.length === 0) return;

      // 내 차례는 놓치면 안 되므로 알림 설정(소리·데스크톱 알림 켜기)과 상관없이 항상 울린다. 데스크톱 알림은 브라우저 권한이 있을 때만 뜬다.
      dispatch(gameAlertSound());

      if (typeof window.Notification !== 'undefined' && Notification.permission === 'granted') {
        const korean = getLocale().locale.startsWith('ko');
        fresh.forEach((item) => {
          const notify = new Notification(korean ? '컨텐츠' : 'Contents', {
            body: korean ? `${item.name}: 내 차례입니다` : `${item.name}: your move`,
            tag: `game-${item.session_id}`,
          });
          notify.addEventListener('click', () => {
            window.focus();
            notify.close();
          });
        });
      }
    })
    .catch(() => {
      refreshWallet();
    });
};
