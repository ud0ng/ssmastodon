// 재화·인벤토리·소속 점수·누적 수치가 바뀌었을 때(선물·지급·보상으로 늘었을 때) 알림: 배지 + 소리.
//   '본 것'(seen)을 브라우저에 기억해 두고, 지금 값이 본 것보다 늘었으면 배지를 단다.
//   재화는 늘었을 때만, 인벤토리는 아이템이 새로 생기거나 개수가 늘었을 때만, 소속 점수는 값이 달라졌을 때(오르내림 모두).
//   그 화면(재화·인벤토리·소속 점수)에 들어가 있으면 본 것으로 치고 알리지 않는다.
//   소리는 새로 읽었을 때 앞서 읽은 값보다 늘었을 때 한 번 (처음 읽을 때는 울리지 않는다).
import { useEffect, useState } from 'react';

import { store } from 'mastodon/store';

import type { Wallet } from './use_wallet';

export type ChangeKind = 'money' | 'inventory' | 'house';

interface Seen {
  money: number;
  inventory: Record<string, number>;
  houses: Record<string, number>;
  // 소속 캐릭터들의 누적 수치 결과값 합계 (옛 기록에는 없다)
  counters?: Record<string, number>;
}

const KEY = 'ssm:wallet-seen';
const EVENT = 'ssm:wallet-seen-changed';

const read = (): Seen | null => {
  try {
    const raw = window.localStorage.getItem(KEY);
    return raw ? (JSON.parse(raw) as Seen) : null;
  } catch {
    return null;
  }
};

const write = (seen: Seen) => {
  if (memory && JSON.stringify(memory) === JSON.stringify(seen)) return;

  try {
    window.localStorage.setItem(KEY, JSON.stringify(seen));
  } catch {
    // 저장이 막힌 브라우저에서는 이번 방문 동안만 기억한다
  }
  memory = seen;
  window.dispatchEvent(new Event(EVENT));
};

let memory: Seen | null = null;
const current = () => memory ?? read();

const inventoryOf = (wallet: Wallet) => Object.fromEntries(wallet.inventory.map((item) => [item.name, item.count]));
const housesOf = (wallet: Wallet) => Object.fromEntries(wallet.houses.map((house) => [house.id, house.total]));

const countersOf = (wallet: Wallet) => Object.fromEntries(wallet.houses.map((house) => [house.id, house.counters ?? 0]));

const snapshotOf = (wallet: Wallet): Seen => ({ money: wallet.money, inventory: inventoryOf(wallet), houses: housesOf(wallet), counters: countersOf(wallet) });

// 내려간 것(사용·구매)은 본 것도 같이 내려서 다음에 늘었을 때 알리게 한다
const reconciled = (seen: Seen, wallet: Wallet): Seen => {
  const inventory = inventoryOf(wallet);
  return {
    money: Math.min(seen.money, wallet.money),
    inventory: Object.fromEntries(Object.entries(seen.inventory).filter(([name]) => name in inventory).map(([name, count]) => [name, Math.min(count, inventory[name] ?? 0)])),
    houses: seen.houses,
    counters: seen.counters,
  };
};

export const isChanged = (kind: ChangeKind, wallet: Wallet, seen: Seen | null, houseId?: string): boolean => {
  if (!seen) return false;

  switch (kind) {
  case 'money':
    return wallet.money > seen.money;
  case 'inventory':
    return wallet.inventory.some((item) => item.count > (seen.inventory[item.name] ?? 0));
  default:
    return wallet.houses.some((house) => (houseId ? house.id === houseId : true) && ((house.id in seen.houses && house.total !== seen.houses[house.id]) || (seen.counters && house.id in seen.counters && (house.counters ?? 0) !== seen.counters[house.id])));
  }
};

// 그 화면을 봤다: 본 것을 지금 값으로 (소속 점수는 houseId 가 있으면 그 소속만)
export const markSeen = (kind: ChangeKind, wallet: Wallet, houseId?: string) => {
  const base = reconciled(current() ?? snapshotOf(wallet), wallet);
  const next = { ...base };
  if (kind === 'money') next.money = wallet.money;
  else if (kind === 'inventory') next.inventory = inventoryOf(wallet);
  else {
    next.houses = { ...base.houses, ...(houseId ? { [houseId]: housesOf(wallet)[houseId] } : housesOf(wallet)) };
    next.counters = { ...base.counters, ...(houseId ? { [houseId]: countersOf(wallet)[houseId] } : countersOf(wallet)) };
  }
  write(next);
};

let previous: Wallet | null = null;

const onPage = (kind: ChangeKind) => {
  const path = window.location.pathname;
  if (kind === 'money') return path.startsWith('/system/wallet');
  if (kind === 'inventory') return path.startsWith('/system/inventory');
  return path.startsWith('/system/houses/');
};

// 재화를 새로 읽을 때마다 (use_wallet): 본 것 맞추기 + 새로 늘었으면 소리
export const trackWalletChanges = (wallet: Wallet) => {
  const seen = current();
  if (!seen) {
    write(snapshotOf(wallet));
  } else {
    // 이 화면에 들어가 있으면 본 것으로
    if (onPage('money')) markSeen('money', wallet);
    if (onPage('inventory')) markSeen('inventory', wallet);
    const houseId = /\/system\/houses\/(\d+)/.exec(window.location.pathname)?.[1];
    if (houseId) markSeen('house', wallet, houseId);
    // 처음 보는 소속은 지금 값을 본 것으로
    const latest = current() ?? seen;
    write({
      ...reconciled(latest, wallet),
      houses: { ...Object.fromEntries(wallet.houses.filter((house) => !(house.id in latest.houses)).map((house) => [house.id, house.total])), ...latest.houses },
      counters: { ...Object.fromEntries(wallet.houses.filter((house) => !(house.id in (latest.counters ?? {}))).map((house) => [house.id, house.counters ?? 0])), ...latest.counters },
    });
  }

  const before = previous;
  previous = wallet;
  if (!before) return;

  const grew =
    (wallet.money > before.money && !onPage('money')) ||
    (isChanged('inventory', wallet, { money: 0, inventory: inventoryOf(before), houses: {} }) && !onPage('inventory')) ||
    (isChanged('house', wallet, { money: 0, inventory: {}, houses: housesOf(before), counters: countersOf(before) }) && !onPage('house'));

  // 소리는 sounds 미들웨어가 meta.sound 를 보고 낸다 (컨텐츠 알림과 같은 소리)
  if (grew) store.dispatch({ type: 'game_alerts/sound', meta: { sound: 'boop' } });
};

// 이 종류에 알림 배지를 달아야 하나 (본 것이 바뀌면 다시 그린다)
export const useChanged = (kind: ChangeKind, wallet: Wallet | null, houseId?: string): boolean => {
  const [, setTick] = useState(0);

  useEffect(() => {
    const update = () => { setTick((tick) => tick + 1); };
    window.addEventListener(EVENT, update);
    return () => { window.removeEventListener(EVENT, update); };
  }, []);

  return wallet ? isChanged(kind, wallet, current(), houseId) : false;
};
