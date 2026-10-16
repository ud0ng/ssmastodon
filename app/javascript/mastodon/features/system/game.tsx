// 컨텐츠 세부 화면 (/system/games/:key): 게임 소개 · 룰 · 순위(5명) · [시작하기](상대 고르기 모달) · 방 목록(진행 중/완료).
// 방을 누르면 컨텐츠 방(session.tsx)으로 — 내가 낀 방이 아니면 관전. 버튼은 서버원 대신 시스템에게 툿을 보낸다 (board.tsx).
import { useCallback, useEffect, useState } from 'react';

import { defineMessages, FormattedMessage, useIntl } from 'react-intl';

import { Link, useHistory, useParams } from 'react-router-dom';

import StarIcon from '@/styles/bird-theme-svg/star.svg?react';
import { openModal } from 'mastodon/actions/modal';
import { apiRequestGet } from 'mastodon/api';
import { Column } from 'mastodon/components/column';
import { ColumnHeader } from 'mastodon/components/column_header';
import { CommandText } from 'mastodon/components/command_text';
import { ICONS } from 'mastodon/components/content_card';
import { Countdown } from 'mastodon/components/countdown';
import { LoadingIndicator } from 'mastodon/components/loading_indicator';
import { RelativeTimestamp } from 'mastodon/components/relative_timestamp';
import { useAppDispatch } from 'mastodon/store';

import { sendCommand, waitForSession } from './board';

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
  // 동시 진행을 막았는데 다른 컨텐츠를 하고 있을 때: 문구(명령어 탭 '이미 진행 중 (웹 시작하기)')와 그 방
  busy: { message: string; session_id: string; name: string | null } | null;
  active: SessionRow[];
  recent: SessionRow[];
  ranking: { name: string; acct: string; wins: number; me: boolean }[];
}

const RULE_LABELS: Record<string, React.ReactNode> = {
  win: <FormattedMessage id='system.result.win' defaultMessage='Win' />,
  draw: <FormattedMessage id='system.result.draw' defaultMessage='Draw' />,
  lose: <FormattedMessage id='system.result.lose' defaultMessage='Loss' />,
};

