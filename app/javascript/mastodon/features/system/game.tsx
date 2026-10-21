// 컨텐츠 세부 화면 (/system/games/:key): 게임 소개 · 룰 · 순위(5명) · [시작하기](상대 고르기 모달) · 방 목록(진행 중/완료).
// 방을 누르면 컨텐츠 방(session.tsx)으로 — 내가 낀 방이 아니면 관전. 버튼은 서버원 대신 시스템에게 툿을 보낸다 (board.tsx).
import { Fragment, useCallback, useEffect, useState } from 'react';

import { defineMessages, FormattedMessage, useIntl } from 'react-intl';

import { Link, useHistory, useParams } from 'react-router-dom';

import StarIcon from '@/styles/bird-theme-svg/star.svg?react';
import { openModal } from 'mastodon/actions/modal';
import { apiRequestDelete, apiRequestGet, apiRequestPost } from 'mastodon/api';
import { Column } from 'mastodon/components/column';
import { ColumnHeader } from 'mastodon/components/column_header';
import { CommandText } from 'mastodon/components/command_text';
import { Countdown } from 'mastodon/components/countdown';
import { GameIcon } from 'mastodon/components/game_icons';
import { LoadingIndicator } from 'mastodon/components/loading_indicator';
import { RelativeTimestamp } from 'mastodon/components/relative_timestamp';
import { useAppDispatch } from 'mastodon/store';

import { sendCommand, waitForSession } from './board';
import { StageIntro } from './stage_page';

const messages = defineMessages({
  title: { id: 'system.game.title', defaultMessage: 'Game' },
  win: { id: 'system.result.win', defaultMessage: 'Win' },
  draw: { id: 'system.result.draw', defaultMessage: 'Draw' },
  lose: { id: 'system.result.lose', defaultMessage: 'Loss' },
  limitTitle: { id: 'system.game.limit_title', defaultMessage: 'You cannot start this right now' },
  limitConfirm: { id: 'system.game.limit_confirm', defaultMessage: 'OK' },
  deleteRoom: { id: 'system.game.delete_room', defaultMessage: 'Delete this record' },
  deleteTitle: { id: 'system.game.delete_title', defaultMessage: 'Delete this game?' },
  deleteMessage: { id: 'system.game.delete_message', defaultMessage: 'The record and every related mention and message will be deleted. This cannot be undone.' },
  tabRules: { id: 'system.game.rules', defaultMessage: 'Rules' },
  tabRanking: { id: 'system.game.ranking', defaultMessage: 'Most wins' },
  tabActive: { id: 'system.game.tab_active', defaultMessage: 'In progress' },
  tabRecent: { id: 'system.game.finished', defaultMessage: 'Finished' },
  deleteConfirm: { id: 'system.game.delete_confirm', defaultMessage: 'Delete' },
});

const REFRESH_MS = 15_000;

export interface SessionRow {
  id: string;
  // 운영진의 테스트 플레이 (참가자와 운영진에게만 보인다, 운영진은 자물쇠)
  test?: boolean;
  status: 'pending' | 'lobby' | 'active' | 'finished' | 'cancelled';
  turn: number;
  // 여럿이 하는 이벤트의 진행 라운드
  round?: number | null;
  // 내가 초대받고 아직 수락하지 않은 방 ('대기중')
  waiting?: boolean;
  deadline_at: string | null;
  finished_at: string | null;
  players: { name: string; acct: string; avatar: string; result: 'win' | 'lose' | 'draw' | null; me: boolean; waiting?: boolean }[];
}

