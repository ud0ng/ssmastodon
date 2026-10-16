// 내 재화·재화 기록·인벤토리·전적 (GET /api/v1/system/wallet)
// 글쓰기 패널 아래 버튼(compose/components/wallet_bar)과 재화·인벤토리 화면(system/wallet)이 같이 쓴다.
import { useCallback, useEffect, useState } from 'react';

import { apiRequestGet } from 'mastodon/api';

export interface WalletItem {
  name: string;
  count: number;
  note: string;
  description: string;
  image: string | null;
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
  item_count: number;
  record: { win: number; lose: number; draw: number };
  inventory: WalletItem[];
  records: WalletRecord[];
}

const REFRESH_MS = 60_000;

export const useWallet = () => {
  const [wallet, setWallet] = useState<Wallet | null>(null);

  const load = useCallback(() => {
    apiRequestGet<Wallet>('v1/system/wallet')
      .then(setWallet)
      .catch(() => {
        // 시스템 기능이 없거나 잠깐 실패하면 그대로 둔다
      });
  }, []);

  useEffect(() => {
    load();
    const timer = window.setInterval(load, REFRESH_MS);
    window.addEventListener('focus', load);

    return () => {
      window.clearInterval(timer);
      window.removeEventListener('focus', load);
    };
  }, [load]);

  return wallet;
};
