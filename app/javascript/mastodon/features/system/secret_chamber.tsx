// 비밀의 방 (마피아형) 진행판: 아바타 원탁, 투표 현황, 석화·퇴학 표시, 내 역할 카드, 방주 비밀 단톡, 예언·조사 기록 노트.
// 고발은 공개, 밤 행동은 시스템에게 DM 으로 자동 전송된다 (지도 컨텐츠와 같은 방식).
// 서버: Game::Events::SecretChamber#view_for (GET /api/v1/system/sessions/:id/view), 명령은 POST /api/v1/system/commands
import { useCallback, useEffect, useMemo, useState } from 'react';

import { FormattedMessage } from 'react-intl';

import { apiRequestGet, apiRequestPost } from 'mastodon/api';
import { GameIcon } from 'mastodon/components/game_icons';
import { RelativeTimestamp } from 'mastodon/components/relative_timestamp';

interface ChamberPlayer {
  seat: number;
  name: string;
  account_id: string;
  acct: string | null;
  avatar: string | null;
  alive: boolean;
  out: { by: string; day: number; role_name: string; faction: string; dark: boolean } | null;
  role_name: string | null;
  dark: boolean | null;
  votes: number;
  voted_by: string[];
}

interface ChamberView {
  phase: 'recruit' | 'day' | 'night' | 'finished' | null;
  day: number;
  phase_no: number;
  max_phases: number;
  deadline_at: string | null;
  ends_at: string | null;
  status: string;
  winner: 'light' | 'dark' | 'draw' | null;
  me: number;
  alive_me: boolean;
  players: ChamberPlayer[];
  my_role: { key: string; name: string; faction: string; dark: boolean; how: string; mates: number[] } | null;
  my_vote: number | null;
  votes: Record<string, number>;
  night: { kind: 'petrify' | 'investigate' | 'protect'; picked: number | null; used?: boolean; blocked?: number | null } | null;
  notes: { day: number; text: string }[];
  dark_chat: { name: string; text: string }[];
  prophecy: string | null;
  commands: Record<string, string>;
  min_players: number;
  max_players: number;
}

const REFRESH_MS = 10_000;

