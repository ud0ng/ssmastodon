// 컨텐츠 세부 화면 (/system/games/:key): 게임 소개 · 룰 · 순위(5명) · [시작하기](상대 고르기 모달) · 방 목록(진행 중/완료).
// 방을 누르면 컨텐츠 방(session.tsx)으로 — 내가 낀 방이 아니면 관전. 버튼은 서버원 대신 시스템에게 툿을 보낸다 (board.tsx).
import { useCallback, useEffect, useState } from 'react';

import { defineMessages, FormattedMessage, useIntl } from 'react-intl';

import { Link, useParams } from 'react-router-dom';

import StarIcon from '@/styles/bird-theme-svg/star.svg?react';
import { openModal } from 'mastodon/actions/modal';
import { apiRequestGet } from 'mastodon/api';
import { Column } from 'mastodon/components/column';
import { ColumnHeader } from 'mastodon/components/column_header';
import { ICONS } from 'mastodon/components/content_card';
import { LoadingIndicator } from 'mastodon/components/loading_indicator';
import { RelativeTimestamp } from 'mastodon/components/relative_timestamp';
import { useAppDispatch } from 'mastodon/store';

import { sendCommand } from './board';

const messages = defineMessages({
  title: { id: 'system.game.title', defaultMessage: 'Game' },
  win: { id: 'system.result.win', defaultMessage: 'Win' },
  draw: { id: 'system.result.draw', defaultMessage: 'Draw' },
  lose: { id: 'system.result.lose', defaultMessage: 'Loss' },
});

const REFRESH_MS = 15_000;

interface SessionRow {
  id: string;
  status: 'pending' | 'active' | 'finished' | 'cancelled';
  turn: number;
  deadline_at: string | null;
  finished_at: string | null;
  players: { name: string; acct: string; result: 'win' | 'lose' | 'draw' | null; me: boolean }[];
}

interface GameInfo {
  key: string;
  name: string;
  group: 'duel' | 'group';
  event: boolean;
  enabled: boolean;
  system_acct: string;
  command: string | null;
  max_opponents: number;
  summary: string;
  steps: string[];
  rules: { label: string; points: number; money: number; items?: string[] }[];
  currency: string;
  record: { win: number; lose: number; draw: number };
  my_session_id: string | null;
  active: SessionRow[];
  recent: SessionRow[];
  ranking: { name: string; acct: string; wins: number; me: boolean }[];
}

const RULE_LABELS: Record<string, React.ReactNode> = {
  win: <FormattedMessage id='system.result.win' defaultMessage='Win' />,
  draw: <FormattedMessage id='system.result.draw' defaultMessage='Draw' />,
  lose: <FormattedMessage id='system.result.lose' defaultMessage='Loss' />,
};

// [시작하기]: 상대 고르기 모달. 서버 이벤트는 바로 열기, 내가 하는 방이 있으면 그 방으로
const StartButton: React.FC<{ game: GameInfo; onSent: () => void }> = ({ game, onSent }) => {
  const dispatch = useAppDispatch();
  const [busy, setBusy] = useState(false);
  const [sent, setSent] = useState(false);

  const openChallenge = useCallback(() => {
    dispatch(openModal({ modalType: 'CHALLENGE', modalProps: { gameKey: game.key, name: game.name, maxOpponents: game.max_opponents } }));
  }, [dispatch, game.key, game.name, game.max_opponents]);

  const openEvent = useCallback(() => {
    setBusy(true);
    sendCommand({ kind: game.key })
      .then((response) => {
        setSent(true);
        window.setTimeout(onSent, 2_000);
        return response;
      })
      .finally(() => {
        setBusy(false);
      });
  }, [game.key, onSent]);

  if (game.my_session_id) {
    return (
      <Link to={`/system/sessions/${game.my_session_id}`} className='system-start'>
        <FormattedMessage id='system.game.enter_room' defaultMessage='Go to my room' />
      </Link>
    );
  }

  if (!game.enabled) {
    return (
      <span className='system-start system-start--off'>
        <FormattedMessage id='system.game.disabled' defaultMessage='This game is turned off right now.' />
      </span>
    );
  }

  if (game.event) {
    return sent ? (
      <span className='system-start system-start--off'>
        <FormattedMessage id='system.game.sent' defaultMessage='Sent. The system will answer in a moment.' />
      </span>
    ) : (
      <button type='button' className='system-start' disabled={busy} onClick={openEvent}>
        <FormattedMessage id='system.game.open_event' defaultMessage='Open the event' />
      </button>
    );
  }

  return (
    <button type='button' className='system-start' onClick={openChallenge}>
      <FormattedMessage id='system.game.start' defaultMessage='Start' />
    </button>
  );
};

// 방 목록 한 줄: 참가자 · 상태(턴/결과/수락 대기) · 내 방이 아니면 [관전]
const RoomList: React.FC<{ rows: SessionRow[] }> = ({ rows }) => {
  const intl = useIntl();
  return (
    <ul className='system-rooms'>
      {rows.map((row) => {
        const mine = row.players.some((player) => player.me);
        return (
          <li key={row.id}>
            <Link to={`/system/sessions/${row.id}`} className='system-rooms__row'>
              <span className='system-rooms__players'>
                {row.players.map((player, index) => (
                  <span key={player.acct} className={player.me ? 'system-rooms__me' : undefined}>
                    {index > 0 && <span className='system-rooms__vs'>{row.players.length === 2 ? ' vs ' : ' · '}</span>}
                    {player.name}
                    {player.result && player.result !== 'lose' && ` (${intl.formatMessage(messages[player.result])})`}
                  </span>
                ))}
              </span>
              <span className='system-rooms__state'>
                {row.status === 'finished' && row.finished_at ? (
                  <RelativeTimestamp timestamp={row.finished_at} />
                ) : row.status === 'pending' ? (
                  <FormattedMessage id='system.game.pending' defaultMessage='Waiting for accept' />
                ) : (
                  <FormattedMessage id='system.game.turn' defaultMessage='Turn {turn}' values={{ turn: row.turn }} />
                )}
              </span>
              <span className={mine ? 'system-rooms__tag system-rooms__tag--mine' : 'system-rooms__tag'}>
                {mine ? (
                  <FormattedMessage id='system.game.my_room' defaultMessage='Mine' />
                ) : (
                  <FormattedMessage id='system.game.spectate' defaultMessage='Watch' />
                )}
              </span>
            </Link>
          </li>
        );
      })}
    </ul>
  );
};