// [시작하기]: 상대 고르기 모달. 서버 이벤트는 바로 열기, 내가 하는 방이 있으면 그 방으로.
// 동시 진행을 막았는데 다른 컨텐츠를 하고 있으면 신청하지 않고 바로 안내 (onBusy)
const StartButton: React.FC<{ game: GameInfo; onSent: () => void; onBusy: () => void }> = ({ game, onSent, onBusy }) => {
  const dispatch = useAppDispatch();
  const history = useHistory();
  const [busy, setBusy] = useState(false);
  const [sent, setSent] = useState(false);

  const openChallenge = useCallback(() => {
    if (game.busy) {
      onBusy();
      return;
    }
    dispatch(openModal({ modalType: 'CHALLENGE', modalProps: { gameKey: game.key, name: game.name, maxOpponents: game.max_opponents } }));
  }, [dispatch, game.key, game.name, game.max_opponents, game.busy, onBusy]);

  const openEvent = useCallback(() => {
    if (game.busy) {
      onBusy();
      return;
    }
    setBusy(true);
    sendCommand({ kind: game.key })
      .then(() => waitForSession(game.key, (info) => info.active[0]?.id ?? null))
      .then((sessionId) => {
        if (sessionId) {
          history.push(`/system/sessions/${sessionId}`);
        } else {
          setSent(true);
          window.setTimeout(onSent, 2_000);
        }
        return sessionId;
      })
      .finally(() => {
        setBusy(false);
      });
  }, [game.key, game.busy, onSent, onBusy, history]);

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
              {row.status !== 'finished' && row.deadline_at && <Countdown until={row.deadline_at} className='system-rooms__time' />}
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

type Tab = 'rules' | 'active' | 'recent';

const SystemGame: React.FC<{ multiColumn?: boolean }> = ({ multiColumn }) => {
  const intl = useIntl();
  const { key } = useParams<{ key: string }>();
  const [game, setGame] = useState<GameInfo | null>(null);
  const [failed, setFailed] = useState(false);
  const [tab, setTab] = useState<Tab>('rules');
  const [busyShown, setBusyShown] = useState(false);

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

  const showBusy = useCallback(() => {
    setBusyShown(true);
  }, []);

  const title = game?.name ?? intl.formatMessage(messages.title);
  const rooms = game && tab !== 'rules' ? game[tab] : [];
  const topWins = game?.ranking[0]?.wins || 1;

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
              <StartButton game={game} onSent={load} onBusy={showBusy} />
            </header>

            {/* 동시 진행을 막았을 때: [시작하기]를 누르면 신청하지 않고 바로 안내 */}
            {busyShown && game.busy && !game.my_session_id && (
              <div className='system-busy' role='alert'>
                <span className='system-busy__text'><CommandText text={game.busy.message} /></span>
                <Link to={`/system/sessions/${game.busy.session_id}`} className='system-busy__link'>
                  {game.busy.name ? (
                    <FormattedMessage id='system.game.busy_room' defaultMessage='Go to {name}' values={{ name: game.busy.name }} />
                  ) : (
                    <FormattedMessage id='system.game.enter_room' defaultMessage='Go to my room' />
                  )}
                </Link>
              </div>
            )}

            {/* 탭: 룰 / 진행 중 / 완료 */}
            <div className='notification__filter-bar system-rooms__tabs'>
              <button type='button' className={tab === 'rules' ? 'active' : undefined} onClick={() => { setTab('rules'); }}>
                <FormattedMessage id='system.game.rules' defaultMessage='Rules' />
              </button>
              <button type='button' className={tab === 'active' ? 'active' : undefined} onClick={() => { setTab('active'); }}>
                <FormattedMessage id='system.game.tab_active' defaultMessage='In progress' />
                {game.active.length > 0 && <span className='system-rooms__count'>{game.active.length}</span>}
              </button>
              <button type='button' className={tab === 'recent' ? 'active' : undefined} onClick={() => { setTab('recent'); }}>
                <FormattedMessage id='system.game.finished' defaultMessage='Finished' />
              </button>
            </div>

            {tab === 'rules' ? (
              <>
                {/* 룰: 한 줄씩, [명령어]는 배지 */}
                <section className='system-section'>
                  <h2 className='system-section__title'>
                    <FormattedMessage id='system.game.rules' defaultMessage='Rules' />
                  </h2>
                  <ol className='system-steps'>
                    {game.steps.map((step, index) => (
                      <li key={step} className='system-steps__item'>
                        <span className='system-steps__number'>{index + 1}</span>
                        <span className='system-steps__text'><CommandText text={step} badge /></span>
                      </li>
                    ))}
                  </ol>
                  {/* 보상: 결과마다 한 칸 (점수 · 재화 · 아이템) */}
                  <div className='system-rewards'>
                    {game.rules.map((rule) => (
                      <div key={rule.label} className={`system-rewards__cell system-rewards__cell--${rule.label}`}>
                        <span className='system-rewards__label'>{RULE_LABELS[rule.label] ?? rule.label}</span>
                        <strong className='system-rewards__points'>
                          <FormattedMessage id='system.game.points_value' defaultMessage='{points} pts' values={{ points: rule.points }} />
                        </strong>
                        <span className='system-rewards__money'>{rule.money} {game.currency}</span>
                        {rule.items && rule.items.length > 0 && <span className='system-rewards__items'>+ {rule.items.join(', ')}</span>}
                      </div>
                    ))}
                  </div>
                </section>

                {/* 최다 승리 (최대 5명): 한 줄씩, 메달 + 승수 막대 */}
                <section className='system-section'>
                  <h2 className='system-section__title'>
                    <FormattedMessage id='system.game.ranking' defaultMessage='Most wins' />
                  </h2>
                  {game.ranking.length > 0 ? (
                    <ol className='system-podium'>
                      {game.ranking.map((row, index) => (
                        <li key={row.acct} className={row.me ? 'system-podium__row system-podium__row--me' : 'system-podium__row'}>
                          <span className={`system-podium__rank system-podium__rank--${index + 1}`}>{index + 1}</span>
                          <span className='system-podium__name'>{row.name}</span>
                          <span className='system-podium__bar'>
                            <span style={{ width: `${(row.wins / topWins) * 100}%` }} />
                          </span>
                          <strong className='system-podium__wins'>
                            <FormattedMessage id='system.game.wins' defaultMessage='{wins} W' values={{ wins: row.wins }} />
                          </strong>
                        </li>
                      ))}
                    </ol>
                  ) : (
                    <p className='system-page__empty'>
                      <FormattedMessage id='system.game.no_ranking' defaultMessage='No wins yet.' />
                    </p>
                  )}
                </section>
              </>
            ) : rooms.length > 0 ? (
              <RoomList rows={rooms} />
            ) : (
              <p className='system-page__empty'>
                {tab === 'active' ? (
                  <FormattedMessage id='system.active.empty' defaultMessage='No game in progress.' />
                ) : (
                  <FormattedMessage id='system.game.no_finished' defaultMessage='No finished games yet.' />
                )}
              </p>
            )}
          </>
        )}
      </div>
    </Column>
  );
};

// eslint-disable-next-line import/no-default-export
export default SystemGame;
