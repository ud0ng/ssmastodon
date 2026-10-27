// 내 재화·누적 획득/사용·인벤토리·전적 (GET /api/v1/system/wallet), 재화 기록 (GET /api/v1/system/wallet/records)
// 서버에서 재화 기록이 생기면 스트리밍 'wallet.changed' → refreshWallet() 으로 바로 다시 읽는다 (actions/streaming).
// 글쓰기 패널 아래 버튼(compose/components/wallet_bar)과 재화·인벤토리 화면(system/wallet)이 같이 쓴다.
import { useCallback, useEffect, useState } from 'react';

import { apiRequestGet } from 'mastodon/api';

import { syncTodo } from './game_todo';
import { trackWalletChanges } from './wallet_changes';

export interface WalletItem {
  name: string;
  // 파는 상점 이름 (인벤토리 탭), 상점에 없는 아이템은 null
  shop?: string | null;
  count: number;
  note: string;
  description: string;
  image: string | null;
  usable: boolean;
  giftable: boolean;
  permanent?: boolean;
  effect: string;
  // 사용할 때 고를 것 (캐릭터·소속·소문 내용)과 효과 요약 줄 (상점 설정 > 아이템 효과)
  needs: { character: boolean; house: boolean; text: boolean };
  effects: string[];
}

export interface WalletRecord {
  id: string;
  kind: string;
  kind_name: string;
  money: number;
  items: { name: string; count: number }[];
  reason: string;
  // 양도·사용의 상대: dir 'to' 내가 상대에게 / 'from' 상대가 나에게
  other?: { name: string; acct: string; avatar: string; dir: 'to' | 'from' } | null;
  created_at: string;
}

export interface Wallet {
  currency: string;
  money: number;
  // 인벤토리 화면 위 착용 슬롯: 내 아바타·이름과 지금 입고 있는 칭호·데코·스킨 (permanent 면 영구)
  me: { name: string; avatar: string };
  wearing: { slot: 'title' | 'deco' | 'skin'; preset: string; name: string; until: string; permanent: boolean }[];
  transfer_enabled: boolean;
  gained: number;
  spent: number;
  posts: number;
  post_chars: number;
  // 시즌별 내 툿 (최근 시즌이 위)
  seasons?: { name: string; running: boolean; posts: number; chars: number }[];
  item_count: number;
  record: { win: number; lose: number; draw: number };
  inventory: WalletItem[];
  house_term: string;
  my_house_id: string | null;
  // fx: 아이템으로 붙은 소속 카드 효과 모양 (상점 설정 > 효과 목록, 꺼져 있으면 null)
  // counters: 그 소속 캐릭터들의 누적 수치 결과값 합계 (바뀌면 소속 점수 카드에 알림 배지)
  houses: { id: string; name: string; color: string; total: number; counters?: number; fx?: string | null; fx_until?: string | null }[];
  invites: number;
  // 내가 행동해야 하는 판 (수락 대기·내 차례). 알림 소리·메뉴 배지의 기준
  todo?: { session_id: string; name: string; event?: boolean }[];
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
        trackWalletChanges(next);
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
