// 이미 알린(또는 처음부터 있던) '내가 행동해야 하는 판'의 id (actions/game_alerts 가 알림을 낼 때 쓴다).
// 할 일에서 빠지면 지워서 다음 차례에 다시 알린다. use_wallet 이 읽을 때마다 syncTodo 로 맞춘다.
let pinged: Set<string> | null = null;

export const knownTodo = (): Set<string> => pinged ?? new Set<string>();

export const setKnownTodo = (ids: Set<string>) => {
  pinged = ids;
};

// 재화를 읽을 때마다: 처음에는 지금 있는 할 일을 기준(알림 없음)으로 삼고, 그 뒤에는 빠진 것만 지운다
export const syncTodo = (ids: string[]) => {
  const current = pinged;
  pinged = current === null ? new Set(ids) : new Set(ids.filter((id) => current.has(id)));
};
