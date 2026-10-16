// 웹 '시스템' 메뉴
//   /system         컨텐츠 고르기 (묶음별 타일) + 내 캐릭터·소속 점수 짧은 줄 + 내가 하는 판
//   /system/me      내 캐릭터·스탯·돈·인벤토리·성적표·최근 판
// 컨텐츠를 고르면 게임 화면(game.tsx). 진행은 시스템 계정에게 보내는 툿이라 앱에서는 멘션 알림으로 한다.
import { useCallback, useEffect, useState } from 'react';

import { defineMessages, FormattedMessage, useIntl } from 'react-intl';

import { Helmet } from 'react-helmet';
import { Link } from 'react-router-dom';

import StarIcon from '@/styles/bird-theme-svg/star.svg?react';
import { apiRequestGet } from 'mastodon/api';
import { Column } from 'mastodon/components/column';
import { ColumnHeader } from 'mastodon/components/column_header';
import { Countdown } from 'mastodon/components/countdown';
import { LoadingIndicator } from 'mastodon/components/loading_indicator';

import { CharacterHeader } from './character_header';
import type { House } from './crest';

const messages = defineMessages({
  title: { id: 'navigation_bar.contents', defaultMessage: 'Contents' },
});

const REFRESH_MS = 30_000;

const GROUP_TITLES: Record<string, React.ReactNode> = {
  duel: <FormattedMessage id='system.group.duel' defaultMessage='1:1 duels' />,
  group: <FormattedMessage id='system.group.group' defaultMessage='Group games' />,
  event: <FormattedMessage id='system.group.event' defaultMessage='Server events' />,
};

interface Game {
  id: string;
  kind: string;
  name: string;
  status: 'pending' | 'active' | 'finished' | 'cancelled';
  result: 'win' | 'lose' | 'draw' | null;
  turn: number;
  deadline_at: string | null;
  finished_at: string | null;
  opponents: { name: string; acct: string }[];
  status_id: string | null;
}

interface TournamentMatch {
  id: string;
  status: 'waiting' | 'ready' | 'playing' | 'judging' | 'done';
  kind_name: string | null;
  scheduled_at: string | null;
  winner_acct: string | null;
  status_id: string | null;
  session_id?: string | null;
  players: { acct: string; name: string; house_id: string | null }[];
}

interface Tournament {
  id: string;
  name: string;
  status: 'running' | 'finished';
  reward: number;
  winner_house_id: string | null;
  wins: { house_id: string; wins: number }[];
  rounds: { name: string; matches: TournamentMatch[] }[];
}

export interface Overview {
  system_acct: string;
  house_term: string;
  scoring_mode: 'points' | 'tournament';
  tournament: Tournament | null;
  houses: House[];
  character: {
    name: string;
    avatar?: string;
    house_id: string | null;
    profile: { name: string; value: string; color: string | null }[];
    stats: { name: string; value: string }[];
    money: number;
    currency: string;
    inventory: { name: string; count: number; note: string }[];
  };
  record: { win: number; lose: number; draw: number };
  active: Game[];
  recent: Game[];
  games: { key: string; name: string; command: string; max_opponents: number }[];
  commands: Record<'accept' | 'decline' | 'forfeit' | 'points' | 'record', string>;
  catalog: { key: string; games: { key: string; name: string; summary: string; open: number; mine: boolean; enabled?: boolean }[] }[];
}

// 진행 중인 컨텐츠 한 줄 (카드): [아이콘] 컨텐츠 / vs 상대 … 상태 배지 · 남은 시간 (분):(초) 실시간
const GameRow: React.FC<{ game: Game }> = ({ game }) => {
  const opponents = game.opponents.map((opponent) => opponent.name).join(', ');
  const state =
    game.status === 'pending' ? (
      <FormattedMessage id='system.game.pending' defaultMessage='Waiting for accept' />
    ) : (
      <FormattedMessage id='system.game.turn' defaultMessage='Turn {turn}' values={{ turn: game.turn }} />
    );

  return (
    <Link className={`system-live system-live--${game.status}`} to={`/system/sessions/${game.id}`}>
      <span className='system-live__main'>
        <strong className='system-live__name'>{game.name}</strong>
        {opponents && (
          <span className='system-live__vs'>
            <FormattedMessage id='system.game.vs' defaultMessage='vs {names}' values={{ names: opponents }} />
          </span>
        )}
      </span>
      <span className='system-live__state'>{state}</span>
      {game.deadline_at && <Countdown until={game.deadline_at} className='system-live__time' />}
    </Link>
  );
};

const System: React.FC<{ multiColumn: boolean }> = ({ multiColumn }) => {
  const intl = useIntl();
  const [data, setData] = useState<Overview | null>(null);
  const [failed, setFailed] = useState(false);

  const load = useCallback(() => {
    apiRequestGet<Overview>('v1/system')
      .then((overview) => {
        setData(overview);
        setFailed(false);
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

  const title = intl.formatMessage(messages.title);
  const myHouse = data?.houses.find((house) => house.id === data.character.house_id);

  return (
    <Column bindToDocument={!multiColumn} label={title}>
      <ColumnHeader icon='system' iconComponent={StarIcon} title={title} multiColumn={multiColumn} />

      <div className='system-page scrollable'>
        {!data && !failed && <LoadingIndicator />}
        {failed && !data && (
          <p className='system-page__empty'>
            <FormattedMessage id='system.load_failed' defaultMessage='Could not load. Try again in a moment.' />
          </p>
        )}

        {data && (
          <>
            {/* 맨 위: 내 캐릭터만 크게 (소속 | 이름 / 전적). 소속 점수는 글쓰기 패널 맨 아래 */}
            <CharacterHeader name={data.character.name} house={myHouse} houseTerm={data.house_term} record={data.record} />

            {data.active.length > 0 && (
              <section className='system-section'>
                <h2 className='system-section__title'>
                  <FormattedMessage id='system.active' defaultMessage='In progress' />
                </h2>
                <div className='system-live-list'>
                  {data.active.map((game) => <GameRow key={game.id} game={game} />)}
                </div>
              </section>
            )}

            {data.catalog.filter((group) => group.games.length > 0).map((group) => (
              <section className='system-section' key={group.key}>
                <h2 className='system-section__title'>{GROUP_TITLES[group.key]}</h2>
                <div className='system-tiles'>
                  {group.games.map((game) => (
                    <Link key={game.key} className={['system-tile', game.mine && 'system-tile--mine', game.enabled === false && 'system-tile--off'].filter(Boolean).join(' ')} to={`/system/games/${game.key}`}>
                      <span className='system-tile__name'>{game.name}</span>
                      <span className='system-tile__summary'>{game.summary}</span>
                      <span className='system-tile__meta'>
                        {game.enabled === false && <span className='system-tile__badge'><FormattedMessage id='system.tile.off' defaultMessage='Off (staff only)' /></span>}
                        {game.mine && <span className='system-tile__badge'><FormattedMessage id='system.tile.mine' defaultMessage='Playing' /></span>}
                        {game.open > 0 && <FormattedMessage id='system.tile.open' defaultMessage='{count} in progress' values={{ count: game.open }} />}
                      </span>
                    </Link>
                  ))}
                </div>
              </section>
            ))}
          </>
        )}
      </div>

      <Helmet>
        <title>{title}</title>
        <meta name='robots' content='noindex' />
      </Helmet>
    </Column>
  );
};

// eslint-disable-next-line import/no-default-export
export default System;
