// 도둑 지도 (웹 전용) 진행판: 호그와트 방 그래프 지도. 갈 수 있는 방을 누르면 시스템에게 DM 으로 자동 전송된다.
// 학생: 전체 지도 + 내 위치 + 목표 장소 + 사감 위치 / 사감: 사감 위치 + 공개된 발자국·구역 기록.
// 서버: Game::Web::MaraudersMap#view_for (GET /api/v1/system/sessions/:id/view), 명령은 POST /api/v1/system/commands
import { useCallback, useEffect, useState } from 'react';

import { FormattedMessage } from 'react-intl';

import { apiRequestGet, apiRequestPost } from 'mastodon/api';
import { GameIcon } from 'mastodon/components/game_icons';

import { BoardHeader } from './board_header';

interface Room { id: number; name: string; x: number; y: number }
interface Token { seat: number; name: string; room: number; student: boolean; me: boolean }
interface Clue { turn: number; kind: 'footprint' | 'target' | 'revelio' | 'zone'; room?: number; zone?: string; found?: boolean }

interface MapView {
  map: true;
  width: number;
  height: number;
  rooms: Room[];
  edges: { a: number; b: number; stairs: boolean }[];
  secret: { a: number; b: number }[];
  role: 'student' | 'prefect' | 'spectator';
  role_name: string;
  position: number | null;
  players: { seat: number; name: string; account_id: string; avatar?: string | null; student: boolean }[];
  trail?: number[];
  revealed: boolean;
  spectator?: boolean;
  status: string;
  moves: number[];
  tokens: Token[];
  targets: { room: number; visited: boolean }[];
  clues: Clue[];
  team_chat: { name: string; text: string }[];
  items: { cloak?: number; revelio?: number };
  item_info: Record<string, string>;
  commands: Record<string, string>;
  phase: 'student' | 'prefects';
  my_turn: boolean;
  cloak: number;
  submitted: boolean;
  waiting: string[];
  turn: number;
  max_turns: number;
  deadline_at: string | null;
}

const REFRESH_MS = 10_000;
const CELL = 120;
const PAD = 12;

