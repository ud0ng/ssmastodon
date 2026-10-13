// 컨텐츠별 게임 화면 (/system/games/:key): 지금 하는 판(게임판), 새 판 신청(상대 고르기), 하는 법, 점수·보상,
// 내 전적, 진행 중·최근 판, 순위. 버튼은 서버원 대신 시스템에게 툿을 보낸다 (board.tsx).
import { useCallback, useEffect, useMemo, useState } from 'react';

import { defineMessages, FormattedMessage, useIntl } from 'react-intl';

import { Link, useParams } from 'react-router-dom';

import StarIcon from '@/styles/bird-theme-svg/star.svg?react';
import { apiRequestGet } from 'mastodon/api';
import { Column } from 'mastodon/components/column';
import { ColumnHeader } from 'mastodon/components/column_header';
import { ICONS } from 'mastodon/components/content_card';
import { LoadingIndicator } from 'mastodon/components/loading_indicator';
import { RelativeTimestamp } from 'mastodon/components/relative_timestamp';

import { GameBoard, sendCommand } from './board';

const messages = defineMessages({
  title: { id: 'system.game.title', defaultMessage: 'Game' },
  search: { id: 'system.game.search', defaultMessage: 'Find a member' },
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
  group: 'duel' | 'group' | 'lesson' | 'event';
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

interface Member {
  acct: string;
  name: string;
  avatar: string;
  house: { name: string; color: string; emoji: string } | null;
}

// 새 판 신청: 상대(여럿이면 여러 명) 고르기
const NewGame: React.FC<{ game: GameInfo; onSent: () => void }> = ({ game, onSent }) => {
  const intl = useIntl();
  const [members, setMembers] = useState<Member[]>([]);
  const [picked, setPicked] = useState<string[]>([]);
  const [query, setQuery] = useState('');
  const [busy, setBusy] = useState(false);
  const [sent, setSent] = useState(false);

  useEffect(() => {
    if (game.group === 'lesson' || game.group === 'event') return;
    apiRequestGet<Member[]>('v1/system/members')
      .then((list) => {
        setMembers(list);
        return list;
      })
      .catch(() => {
        setMembers([]);
      });
  }, [game.group]);

  const shown = useMemo(() => {
    const q = query.trim().toLowerCase();
    return q ? members.filter((member) => member.name.toLowerCase().includes(q) || member.acct.toLowerCase().includes(q)) : members;
  }, [members, query]);

  const toggle = useCallback(
    (acct: string) => {
      setPicked((current) => {
        if (current.includes(acct)) return current.filter((item) => item !== acct);
        if (game.max_opponents === 1) return [acct];
        return current.length >= game.max_opponents ? current : [...current, acct];
      });
    },
    [game.max_opponents],
  );

  const send = useCallback(
    (params: Record<string, unknown>) => {
      setBusy(true);
      sendCommand({ kind: game.key, ...params })
        .then((response) => {
          setSent(true);
          setPicked([]);
          window.setTimeout(onSent, 2_000);
          return response;
        })
        .finally(() => {
          setBusy(false);
        });
    },
    [game.key, onSent],
  );

  if (!game.enabled) {
    return (
      <p className='system-page__empty'>
        <FormattedMessage id='system.game.disabled' defaultMessage='This game is turned off right now.' />
      </p>
    );
  }

  if (game.group === 'lesson') {
    return (
      <div className='system-newgame system-newgame--simple'>
        <button type='button' className='content-card__action' disabled={busy} onClick={() => { send({ mode: 'study' }); }}>
          <FormattedMessage id='system.game.study' defaultMessage='Self-study' />
        </button>
        <button type='button' className='content-card__action content-card__action--secondary' disabled={busy} onClick={() => { send({ mode: 'class' }); }}>
          <FormattedMessage id='system.game.open_class' defaultMessage='Open a class' />
        </button>
        {sent && <span className='system-board__sent'><FormattedMessage id='system.game.sent' defaultMessage='Sent. The system will answer in a moment.' /></span>}
      </div>
    );
  }

  if (game.group === 'event') {
    return (
      <div className='system-newgame system-newgame--simple'>
        <button type='button' className='content-card__action' disabled={busy} onClick={() => { send({}); }}>
          <FormattedMessage id='system.game.open_event' defaultMessage='Open the event' />
        </button>
        {sent && <span className='system-board__sent'><FormattedMessage id='system.game.sent' defaultMessage='Sent. The system will answer in a moment.' /></span>}
      </div>
    );
  }

  return (
    <div className='system-newgame'>
      <div className='system-newgame__head'>
        <strong>
          {game.max_opponents > 1 ? (
            <FormattedMessage id='system.game.pick_many' defaultMessage='Pick up to {max} people' values={{ max: game.max_opponents }} />
          ) : (
            <FormattedMessage id='system.game.pick_one' defaultMessage='Pick an opponent' />
          )}
        </strong>
        <input
          type='search'
          value={query}
          onChange={(event) => { setQuery(event.target.value); }}
          placeholder={intl.formatMessage(messages.search)}
          aria-label={intl.formatMessage(messages.search)}
        />
      </div>
      <div className='system-newgame__members'>
        {shown.map((member) => {
          const index = picked.indexOf(member.acct);
          return (
            <button
              key={member.acct}
              type='button'
              className={index >= 0 ? 'system-member system-member--picked' : 'system-member'}
              style={{ '--house-color': member.house?.color || '#6b5b3e' } as React.CSSProperties}
              onClick={() => { toggle(member.acct); }}
            >
              <img src={member.avatar} alt='' />
              <span className='system-member__name'>{member.name}</span>
              {member.house && <span className='system-member__house'>{member.house.emoji} {member.house.name}</span>}
              {index >= 0 && game.max_opponents > 1 && <span className='system-member__order'>{index + 1}</span>}
            </button>
          );
        })}
      </div>
      <div className='system-newgame__actions'>
        {game.key === 'quidditch' && picked.length > 1 && (
          <span className='hint'>
            <FormattedMessage id='system.game.teams_hint' defaultMessage='You and the first {half} picked are one team.' values={{ half: Math.max(Math.floor((picked.length + 1) / 2) - 1, 0) }} />
          </span>
        )}
        <button type='button' className='content-card__action' disabled={busy || picked.length === 0} onClick={() => { send({ opponents: picked }); }}>
          <FormattedMessage id='system.game.invite' defaultMessage='Challenge' />
        </button>
        {sent && <span className='system-board__sent'><FormattedMessage id='system.game.sent' defaultMessage='Sent. The system will answer in a moment.' /></span>}
      </div>
    </div>
  );
};

const SessionList: React.FC<{ rows: SessionRow[] }> = ({ rows }) => {
  const intl = useIntl();
  return (
    <ul className='system-sessions'>
      {rows.map((row) => (
        <li key={row.id}>
          <Link to={`/system/sessions/${row.id}`} className='system-sessions__row'>
            <span className='system-sessions__players'>
              {row.players.map((player, index) => (
                <span key={player.acct} className={player.me ? 'system-sessions__me' : undefined}>
                  {index > 0 && ' · '}
                  {player.name}
                  {player.result && player.result !== 'lose' && ` (${intl.formatMessage(messages[player.result])})`}
                </span>
              ))}
            </span>
            <span className='system-sessions__time'>
              {row.status === 'finished' && row.finished_at ? (
                <RelativeTimestamp timestamp={row.finished_at} />
              ) : row.status === 'pending' ? (
                <FormattedMessage id='system.game.pending' defaultMessage='Waiting for accept' />
              ) : (
                <FormattedMessage id='system.game.turn' defaultMessage='Turn {turn}' values={{ turn: row.turn }} />
              )}
            </span>
          </Link>
        </li>
      ))}
    </ul>
  );
};

const RULE_LABELS: Record<string, React.ReactNode> = {
  win: <FormattedMessage id='system.result.win' defaultMessage='Win' />,
  draw: <FormattedMessage id='system.result.draw' defaultMessage='Draw' />,
  lose: <FormattedMessage id='system.result.lose' defaultMessage='Loss' />,
};

const SystemGame: React.FC<{ multiColumn?: boolean }> = ({ multiColumn }) => {
  const intl = useIntl();
  const { key } = useParams<{ key: string }>();
  const [game, setGame] = useState<GameInfo | null>(null);
  const [failed, setFailed] = useState(false);

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
            <header className='system-game-page__hero'>
              <span className='system-game-page__icon' aria-hidden>{ICONS[game.key] ?? '📜'}</span>
              <div>
                <h2>{game.name}</h2>
                <p>{game.summary}</p>
              </div>
              <div className='system-game-page__record'>
                <FormattedMessage id='system.record' defaultMessage='{win} W · {lose} L · {draw} D' values={game.record} />
              </div>
            </header>

            <section className='system-section'>
              <h2 className='system-section__title'>
                {game.my_session_id ? (
                  <FormattedMessage id='system.game.now' defaultMessage='Your game' />
                ) : (
                  <FormattedMessage id='system.game.new' defaultMessage='New game' />
                )}
              </h2>
              {game.my_session_id ? (
                <>
                  <GameBoard key={game.my_session_id} sessionId={game.my_session_id} onChanged={load} />
                  <Link className='system-game-page__more' to={`/system/sessions/${game.my_session_id}`}>
                    <FormattedMessage id='system.game.whole' defaultMessage='See the whole game' />
                  </Link>
                </>
              ) : (
                <NewGame game={game} onSent={load} />
              )}
            </section>

            <div className='system-game-page__columns'>
              <section className='system-section'>
                <h2 className='system-section__title'>
                  <FormattedMessage id='system.game.how' defaultMessage='How to play' />
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

            <section className='system-section'>
              <h2 className='system-section__title'>
                <FormattedMessage id='system.active' defaultMessage='In progress' />
              </h2>
              {game.active.length > 0 ? <SessionList rows={game.active} /> : (
                <p className='system-page__empty'>
                  <FormattedMessage id='system.active.empty' defaultMessage='No game in progress.' />
                </p>
              )}
            </section>

            {game.recent.length > 0 && (
              <section className='system-section'>
                <h2 className='system-section__title'>
                  <FormattedMessage id='system.game.recent' defaultMessage='Recent results' />
                </h2>
                <SessionList rows={game.recent} />
              </section>
            )}
          </>
        )}
      </div>
    </Column>
  );
};

// eslint-disable-next-line import/no-default-export
export default SystemGame;