const SystemGame: React.FC<{ multiColumn?: boolean }> = ({ multiColumn }) => {
  const intl = useIntl();
  const { key } = useParams<{ key: string }>();
  const [game, setGame] = useState<GameInfo | null>(null);
  const [failed, setFailed] = useState(false);
  const [tab, setTab] = useState<'active' | 'recent'>('active');

  const load = useCallback(() => {
    apiRequestGet<GameInfo>(`v1/system/games/${key}`)
      .then((info) => {
        setGame(info);
        setFailed(false);
        return info;
      })
      .catch(() => {
        setFailed(true);
      });
  }, [key]);

  useEffect(() => {
    load();
    const timer = window.setInterval(load, REFRESH_MS);
    return () => {
      window.clearInterval(timer);
    };
  }, [load]);

  const title = game?.name ?? intl.formatMessage(messages.title);
  const rooms = game ? game[tab] : [];

  return (
    <Column bindToDocument={!multiColumn} label={title}>
      <ColumnHeader icon='system' iconComponent={StarIcon} title={title} multiColumn={multiColumn} showBackButton />

      <div className='system-page system-game-page scrollable'>
        {!game && !failed && <LoadingIndicator />}
        {failed && !game && (
          <p className='system-page__empty'>
            <FormattedMessage id='system.load_failed' defaultMessage='Could not load. Try again in a moment.' />
          </p>
        )}

        {game && (
          <>
            {/* 게임 소개 + 시작하기 */}
            <header className='system-game-page__hero'>
              <span className='system-game-page__icon' aria-hidden>{ICONS[game.key] ?? '📜'}</span>
              <div className='system-game-page__intro'>
                <h2>{game.name}</h2>
                <p>{game.summary}</p>
                <span className='system-game-page__record'>
                  <FormattedMessage id='system.record' defaultMessage='{win} W · {lose} L · {draw} D' values={game.record} />
                </span>
              </div>
              <StartButton game={game} onSent={load} />
            </header>

            <div className='system-game-page__columns'>
              {/* 룰 */}
              <section className='system-section'>
                <h2 className='system-section__title'>
                  <FormattedMessage id='system.game.rules' defaultMessage='Rules' />
                </h2>
                <ol className='system-game-page__steps'>
                  {game.steps.map((step) => <li key={step}>{step}</li>)}
                </ol>
                <table className='system-game-page__rules'>
                  <thead>
                    <tr>
                      <th />
                      <th><FormattedMessage id='system.game.points' defaultMessage='Points' /></th>
                      <th>{game.currency}</th>
                    </tr>
                  </thead>
                  <tbody>
                    {game.rules.map((rule) => (
                      <tr key={rule.label}>
                        <th>{RULE_LABELS[rule.label] ?? rule.label}</th>
                        <td>{rule.points}</td>
                        <td>
                          {rule.money}
                          {rule.items && rule.items.length > 0 && <span className='system-game-page__items'> + {rule.items.join(', ')}</span>}
                        </td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </section>

              {/* 순위 (최대 5명) */}
              <section className='system-section'>
                <h2 className='system-section__title'>
                  <FormattedMessage id='system.game.ranking' defaultMessage='Most wins' />
                </h2>
                {game.ranking.length > 0 ? (
                  <ol className='system-ranking'>
                    {game.ranking.map((row) => (
                      <li key={row.acct} className={row.me ? 'system-ranking__me' : undefined}>
                        <span>{row.name}</span>
                        <strong>{row.wins}</strong>
                      </li>
                    ))}
                  </ol>
                ) : (
                  <p className='system-page__empty'>
                    <FormattedMessage id='system.game.no_ranking' defaultMessage='No wins yet.' />
                  </p>
                )}
              </section>
            </div>

            {/* 방 목록: 진행 중 / 완료 */}
            <section className='system-section'>
              <h2 className='system-section__title'>
                <FormattedMessage id='system.game.rooms' defaultMessage='Rooms' />
              </h2>
              <div className='notification__filter-bar system-rooms__tabs'>
                <button type='button' className={tab === 'active' ? 'active' : undefined} onClick={() => { setTab('active'); }}>
                  <FormattedMessage id='system.active' defaultMessage='In progress' />
                  {game.active.length > 0 && ` ${game.active.length}`}
                </button>
                <button type='button' className={tab === 'recent' ? 'active' : undefined} onClick={() => { setTab('recent'); }}>
                  <FormattedMessage id='system.game.finished' defaultMessage='Finished' />
                </button>
              </div>
              {rooms.length > 0 ? <RoomList rows={rooms} /> : (
                <p className='system-page__empty'>
                  {tab === 'active' ? (
                    <FormattedMessage id='system.active.empty' defaultMessage='No game in progress.' />
                  ) : (
                    <FormattedMessage id='system.game.no_finished' defaultMessage='No finished games yet.' />
                  )}
                </p>
              )}
            </section>
          </>
        )}
      </div>
    </Column>
  );
};

// eslint-disable-next-line import/no-default-export
export default SystemGame;