export const ChamberPlay: React.FC<{ sessionId: string; onMoved?: () => void }> = ({ sessionId, onMoved }) => {
  const [view, setView] = useState<ChamberView | null>(null);
  const [selected, setSelected] = useState<number | null>(null);
  const [busy, setBusy] = useState(false);
  const [chat, setChat] = useState('');
  const [prophecy, setProphecy] = useState('');

  const load = useCallback(() => {
    apiRequestGet<{ view: ChamberView | null }>(`v1/system/sessions/${sessionId}/view`)
      .then((response) => {
        setView(response.view);
        return response;
      })
      .catch(() => {
        setView(null);
      });
  }, [sessionId]);

  useEffect(() => {
    load();
    const timer = window.setInterval(load, REFRESH_MS);
    return () => {
      window.clearInterval(timer);
    };
  }, [load]);

  // 보낸 뒤 시스템이 처리하는 걸 잠시 기다렸다가 다시 읽는다
  const send = useCallback(
    (command: string, options: { target?: string | null; args?: string; dm: boolean }) => {
      setBusy(true);
      apiRequestPost('v1/system/commands', { session_id: sessionId, command, args: options.args, target: options.target ?? undefined, dm: options.dm })
        .catch(() => undefined)
        .finally(() => {
          setBusy(false);
          [1200, 3500].forEach((delay) => {
            window.setTimeout(() => {
              load();
              onMoved?.();
            }, delay);
          });
        });
    },
    [sessionId, load, onMoved],
  );

  const total = view?.players.length ?? 0;
  const size = Math.min(14, Math.max(8.5, 120 / Math.max(total, 1)));
  const positions = useMemo(
    () => Array.from({ length: total }, (_, index) => {
      const angle = (-Math.PI / 2) + ((index / Math.max(total, 1)) * Math.PI * 2);
      return { x: 50 + (Math.cos(angle) * 36), y: 50 + (Math.sin(angle) * 36) };
    }),
    [total],
  );

  if (!view) return null;

  const cmd = view.commands;
  const target = view.players.find((player) => player.seat === selected) ?? null;
  const byPlayer = new Map(view.players.map((player) => [player.seat, player]));
  const alivePlayers = view.players.filter((player) => player.alive);
  const night = view.night;
  const playing = view.phase === 'day' || view.phase === 'night';
  const dark = view.my_role?.dark ?? false;

  const handleChat = (event: React.FormEvent) => {
    event.preventDefault();
    const text = chat.trim();
    if (!text) return;
    send(cmd.chat ?? '밀담', { args: text, dm: true });
    setChat('');
  };

  const handleProphecy = (event: React.FormEvent) => {
    event.preventDefault();
    const text = prophecy.trim();
    if (!text) return;
    send(cmd.prophecy ?? '예언', { args: text, dm: true });
    setProphecy('');
  };

  // 지금 고를 수 있는 행동 (고른 아바타 기준)
  const action = (() => {
    if (!target || !view.alive_me || !target.alive) return null;
    if (view.phase === 'day') {
      return target.seat === view.me ? null : { command: cmd.accuse ?? '고발', dm: false, label: `${cmd.accuse}: ${target.name}`, done: view.my_vote === target.seat };
    }
    if (view.phase === 'night' && night) {
      const command = { petrify: cmd.petrify, investigate: cmd.investigate, protect: cmd.protect }[night.kind] ?? '';
      const blocked = night.kind === 'protect' && night.blocked === target.seat;
      const selfPick = night.kind !== 'protect' && target.seat === view.me;
      if (blocked || selfPick || (night.kind === 'investigate' && night.used)) return null;
      return { command, dm: true, label: `${command}: ${target.name}`, done: night.picked === target.seat };
    }
    return null;
  })();

  return (
    <div className='chamber-play'>
      {/* 맨 위 고정 헤더: 지금 페이즈(낮/밤) · 시간 · 참가자 */}
      <div className='chamber-head'>
        <div className='chamber-head__phase'>
          <span className={view.phase === 'night' ? 'chamber-head__icon chamber-head__icon--night' : 'chamber-head__icon'}>
            <GameIcon name={view.phase === 'night' ? 'moon' : 'sun'} />
          </span>
          <div className='chamber-head__title'>
            <strong>
              {view.phase === 'day' && <FormattedMessage id='chamber.day' defaultMessage='Day {day}' values={{ day: view.day }} />}
              {view.phase === 'night' && <FormattedMessage id='chamber.night' defaultMessage='Night {day}' values={{ day: view.day }} />}
              {view.phase === 'recruit' && <FormattedMessage id='chamber.recruit' defaultMessage='Recruiting {count} / {min}-{max}' values={{ count: total, min: view.min_players, max: view.max_players }} />}
              {view.phase === 'finished' && <FormattedMessage id='chamber.finished' defaultMessage='Finished' />}
            </strong>
            {playing && <small><FormattedMessage id='chamber.phase' defaultMessage='Phase {no} / {max}' values={{ no: view.phase_no, max: view.max_phases }} /></small>}
          </div>
        </div>
        {playing && (
          <div className='chamber-head__time'>
            {view.deadline_at && <span><GameIcon name='hourglass' /> <RelativeTimestamp timestamp={view.deadline_at} futureDate /></span>}
            {view.ends_at && <small><FormattedMessage id='chamber.ends' defaultMessage='Ends' /> <RelativeTimestamp timestamp={view.ends_at} futureDate /></small>}
          </div>
        )}
        <div className='chamber-head__people'>
          <span className='chamber-head__avatars'>
            {view.players.map((player) => (
              <span key={player.seat} className={player.alive ? 'chamber-head__avatar' : 'chamber-head__avatar chamber-head__avatar--out'} title={player.name}>
                {player.avatar && <img src={player.avatar} alt='' />}
              </span>
            ))}
          </span>
          <small><FormattedMessage id='chamber.alive_of' defaultMessage='{alive} / {total} alive' values={{ alive: alivePlayers.length, total }} /></small>
        </div>
      </div>

      {/* 아바타 원탁 */}
      <div className={view.phase === 'night' ? 'chamber-play__table chamber-play__table--night' : 'chamber-play__table'}>
        <div className='chamber-play__disc' />

        {/* 고발 화살표: 누가 누구를 고발했는지 */}
        {view.phase === 'day' && (
          <svg className='chamber-play__arrows' viewBox='0 0 100 100' aria-hidden='true'>
            <defs>
              <marker id='chamber-arrow' viewBox='0 0 10 10' refX='7' refY='5' markerWidth='4' markerHeight='4' orient='auto-start-reverse'>
                <path d='M0 0 L10 5 L0 10 z' className='chamber-play__arrow-head' />
              </marker>
            </defs>
            {Object.entries(view.votes).map(([voter, targetSeat]) => {
              const from = positions[view.players.findIndex((player) => player.seat === Number(voter))];
              const to = positions[view.players.findIndex((player) => player.seat === targetSeat)];
              if (!from || !to) return null;
              const length = Math.hypot(to.x - from.x, to.y - from.y) || 1;
              const ux = (to.x - from.x) / length;
              const uy = (to.y - from.y) / length;
              const gap = size / 2 + 1;
              return (
                <line
                  key={voter}
                  className={Number(voter) === view.me ? 'chamber-play__arrow chamber-play__arrow--mine' : 'chamber-play__arrow'}
                  x1={from.x + (ux * gap)}
                  y1={from.y + (uy * gap)}
                  x2={to.x - (ux * gap)}
                  y2={to.y - (uy * gap)}
                  markerEnd='url(#chamber-arrow)'
                />
              );
            })}
          </svg>
        )}

        <div className='chamber-play__center'>
          {view.winner ? (
            <strong className='chamber-play__winner'>
              {view.winner === 'draw' ? <FormattedMessage id='chamber.draw' defaultMessage='Draw' /> : <FormattedMessage id='chamber.winner' defaultMessage='The {side} side wins' values={{ side: view.winner === 'dark' ? (view.players.find((player) => player.out?.dark)?.out?.faction ?? '') : (view.players.find((player) => player.out && !player.out.dark)?.out?.faction ?? '') }} />}
            </strong>
          ) : (
            <>
              <GameIcon name={view.phase === 'night' ? 'moon' : 'sun'} />
              <span><FormattedMessage id='chamber.alive' defaultMessage='{count} left' values={{ count: alivePlayers.length }} /></span>
            </>
          )}
        </div>

        {view.players.map((player, index) => {
          const at = positions[index];
          const isMe = player.seat === view.me;
          const classes = [
            'chamber-seat',
            !player.alive && 'chamber-seat--out',
            player.out?.by === 'petrify' && 'chamber-seat--petrified',
            (player.out?.by === 'vote' || player.out?.by === 'forfeit') && 'chamber-seat--expelled',
            isMe && 'chamber-seat--me',
            selected === player.seat && 'chamber-seat--selected',
            player.dark === true && 'chamber-seat--dark',
          ].filter(Boolean).join(' ');
          return (
            <button
              key={player.seat}
              type='button'
              className={classes}
              style={{ left: `${at?.x ?? 50}%`, top: `${at?.y ?? 50}%`, width: `${size}%` }}
              onClick={() => { setSelected(selected === player.seat ? null : player.seat); }}
              title={[player.name, player.out ? `${player.out.faction} · ${player.out.role_name}` : player.role_name, player.voted_by.length ? player.voted_by.join(', ') : null].filter(Boolean).join(' / ')}
            >
              <span className='chamber-seat__avatar'>
                {player.avatar && <img src={player.avatar} alt='' />}
                {player.out?.by === 'petrify' && <span className='chamber-seat__mark'><GameIcon name='stun' /></span>}
                {(player.out?.by === 'vote' || player.out?.by === 'forfeit') && <span className='chamber-seat__mark chamber-seat__mark--expelled'><GameIcon name='x' /></span>}
              </span>
              {player.votes > 0 && view.phase === 'day' && <span className='chamber-seat__votes'>{player.votes}</span>}
              {player.out && (
                <span className={player.out.by === 'petrify' ? 'chamber-seat__tag chamber-seat__tag--stone' : 'chamber-seat__tag chamber-seat__tag--expelled'}>
                  {player.out.by === 'petrify' ? <FormattedMessage id='chamber.petrified' defaultMessage='Petrified' /> : <FormattedMessage id='chamber.expelled' defaultMessage='Expelled' />}
                </span>
              )}
              <span className='chamber-seat__name'>{player.name}</span>
              {(player.out || player.role_name) && (
                <span className={(player.out?.dark ?? player.dark) ? 'chamber-seat__role chamber-seat__role--dark' : 'chamber-seat__role'}>
                  {player.out ? player.out.role_name : player.role_name}
                </span>
              )}
            </button>
          );
        })}
      </div>

      {/* 행동 */}
      {view.status !== 'finished' && playing && (
        <div className='chamber-play__actions'>
          {!view.alive_me ? (
            <p className='chamber-play__hint'><FormattedMessage id='chamber.spectate' defaultMessage='You are out. You can watch and see every role.' /></p>
          ) : (
            <>
              <p className='chamber-play__hint'>
                {view.phase === 'day' ? (
                  view.my_vote !== null ? (
                    <FormattedMessage id='chamber.my_vote' defaultMessage='Your accusation: {name}. Tap another seat to change it.' values={{ name: byPlayer.get(view.my_vote)?.name ?? '' }} />
                  ) : (
                    <FormattedMessage id='chamber.pick_day' defaultMessage='Tap a seat, then accuse. The most accused is expelled.' />
                  )
                ) : night ? (
                  <FormattedMessage id='chamber.pick_night' defaultMessage='Tap a seat to use your night power.' />
                ) : (
                  <FormattedMessage id='chamber.quiet_night' defaultMessage='Quiet night. Wait for the morning.' />
                )}
              </p>
              {action && (
                <button type='button' className='content-card__action' disabled={busy || action.done} onClick={() => { send(action.command, { target: target?.acct, dm: action.dm }); }}>
                  {action.label}
                </button>
              )}
            </>
          )}
        </div>
      )}

      {/* 내 역할 카드 */}
      {view.my_role && (
        <div className={dark ? 'chamber-card chamber-card--dark' : 'chamber-card'}>
          <div className='chamber-card__head'>
            <span className='chamber-card__role'>{view.my_role.name}</span>
            <span className='chamber-card__faction'>{view.my_role.faction}</span>
          </div>
          <p className='chamber-card__how'>{view.my_role.how}</p>
          {view.my_role.mates.length > 0 && (
            <p className='chamber-card__mates'>
              <FormattedMessage id='chamber.mates' defaultMessage='Allies' />: {view.my_role.mates.map((seat) => byPlayer.get(seat)?.name).filter(Boolean).join(', ')}
            </p>
          )}
        </div>
      )}

      {/* 기록 노트 (예언자 예언·오러 조사) */}
      {view.notes.length > 0 && (
        <div className='chamber-notes'>
          <strong><FormattedMessage id='chamber.notes' defaultMessage='Notes' /></strong>
          <ul>
            {view.notes.map((note, index) => <li key={`${note.day}-${index}`}><b>{note.day}</b> {note.text}</li>)}
          </ul>
        </div>
      )}

      {/* 방주 비밀 단톡 · 예언 정하기 */}
      {dark && view.alive_me && (
        <div className='chamber-chat'>
          <strong><FormattedMessage id='chamber.dark_chat' defaultMessage='Secret chat (allies only)' /></strong>
          <ul className='chamber-chat__log'>
            {view.dark_chat.slice(-8).map((line, index) => <li key={`${index}${line.name}`}><b>{line.name}</b> {line.text}</li>)}
          </ul>
          <form className='chamber-chat__form' onSubmit={handleChat}>
            <input value={chat} onChange={(event) => { setChat(event.target.value); }} maxLength={200} placeholder='…' />
            <button type='submit' className='chamber-chat__send' disabled={busy || chat.trim() === ''}><FormattedMessage id='chamber.send' defaultMessage='Send' /></button>
          </form>
          {view.phase === 'night' && (
            <form className='chamber-chat__form chamber-chat__form--prophecy' onSubmit={handleProphecy}>
              <input value={prophecy} onChange={(event) => { setProphecy(event.target.value); }} maxLength={200} placeholder={view.prophecy ?? ''} />
              <button type='submit' className='chamber-chat__send' disabled={busy || prophecy.trim() === ''}><GameIcon name='sparkle' /> <FormattedMessage id='chamber.send_prophecy' defaultMessage='Send prophecy' /></button>
            </form>
          )}
        </div>
      )}
    </div>
  );
};
