// 내 재화·누적 획득/사용·인벤토리·전적 (GET /api/v1/system/wallet), 재화 기록 (GET /api/v1/system/wallet/records)
// 서버에서 재화 기록이 생기면 스트리밍 'wallet.changed' → refreshWallet() 으로 바로 다시 읽는다 (actions/streaming).
// 글쓰기 패널 아래 버튼(compose/components/wallet_bar)과 재화·인벤토리 화면(system/wallet)이 같이 쓴다.
import { useCallback, useEffect, useState } from 'react';

import { apiRequestGet } from 'mastodon/api';

import { syncTodo } from './game_todo';

export interface WalletItem {
  name: string;
  count: number;
  note: string;
  description: string;
  image: string | null;
  usable: boolean;
  giftable: boolean;
  permanent?: boolean;
  use_target: 'stat' | 'character' | 'special';
  special_kind: 'staff' | 'report' | 'bomb' | 'howler';
  effect: string;
  allow_random: boolean;
  stat_temporary: boolean;
  stat_minutes: number;
  stat: string | null;
  stat_value: string | null;
}

export interface WalletRecord {
  id: string;
  kind: string;
  kind_name: string;
  money: number;
  items: { name: string; count: number }[];
  reason: string;
  created_at: string;
}

export interface Wallet {
  currency: string;
  money: number;
  transfer_enabled: boolean;
  gained: number;
  spent: number;
  item_count: number;
  record: { win: number; lose: number; draw: number };
  inventory: WalletItem[];
  house_term: string;
  my_house_id: string | null;
  houses: { id: string; name: string; color: string; total: number }[];
  wearing?: { label: string; until: string }[];
  invites: number;
  // 내가 행동해야 하는 판 (수락 대기·내 차례). 알림 소리·메뉴 배지의 기준
  todo?: { session_id: string; name: string }[];
}

export type RecordFilter = 'all' | 'gain' | 'spend' | 'items';

const REFRESH_MS = 60_000;
export const CHANGED_EVENT = 'ssm:wallet-changed';

// 구매·사용·선물·버리기 뒤: 글쓰기창 아래 버튼과 화면을 같이 새로 읽게
export const refreshWallet = () => {
  window.dispatchEvent(new Event(CHANGED_EVENT));
};

// 서버가 보낸 { error } 문구 (없으면 null)
export const apiErrorMessage = (error: unknown): string | null => {
  const data = (error as { response?: { data?: { error?: unknown } } } | null)?.response?.data;
  return typeof data?.error === 'string' ? data.error : null;
};

export const useWallet = () => {
  const [wallet, setWallet] = useState<Wallet | null>(null);

  const load = useCallback(() => {
    apiRequestGet<Wallet>('v1/system/wallet')
      .then((next) => {
        syncTodo((next.todo ?? []).map((item) => item.session_id));
        setWallet(next);
        return next;
      })
      .catch(() => {
        // 시스템 기능이 없거나 잠깐 실패하면 그대로 둔다
      });
  }, []);

  useEffect(() => {
    load();
    const timer = window.setInterval(load, REFRESH_MS);
    window.addEventListener('focus', load);
    window.addEventListener(CHANGED_EVENT, load);

    return () => {
      window.clearInterval(timer);
      window.removeEventListener('focus', load);
      window.removeEventListener(CHANGED_EVENT, load);
    };
  }, [load]);

  return wallet;
};

// 재화 기록: 탭(filter)마다 30개씩, 더 보기로 다음 쪽. 재화가 바뀌면 첫 쪽부터 다시
export const useWalletRecords = (filter: RecordFilter) => {
  const [records, setRecords] = useState<WalletRecord[] | null>(null);
  const [next, setNext] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);

  const fetchPage = useCallback(
    (maxId: string | null) => {
      setLoading(true);
      apiRequestGet<{ records: WalletRecord[]; next_max_id: string | null }>('v1/system/wallet/records', { filter, ...(maxId ? { max_id: maxId } : {}) })
        .then(({ records: page, next_max_id }) => {
          setRecords((current) => (maxId && current ? [...current, ...page] : page));
          setNext(next_max_id);
          return page;
        })
        .catch(() => {
          setRecords((current) => current ?? []);
        })
        .finally(() => {
          setLoading(false);
        });
    },
    [filter],
  );

  useEffect(() => {
    setRecords(null);
    fetchPage(null);
    const reload = () => { fetchPage(null); };
    window.addEventListener(CHANGED_EVENT, reload);

    return () => {
      window.removeEventListener(CHANGED_EVENT, reload);
    };
  }, [fetchPage]);

  const loadMore = useCallback(() => {
    if (next) fetchPage(next);
  }, [fetchPage, next]);

  return { records, loading, hasMore: next !== null, loadMore };
};