export interface GameInfo {
  key: string;
  name: string;
  group: 'duel' | 'group';
  event: boolean;
  can_open?: boolean;
  // 운영진이 웹에서 바로 여는 모집형 이벤트 (아니면 멘션 명령어로 연다)
  web_open?: boolean;
  event_min_players?: number;
  event_max_players?: number;
  event_join_minutes?: number;
  // 운영진: 끝난 판 기록을 지울 수 있다
  staff?: boolean;
  daily_limit_message?: string | null;
  enabled: boolean;
  system_acct: string;
  command: string | null;
  max_opponents: number;
  min_opponents?: number;
  team?: boolean;
  uneven_teams?: boolean;
  // 운영진이 연 이벤트 모집 중이고 내가 아직 참가하지 않았다
  recruiting?: { session_id: string; ends_at: string | null; count: number } | null;
  summary: string;
  rules_text?: { icon: string; title: string; text: string; visual?: string | null; nodes?: string[]; table?: { head: string[]; rows: string[][] } | null }[];
  cast?: { name: string; lines: string[] }[];
  roles?: { name: string | null; win: string; win_notes?: string[]; notes: string[] }[];
  items?: { name: string; effect: string; icon: string; count?: string | null }[];
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
export const StartButton: React.FC<{ game: GameInfo; onSent: () => void; onBusy: () => void; onRooms?: () => void }> = ({ game, onSent, onBusy, onRooms }) => {
  const intl = useIntl();
  const dispatch = useAppDispatch();
  const history = useHistory();
  const [busy, setBusy] = useState(false);
  const [sent, setSent] = useState(false);

  const openChallenge = useCallback(() => {
    if (game.busy) {
      onBusy();
      return;
    }
    if (game.daily_limit_message) {
      dispatch(openModal({
        modalType: 'CONFIRM',
        modalProps: {
          title: intl.formatMessage(messages.limitTitle),
          message: game.daily_limit_message,
          confirm: intl.formatMessage(messages.limitConfirm),
          onConfirm: () => undefined,
        },
      }));
      return;
    }
    dispatch(openModal({ modalType: 'CHALLENGE', modalProps: { gameKey: game.key, name: game.name, maxOpponents: game.max_opponents, minOpponents: game.min_opponents ?? 1, team: (game.team ?? false) || (game.uneven_teams ?? false), unevenTeams: game.uneven_teams ?? false } }));
  }, [dispatch, intl, game.key, game.name, game.max_opponents, game.min_opponents, game.team, game.uneven_teams, game.daily_limit_message, game.busy, onBusy]);

  // 이벤트가 열린 뒤: 내 방이 생기면 거기로, 아니면 잠깐 안내
  const afterOpened = useCallback(() => {
    setBusy(true);
    waitForSession(game.key, (info) => info.active[0]?.id ?? null)
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
  }, [game.key, onSent, history]);

  // 운영진이 웹에서 여는 이벤트는 모달(모집·고르기·테스트 플레이·취소), 그 밖에는 멘션 명령어
  const openEvent = useCallback((join = false) => {
    if (game.busy) {
      onBusy();
      return;
    }
    if (!join && game.web_open) {
      dispatch(openModal({ modalType: 'EVENT_OPEN', modalProps: { gameKey: game.key, name: game.name, minPlayers: game.event_min_players, maxPlayers: game.event_max_players, joinMinutes: game.event_join_minutes, onOpened: afterOpened } }));
      return;
    }
    setBusy(true);
    sendCommand(join ? { kind: game.key, join: true } : { kind: game.key })
      .then(afterOpened)
      .catch(() => {
        setBusy(false);
      });
  }, [dispatch, game.key, game.name, game.busy, game.web_open, game.event_min_players, game.event_max_players, game.event_join_minutes, afterOpened, onBusy]);

  // 운영진은 언제나 [이벤트 열기]가 보인다 (모집 중이어도, 내가 다른 방에 있어도): 여러 이벤트를 동시에 열 수 있다
  if (game.event && game.can_open && game.enabled) {
    return sent ? (
      <span className='system-start system-start--off'>
        <FormattedMessage id='system.game.sent' defaultMessage='Sent. The system will answer in a moment.' />
      </span>
    ) : (
      <button type='button' className='system-start' disabled={busy} onClick={() => { openEvent(); }}>
        <FormattedMessage id='system.game.open_event' defaultMessage='Open the event' />
      </button>
    );
  }

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

  // 열려 있는 이벤트: [이벤트 참가하기] → 진행중 탭의 방 목록으로 (방에 들어가 [참여하기])
  if (game.recruiting && !game.can_open) {
    return (
      <button type='button' className='system-start' onClick={() => { onRooms?.(); }}>
        <FormattedMessage id='system.game.join_event' defaultMessage='Join the event ({count} joined)' values={{ count: game.recruiting.count }} />
      </button>
    );
  }

  if (game.event && !game.can_open) {
    return (
      <span className='system-start system-start--off'>
        <FormattedMessage id='system.game.preparing' defaultMessage='Preparing' />
      </span>
    );
  }

  if (game.event) {
    return sent ? (
      <span className='system-start system-start--off'>
        <FormattedMessage id='system.game.sent' defaultMessage='Sent. The system will answer in a moment.' />
      </span>
    ) : (
      <button type='button' className='system-start' disabled={busy} onClick={() => { openEvent(); }}>
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

// 방 목록 카드: 참가자 아바타 · 이름 (VS) · 상태(턴·남은 시간 / 끝난 때). 내 방은 테마색 바탕.
// 끝난 판은 승리자 아바타에 금빛 테두리 + 왕관, 이름은 테마색. 패배자는 흐리게, 무승부는 '무' 표시
export const RoomList: React.FC<{ rows: SessionRow[]; onDelete?: (row: SessionRow) => void }> = ({ rows, onDelete }) => {
  const intl = useIntl();
  return (
    <ul className='system-room-list'>
      {rows.map((row) => {
        const mine = row.players.some((player) => player.me);
        const versus = row.players.length === 2;
        return (
          <li key={row.id} className={onDelete ? 'system-room-list__item system-room-list__item--deletable' : undefined}>
            <Link
              to={`/system/sessions/${row.id}`}
              className={`system-room-card system-room-card--${row.status}${mine ? ' system-room-card--mine' : ''}${versus ? '' : ' system-room-card--many'}`}
            >
              <span className='system-room-card__players'>
                {row.players.map((player, index) => (
                  <Fragment key={player.acct}>
                    {index > 0 && versus && <span className='system-room-card__vs'>VS</span>}
                    <span
                      className={[
                        'system-room-card__player',
                        player.result && `system-room-card__player--${player.result}`,
                        player.me && 'system-room-card__player--me',
                      ].filter(Boolean).join(' ')}
                    >
                      <span className='system-room-card__avatar'>
                        <img src={player.avatar} alt='' />
                        {player.result === 'win' && <span className='system-room-card__crown' aria-hidden><GameIcon name='crown' /></span>}
                      </span>
                      <span className='system-room-card__name'>{player.name}</span>
                      {player.result && player.result !== 'lose' && (
                        <span className={`system-room-card__result system-room-card__result--${player.result}`}>
                          {intl.formatMessage(messages[player.result])}
                        </span>
                      )}
                    </span>
                  </Fragment>
                ))}
              </span>

              <span className='system-room-card__side'>
                {row.test && <span className='system-room-card__lock' role='img' aria-label='test play' title='Test play'>🔒</span>}
                <span className='system-room-card__state'>
                  {row.status === 'finished' && row.finished_at ? (
                    <RelativeTimestamp timestamp={row.finished_at} />
                  ) : row.status === 'pending' ? (
                    <FormattedMessage id='system.game.pending' defaultMessage='Waiting for accept' />
                  ) : (
                    <FormattedMessage id='system.game.turn' defaultMessage='Turn {turn}' values={{ turn: row.turn }} />
                  )}
                </span>
                {row.status !== 'finished' && row.deadline_at && <Countdown until={row.deadline_at} className='system-room-card__time' />}
              </span>
            </Link>
            {onDelete && (
              <button
                type='button'
                className='system-room-list__delete'
                title={intl.formatMessage(messages.deleteRoom)}
                aria-label={intl.formatMessage(messages.deleteRoom)}
                onClick={() => { onDelete(row); }}
              >
                <GameIcon name='x' />
              </button>
            )}
          </li>
        );
      })}
    </ul>
  );
};

// 이벤트 방 목록 (여럿이 하는 컨텐츠): [모집중·진행중·완료 배지] | 참가 캐릭터 아바타(아래 이름) | 오른쪽: 모집 종료까지 / 라운드 / 끝난 때. 완료된 방은 승리자를 색으로 강조
const EventRoomList: React.FC<{ rows: SessionRow[]; onDelete?: (row: SessionRow) => void }> = ({ rows, onDelete }) => {
  const intl = useIntl();
  return (
    <ul className='event-room-list'>
      {rows.map((row) => {
        const recruiting = row.status === 'pending' || row.status === 'lobby';
        const finished = row.status === 'finished' || row.status === 'cancelled';
        const mode = recruiting || row.waiting ? 'recruiting' : finished ? 'finished' : 'running';
        return (
          <li key={row.id} className='event-room-list__item'>
            <Link to={`/system/sessions/${row.id}`} className={`event-room event-room--${mode}`}>
              <span className='event-room__badge'>
                {row.test && <span role='img' aria-label='test play' title='Test play'>🔒 </span>}
                {row.waiting
                  ? <FormattedMessage id='event.room.waiting_badge' defaultMessage='Waiting' />
                  : recruiting
                  ? <FormattedMessage id='event.room.recruiting' defaultMessage='Recruiting' />
                  : finished
                    ? <FormattedMessage id='event.room.finished' defaultMessage='Finished' />
                    : <FormattedMessage id='event.room.running' defaultMessage='In progress' />}
              </span>
              <span className='event-room__players'>
                {row.players.map((player) => (
                  <span key={player.acct} className={['event-room__player', player.result === 'win' && 'is-winner', player.me && 'is-me', player.waiting && 'is-waiting'].filter(Boolean).join(' ')}>
                    <img src={player.avatar} alt='' />
                    <span>{player.name}</span>
                    {player.waiting && <small><FormattedMessage id='event.room.waiting_badge' defaultMessage='Waiting' /></small>}
                  </span>
                ))}
              </span>
              <span className='event-room__side'>
                {recruiting && (row.deadline_at
                  ? <Countdown until={row.deadline_at} className='event-room__time' />
                  : <FormattedMessage id='event.room.waiting' defaultMessage='Waiting room' />)}
                {row.status === 'active' && <FormattedMessage id='event.room.round' defaultMessage='Round {round}' values={{ round: row.round ?? row.turn }} />}
                {finished && row.finished_at && <RelativeTimestamp timestamp={row.finished_at} />}
              </span>
            </Link>
            {onDelete && (
              <button type='button' className='system-room-list__delete' title={intl.formatMessage(messages.deleteRoom)} aria-label={intl.formatMessage(messages.deleteRoom)} onClick={() => { onDelete(row); }}>
                <GameIcon name='x' />
              </button>
            )}
          </li>
        );
      })}
    </ul>
  );
};

type Tab = 'rules' | 'ranking' | 'active' | 'recent';

// 주문 상성 삼각형: 화살표가 가리키는 쪽을 이긴다 (0 → 1 → 2 → 0)
const SpellTriangle: React.FC<{ nodes: string[] }> = ({ nodes }) => {
  const radius = 31;
  const points: [number, number][] = [[150, 36], [250, 158], [50, 158]];
  return (
    <svg className='spell-triangle' viewBox='0 0 300 196' role='img'>
      <defs>
        <marker id='spell-arrow' viewBox='0 0 10 10' refX='8' refY='5' markerWidth='7' markerHeight='7' orient='auto-start-reverse'>
          <path d='M0 0 L10 5 L0 10 z' className='spell-triangle__head' />
        </marker>
      </defs>
      {points.map(([x1, y1], index) => {
        const [x2, y2] = points[(index + 1) % 3] as [number, number];
        const length = Math.hypot(x2 - x1, y2 - y1);
        const ux = (x2 - x1) / length;
        const uy = (y2 - y1) / length;
        return (
          <line
            key={index}
            className='spell-triangle__arrow'
            x1={x1 + (ux * (radius + 3))}
            y1={y1 + (uy * (radius + 3))}
            x2={x2 - (ux * (radius + 7))}
            y2={y2 - (uy * (radius + 7))}
            markerEnd='url(#spell-arrow)'
          />
        );
      })}
      {points.map(([x, y], index) => (
        <g key={index} className='spell-triangle__node'>
          <circle cx={x} cy={y} r={radius} />
          <text x={x} y={y + 5} textAnchor='middle'>{nodes[index]}</text>
        </g>
      ))}
    </svg>
  );
};

// 규칙 · 역할 · 아이템 · 진행 방법 · 보상 (일반 화면과 스테이지 화면이 같이 쓴다)
export const RulesBody: React.FC<{ game: GameInfo }> = ({ game }) => (
  <>
          {/* 역할 소개: 룰 위에 역할마다 이야기 한 장 (도둑 지도·비밀의 방) */}
          {game.cast && game.cast.length > 0 && (
            <section className='system-section'>
              <h2 className='system-section__title'>
                <FormattedMessage id='system.game.cast' defaultMessage='Roles' />
              </h2>
              <div className='system-roles'>
                {game.cast.map((member) => (
                  <article key={member.name} className='system-role'>
                    <span className='system-role__badge'>{member.name}</span>
                    {member.lines.map((line) => <p key={line} className='system-role__story'>{line}</p>)}
                  </article>
                ))}
              </div>
            </section>
          )}

          {/* 룰: 알아야 할 규칙 (아이콘 + 제목 + 설명) */}
          {game.rules_text && game.rules_text.length > 0 && (
            <section className='system-section'>
              <h2 className='system-section__title'>
                <FormattedMessage id='system.game.rules' defaultMessage='Rules' />
              </h2>
              <ul className='system-rules'>
                {game.rules_text.map((rule) => (
                  <li key={rule.title} className='system-rule'>
                    <span className='system-rule__icon'><GameIcon name={rule.icon} /></span>
                    <div className='system-rule__body'>
                      <strong className='system-rule__title'>{rule.title}</strong>
                      <p className='system-rule__text'><CommandText text={rule.text} noEmoji /></p>
                      {rule.visual === 'triangle' && rule.nodes && rule.nodes.length === 3 && <SpellTriangle nodes={rule.nodes} />}
                      {rule.table && (
                        <table className='system-rule__table'>
                          <thead>
                            <tr>{rule.table.head.map((cell) => <th key={cell}>{cell}</th>)}</tr>
                          </thead>
                          <tbody>
                            {rule.table.rows.map((row) => (
                              <tr key={row.join('|')}>
                                {row.map((cell, index) => (index === 0 ? <th key={cell} scope='row'>{cell}</th> : <td key={cell}>{cell}</td>))}
                              </tr>
                            ))}
                          </tbody>
                        </table>
                      )}
                    </div>
                  </li>
                ))}
              </ul>
            </section>
          )}

          {/* 역할과 승리 조건: 역할마다 카드 하나 */}
          {game.roles && game.roles.length > 0 && (
            <section className='system-section'>
              <h2 className='system-section__title'>
                {game.roles.length > 1 || game.roles[0]?.name ? (
                  <FormattedMessage id='system.game.roles' defaultMessage='Roles and how to win' />
                ) : (
                  <FormattedMessage id='system.game.role_win' defaultMessage='How to win' />
                )}
              </h2>
              <div className='system-roles'>
                {game.roles.map((role, index) => (
                  <article key={role.name ?? index} className='system-role'>
                    {role.name && <span className='system-role__badge'>{role.name}</span>}
                    <div className='system-role__row system-role__row--win'>
                      <span className='system-role__label'><GameIcon name='tournament' /> <FormattedMessage id='system.game.role_win_label' defaultMessage='Win' /></span>
                      <span className='system-role__text'>
                        <CommandText text={role.win} noEmoji />
                        {role.win_notes && role.win_notes.length > 0 && (
                          <ul className='system-role__notes'>
                            {role.win_notes.map((note) => <li key={note}><CommandText text={note} noEmoji /></li>)}
                          </ul>
                        )}
                      </span>
                    </div>
                    {role.notes.length > 0 && (
                      <div className='system-role__row'>
                        <span className='system-role__label'><GameIcon name='star' /> <FormattedMessage id='system.game.role_notes' defaultMessage='Differences' /></span>
                        <ul className='system-role__notes'>
                          {role.notes.map((note) => <li key={note}><CommandText text={note} noEmoji /></li>)}
                        </ul>
                      </div>
                    )}
                  </article>
                ))}
              </div>
            </section>
          )}

          {/* 아이템: 아이콘 + 카드 */}
          {game.items && game.items.length > 0 && (
            <section className='system-section'>
              <h2 className='system-section__title'>
                <FormattedMessage id='system.game.role_items' defaultMessage='Items' />
              </h2>
              <div className='system-items'>
                {game.items.map((item) => (
                  <article key={item.name} className='system-item-card'>
                    <span className='system-item-card__icon'><GameIcon name={item.icon} /></span>
                    <div className='system-item-card__body'>
                      <div className='system-item-card__head'>
                        <CommandText text={`[${item.name}]`} noEmoji />
                        {item.count && <span className='system-item-card__count'>{item.count}</span>}
                      </div>
                      <p className='system-item-card__effect'>{item.effect}</p>
                    </div>
                  </article>
                ))}
              </div>
            </section>
          )}

          {/* 진행 방법: 한 줄씩, [명령어]는 배지 */}
          <section className='system-section'>
            <h2 className='system-section__title'>
              <FormattedMessage id='system.game.how_to_play' defaultMessage='How to play' />
            </h2>
            <ol className='system-steps'>
              {game.steps.map((step, index) => (
                <li key={step} className='system-steps__item'>
                  <span className='system-steps__number'>{index + 1}</span>
                  <span className='system-steps__text'><CommandText text={step} noEmoji /></span>
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
  </>
);

// 최다 승리 (최대 5명): 한 줄씩, 메달 + 승수 막대
export const RankingBody: React.FC<{ game: GameInfo }> = ({ game }) => {
  const topWins = game.ranking[0]?.wins || 1;
  return (
  <>
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
  );
};

const SystemGame: React.FC<{ multiColumn?: boolean }> = ({ multiColumn }) => {
  const intl = useIntl();
  const dispatch = useAppDispatch();
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

  // 운영진: 끝난 판의 기록과 관련 멘션을 모두 지운다 (되돌릴 수 없어 확인을 거친다)
  const handleDelete = useCallback((row: SessionRow) => {
    dispatch(openModal({
      modalType: 'CONFIRM',
      modalProps: {
        title: intl.formatMessage(messages.deleteTitle),
        message: intl.formatMessage(messages.deleteMessage),
        confirm: intl.formatMessage(messages.deleteConfirm),
        dangerous: true,
        onConfirm: () => {
          apiRequestDelete(`v1/system/sessions/${row.id}`)
            .then(() => { load(); return undefined; })
            .catch(() => undefined);
        },
      },
    }));
  }, [dispatch, intl, load]);

  const title = game?.name ?? intl.formatMessage(messages.title);
  const rooms = game && (tab === 'active' || tab === 'recent') ? game[tab] : [];

  // 여럿이 하는 컨텐츠: 어두운 스테이지 소개 화면 (왼쪽 큰 제목·메뉴, 오른쪽 내용)
  if (game?.group === 'group') {
    const stageTabs = [
      { key: 'rules', label: intl.formatMessage(messages.tabRules) },
      { key: 'ranking', label: intl.formatMessage(messages.tabRanking) },
      { key: 'active', label: intl.formatMessage(messages.tabActive), count: game.active.length },
      { key: 'recent', label: intl.formatMessage(messages.tabRecent) },
    ];
    const stageRooms = tab === 'active' ? game.active : game.recent;

    return (
      <StageIntro
        name={game.name}
        summary={game.summary}
        record={game.record}
        action={<StartButton game={game} onSent={load} onBusy={showBusy} />}
        notice={busyShown && game.busy && !game.my_session_id ? (
          <div className='system-busy' role='alert'>
            <span className='system-busy__text'><CommandText text={game.busy.message} noEmoji /></span>
            <Link to={`/system/sessions/${game.busy.session_id}`} className='system-busy__link'>
              {game.busy.name ? <FormattedMessage id='system.game.busy_room' defaultMessage='Go to {name}' values={{ name: game.busy.name }} /> : <FormattedMessage id='system.game.enter_room' defaultMessage='Go to my room' />}
            </Link>
          </div>
        ) : null}
        tabs={stageTabs}
        tab={tab}
        onTab={(next) => { setTab(next as Tab); }}
      >
        {tab === 'rules' && <div className='system-page system-game-page'><RulesBody game={game} /></div>}
        {tab === 'ranking' && <div className='system-page system-game-page'><RankingBody game={game} /></div>}
        {(tab === 'active' || tab === 'recent') && (stageRooms.length > 0 ? (
          <EventRoomList rows={stageRooms} onDelete={game.staff && tab === 'recent' ? handleDelete : undefined} />
        ) : (
          <p className='system-page__empty'>
            {tab === 'active' ? <FormattedMessage id='system.active.empty' defaultMessage='No game in progress.' /> : <FormattedMessage id='system.game.no_finished' defaultMessage='No finished games yet.' />}
          </p>
        ))}
      </StageIntro>
    );
  }

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
              <div className='system-game-page__intro'>
                <h2>{game.name}</h2>
                <p>{game.summary}</p>
                <div className='system-game-page__stats'>
                  <span className='system-game-page__stat system-game-page__stat--win'>
                    <strong>{game.record.win}</strong> <FormattedMessage id='system.record_win' defaultMessage='W' />
                  </span>
                  <span className='system-game-page__stat system-game-page__stat--lose'>
                    <strong>{game.record.lose}</strong> <FormattedMessage id='system.record_lose' defaultMessage='L' />
                  </span>
                  <span className='system-game-page__stat'>
                    <strong>{game.record.draw}</strong> <FormattedMessage id='system.record_draw' defaultMessage='D' />
                  </span>
                </div>
              </div>
              <StartButton game={game} onSent={load} onBusy={showBusy} />
            </header>

            {/* 동시 진행을 막았을 때: [시작하기]를 누르면 신청하지 않고 바로 안내 */}
            {busyShown && game.busy && !game.my_session_id && (
              <div className='system-busy' role='alert'>
                <span className='system-busy__text'><CommandText text={game.busy.message} noEmoji /></span>
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
              <RulesBody game={game} />
              <RankingBody game={game} />
            </>
            ) : rooms.length > 0 ? (
              <RoomList rows={rooms} onDelete={game.staff && tab === 'recent' ? handleDelete : undefined} />
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