export const MaraudersMapPlay: React.FC<{ sessionId: string; onMoved?: () => void }> = ({ sessionId, onMoved }) => {
  const [view, setView] = useState<MapView | null>(null);
  const [busy, setBusy] = useState(false);
  const [chat, setChat] = useState('');

  const load = useCallback(() => {
    apiRequestGet<{ view: MapView | null }>(`v1/system/sessions/${sessionId}/view`)
      .then((response) => {
        setView(response.view);
        return response;
      })
      .catch(() => {
        setView(null);
      });
  }, [sessionId]);

  // 관전자는 더 자주 새로 읽어 실시간처럼 보이게 한다
  const spectating = view?.revealed ?? false;
  useEffect(() => {
    load();
    const timer = window.setInterval(load, spectating ? 4000 : REFRESH_MS);
    return () => {
      window.clearInterval(timer);
    };
  }, [load, spectating]);

  // 보낸 뒤 시스템이 처리하는 걸 잠시 기다렸다가 다시 읽는다
  const send = useCallback(
    (command: string, args?: string) => {
      setBusy(true);
      apiRequestPost('v1/system/commands', { session_id: sessionId, command, args, dm: true })
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

  const handleChat = (event: React.FormEvent) => {
    event.preventDefault();
    const text = chat.trim();
    if (!text || !view) return;
    send(view.commands.team ?? '팀채팅', text);
    setChat('');
  };

  if (!view?.map) return null;

  const center = (room: Room) => [PAD + (room.x * CELL) + (CELL / 2), PAD + (room.y * CELL) + (CELL / 2)] as const;
  const byId = new Map(view.rooms.map((room) => [room.id, room]));
  const svgWidth = (PAD * 2) + (CELL * view.width);
  const svgHeight = (PAD * 2) + (CELL * view.height);
  const targets = new Map(view.targets.map((target) => [target.room, target.visited]));
  const lastClue = new Map<number, Clue>();
  view.clues.forEach((clue) => {
    if (clue.room !== undefined && clue.kind !== 'zone') lastClue.set(clue.room, clue);
  });
  const zoneClue = [...view.clues].reverse().find((clue) => clue.kind === 'zone');
  const cmd = view.commands;
  const canPick = view.my_turn && !busy;
  const student = view.role === 'student';
  const prefect = view.role === 'prefect';
  const trailPoints = (view.trail ?? []).map((id) => byId.get(id)).filter((room): room is Room => Boolean(room)).map((room) => center(room).join(','));

  const handleRoom = (room: Room) => {
    if (!canPick) return;
    send(cmd.move ?? '이동', room.name);
  };

  const status = () => {
    if (!view.my_turn) {
      return <FormattedMessage id='map.wait_turn' defaultMessage='Waiting for: {names}' values={{ names: view.waiting.join(', ') || '-' }} />;
    }
    if (view.submitted) {
      return <FormattedMessage id='map.sent' defaultMessage='Sent. Waiting for: {names}. Tap another room to change it.' values={{ names: view.waiting.join(', ') || '-' }} />;
    }
    return <FormattedMessage id='map.pick' defaultMessage='Tap a highlighted room next to you to move, or stay hidden.' />;
  };

  return (
    <div className='map-play'>
      <BoardHeader
        icon='scope'
        title={<FormattedMessage id='maze.turn' defaultMessage='Turn {turn}' values={{ turn: view.turn }} />}
        subtitle={<>{view.role_name} · <FormattedMessage id='maze.turns_max' defaultMessage='up to {max} turns' values={{ max: view.max_turns }} /></>}
        deadline={view.status === 'active' ? view.deadline_at : null}
        people={view.players.map((person) => ({ key: person.seat, name: person.name, avatar: person.avatar }))}
        peopleNote={view.status === 'finished' ? <FormattedMessage id='maze.finished' defaultMessage='Finished' /> : <FormattedMessage id='maze.live' defaultMessage='Live' />}
      />

      {(view.cloak > 0 || zoneClue) && (
        <div className='maze-play__head'>
          {view.cloak > 0 && <span className='maze-play__chip'><GameIcon name='cloak' /> {view.cloak}</span>}
          {zoneClue && <span className='maze-play__chip'><GameIcon name='scope' /> {zoneClue.zone} ({zoneClue.turn})</span>}
        </div>
      )}

      <svg className='map-play__svg' viewBox={`0 0 ${svgWidth} ${svgHeight}`} role='img'>
        {view.edges.map((edge) => {
          const a = byId.get(edge.a);
          const b = byId.get(edge.b);
          if (!a || !b) return null;
          const [x1, y1] = center(a);
          const [x2, y2] = center(b);
          return <line key={`${edge.a}-${edge.b}`} x1={x1} y1={y1} x2={x2} y2={y2} className={edge.stairs ? 'map-play__edge map-play__edge--stairs' : 'map-play__edge'} />;
        })}
        {view.secret.map((edge) => {
          const a = byId.get(edge.a);
          const b = byId.get(edge.b);
          if (!a || !b) return null;
          const [x1, y1] = center(a);
          const [x2, y2] = center(b);
          return <line key={`s${edge.a}-${edge.b}`} x1={x1} y1={y1} x2={x2} y2={y2} className='map-play__edge map-play__edge--secret' />;
        })}

        {/* 학생이 지나온 길 (관전·끝난 판) */}
        {view.revealed && trailPoints.length > 1 && <polyline className='map-play__trail' points={trailPoints.join(' ')} />}

        {view.rooms.map((room) => {
          const x = PAD + (room.x * CELL) + 8;
          const y = PAD + (room.y * CELL) + 8;
          const reachable = canPick && view.moves.includes(room.id);
          const here = room.id === view.position;
          const clue = lastClue.get(room.id);
          const tokens = view.tokens.filter((token) => token.room === room.id);
          return (
            <g
              key={room.id}
              className={['map-play__room', reachable && 'map-play__room--reachable', here && 'map-play__room--selected', targets.has(room.id) && 'map-play__room--target'].filter(Boolean).join(' ')}
              onClick={() => { if (reachable) handleRoom(room); }}
            >
              <title>{room.name}</title>
              <rect x={x} y={y} width={CELL - 16} height={CELL - 16} rx={8} />
              <text x={x + ((CELL - 16) / 2)} y={y + 22} textAnchor='middle' className='map-play__name'>{room.name}</text>
              {targets.has(room.id) && <GameIcon name={targets.get(room.id) ? 'check' : 'star'} x={x + ((CELL - 16) / 2) - 9} y={y + 28} size={18} />}
              {clue && (
                <GameIcon name={{ footprint: 'foot', target: 'sparkle', revelio: 'bulb' }[clue.kind] ?? 'sparkle'} x={x + (CELL - 30) - 8} y={y + 6} size={16} />
              )}
              {tokens.map((token, index) => (
                <g key={token.seat}>
                  <title>{token.name}</title>
                  <circle cx={x + 18 + (index * 22)} cy={y + CELL - 38} r={9} className={token.student ? 'map-play__token map-play__token--student' : token.me ? 'map-play__token map-play__token--me' : 'map-play__token'} />
                </g>
              ))}
            </g>
          );
        })}
      </svg>

      <div className='maze-play__foot'>
        <p className='maze-play__hint'>
          {view.revealed ? (
            view.status === 'finished'
              ? <FormattedMessage id='maze.replay_map' defaultMessage='Finished game: every position and the escape route are shown.' />
              : <FormattedMessage id='maze.watching' defaultMessage='Spectating: every position is shown live.' />
          ) : status()}
        </p>
        {!view.revealed && <div className='maze-play__items'>
          <button
            type='button'
            className='maze-play__item'
            title='제자리에 머물러 이번 턴을 보냅니다.'
            disabled={!canPick}
            onClick={() => { send(cmd.hide ?? '숨기'); }}
          >
            {cmd.hide}
          </button>
          {student ? (
            <button
              type='button'
              className='maze-play__item'
              title={view.item_info.cloak}
              disabled={!canPick || (view.items.cloak ?? 0) <= 0}
              onClick={() => { send(cmd.cloak ?? '투명망토'); }}
            >
              <GameIcon name='cloak' /> {cmd.cloak} <span className='maze-play__count'>{view.items.cloak ?? 0}</span>
            </button>
          ) : (
            <button
              type='button'
              className='maze-play__item'
              title={view.item_info.revelio}
              disabled={!canPick || (view.items.revelio ?? 0) <= 0}
              onClick={() => { send(cmd.revelio ?? '레벨리오'); }}
            >
              <GameIcon name='bulb' /> {cmd.revelio} <span className='maze-play__count'>{view.items.revelio ?? 0}</span>
            </button>
          )}
        </div>}
      </div>

      {/* 사감 팀 채팅: 학생에게는 보이지 않는다 */}
      {prefect && (
        <div className='map-play__chat'>
          <strong className='map-play__chat-title'>
            <FormattedMessage id='map.team_chat' defaultMessage='Team chat' />
          </strong>
          <ul className='map-play__chat-log'>
            {view.team_chat.slice(-6).map((line, index) => (
              <li key={`${index}${line.name}`}><b>{line.name}</b> {line.text}</li>
            ))}
          </ul>
          <form className='map-play__chat-form' onSubmit={handleChat}>
            <input value={chat} onChange={(event) => { setChat(event.target.value); }} maxLength={200} placeholder='…' />
            <button type='submit' className='maze-play__item' disabled={busy || chat.trim() === ''}>
              <FormattedMessage id='map.team_chat_send' defaultMessage='Send' />
            </button>
          </form>
        </div>
      )}
    </div>
  );
};
