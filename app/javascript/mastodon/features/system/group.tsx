// 여럿이 하는 컨텐츠 목록 (/system/group): 어두운 스테이지 화면에 컨텐츠마다 카드 하나 (stage_page.tsx).
import { useCallback, useEffect, useState } from 'react';

import { Redirect } from 'react-router-dom';

import { apiRequestGet } from 'mastodon/api';

import { StageHub } from './stage_page';
import type { HubGame } from './stage_page';

const REFRESH_MS = 30_000;

interface Overview {
  catalog: { key: string; games: HubGame[] }[];
}

const SystemGroup: React.FC = () => {
  const [games, setGames] = useState<HubGame[] | null>(null);
  const [failed, setFailed] = useState(false);

  const load = useCallback(() => {
    apiRequestGet<Overview>('v1/system')
      .then((overview) => {
        setGames(overview.catalog.find((group) => group.key === 'group')?.games ?? []);
        return overview;
      })
      .catch(() => {
        setFailed(true);
      });
  }, []);

  useEffect(() => {
    load();
    const timer = window.setInterval(load, REFRESH_MS);
    return () => {
      window.clearInterval(timer);
    };
  }, [load]);

  if (failed && !games) return <Redirect to='/system' />;
  if (!games) return null;
  return <StageHub games={games} />;
};

// eslint-disable-next-line import/no-default-export
export default SystemGroup;
