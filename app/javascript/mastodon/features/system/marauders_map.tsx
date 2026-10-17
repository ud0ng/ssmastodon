// 도둑 지도 (웹 전용) 진행판: 호그와트 방 그래프 지도. 갈 수 있는 방을 누르면 시스템에게 DM 으로 자동 전송된다.
// 학생 팀: 전체 지도 + 팀 위치 + 목표 장소 + 사감 위치 + 팀 채팅 / 사감 팀: 사감 위치 + 공개된 발자국·구역 기록 + 팀 채팅.
// 서버: Game::Web::MaraudersMap#view_for (GET /api/v1/system/sessions/:id/view), 명령은 POST /api/v1/system/commands
import { useCallback, useEffect, useState } from 'react';

import { FormattedMessage } from 'react-intl';

import { apiRequestGet, apiRequestPost } from 'mastodon/api';
import { GameIcon } from 'mastodon/components/game_icons';

import { AvatarClip, AvatarPin, BoardHeader, BoardTip, useBoardTip } from './board_header';
import type { MapGlyphName } from './map_glyphs';
import { MapGlyph } from './map_glyphs';

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
  student_name?: string;
  prefect_name?: string;
  position: number | null;
  players: { seat: number; name: string; account_id: string; avatar?: string | null; student: boolean }[];
  trail?: number[];
  revealed: boolean;
  spectator?: boolean;
  status: string;
  moves: number[];
  planned_room?: number | null;
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

const REFRESH_MS = 3_000;
// 한 칸(방 + 사이 길)의 크기. 방 사이 틈(GAP)에 복도·계단을 직선으로 그린다.
const CELL = 132;
const GAP = 30;
const INSET = GAP / 2;
const TILE = CELL - GAP;
const PAD = 12;

const CLUE_GLYPH: Record<string, MapGlyphName> = { footprint: 'foot', target: 'target', revelio: 'eye' };

// 범례 견본에 쓰는 작은 선
const LegendLine: React.FC<{ kind: 'corridor' | 'stairs' | 'secret' }> = ({ kind }) => (
  <svg className='map-legend__swatch' viewBox='0 0 40 16' width={40} height={16} aria-hidden>
    {kind === 'secret' ? (
      <>
        <path d='M4 12Q20 -4 36 12' className='map-play__secret-halo' />
        <path d='M4 12Q20 -4 36 12' className='map-play__secret' />
      </>
    ) : (
      <line x1={4} y1={8} x2={36} y2={8} className={kind === 'stairs' ? 'map-play__edge map-play__edge--stairs' : 'map-play__edge'} />
    )}
  </svg>
);

const LegendGlyph: React.FC<{ name: MapGlyphName }> = ({ name }) => (
  <svg className='map-legend__swatch map-legend__swatch--glyph' viewBox='0 0 20 20' width={20} height={20} aria-hidden>
    <MapGlyph name={name} x={1} y={1} size={18} />
  </svg>
);

export const MaraudersMapPlay: React.FC<{ sessionId: string; onMoved?: () => void }> = ({ sessionId, onMoved }) => {
  const [view, setView] = useState<MapView | null>(null);
  const [busy, setBusy] = useState(false);
  const [chat, setChat] = useState('');
  const board = useBoardTip();
  // 방을 누르면 서버 답을 기다리지 않고 바로 말이 그 방으로 간다 (턴이 바뀌면 지운다)
  const [chosen, setChosen] = useState<{ turn: number; room: number } | null>(null);

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
          load();
          [600, 2000].forEach((delay) => {
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
  const cmd = view.commands;
  const canPick = view.my_turn;
  const myRoom = (chosen && chosen.turn === view.turn ? chosen.room : null) ?? view.planned_room ?? view.position;
  const student = view.role === 'student';
  const prefect = view.role === 'prefect';
  const studentName = view.student_name ?? view.role_name;
  const prefectName = view.prefect_name ?? '';
  const trailPoints = (view.trail ?? []).map((id) => byId.get(id)).filter((room): room is Room => Boolean(room)).map((room) => center(room).join(','));
  const hasStairs = view.edges.some((edge) => edge.stairs);
  const hasFootprint = view.clues.some((clue) => clue.kind === 'footprint');

  // 이웃한 두 방 사이 틈에 그리는 직선 (가로 ㅡ / 세로 ㅣ). 이웃이 아니면 중심끼리 잇는다.
  const gapLine = (a: Room, b: Room) => {
    const [ax, ay] = center(a);
    const [bx, by] = center(b);
    const near = Math.abs(a.x - b.x) + Math.abs(a.y - b.y) === 1;
    if (!near) return { x1: ax, y1: ay, x2: bx, y2: by };
    const half = (CELL / 2) - INSET;
    if (a.y === b.y) {
      const dir = b.x > a.x ? 1 : -1;
      return { x1: ax + (dir * half), y1: ay, x2: bx - (dir * half), y2: by };
    }
    const dir = b.y > a.y ? 1 : -1;
    return { x1: ax, y1: ay + (dir * half), x2: bx, y2: by - (dir * half) };
  };

  // 비밀 통로: 두 방 안쪽에서 시작해 칸 위를 휘어 지나는 점선. 양 끝에 열쇠 구멍 표시.
  const secretPath = (a: Room, b: Room) => {
    const [ax, ay] = center(a);
    const [bx, by] = center(b);
    const dx = bx - ax;
    const dy = by - ay;
    const length = Math.hypot(dx, dy) || 1;
    const reach = (TILE / 2) - 14;
    const ux = dx / length;
    const uy = dy / length;
    // 방 이름(위)과 말(가운데)을 피해 아래쪽에 붙인다
    const low = (y: number, cy: number) => Math.max(y, cy + 18);
    const start = [ax + (ux * reach), low(ay + (uy * reach), ay)];
    const end = [bx - (ux * reach), low(by - (uy * reach), by)];
    const bow = Math.min(60, length * 0.18);
    const control = [(ax + bx) / 2 - (uy * bow), (ay + by) / 2 + (ux * bow)];
    return { start, end, d: `M${start[0]} ${start[1]} Q${control[0]} ${control[1]} ${end[0]} ${end[1]}` };
  };

  const handleRoom = (room: Room) => {
    if (!canPick) return;
    setChosen({ turn: view.turn, room: room.id });
    send(cmd.move ?? '이동', room.name);
  };

  const status = () => {
    if (!view.my_turn) {
      return <FormattedMessage id='map.wait_turn' defaultMessage='Waiting for: {names}' values={{ names: view.waiting.join(', ') || '-' }} />;
    }
    if (view.submitted) {
      return <FormattedMessage id='map.sent' defaultMessage='Sent. Waiting for: {names}. Tap another room to change it.' values={{ names: view.waiting.join(', ') || '-' }} />;
    }
    return null;
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

      {view.cloak > 0 && (
        <div className='maze-play__head'>
          <span className='maze-play__chip'><GameIcon name='cloak' /> {view.cloak}</span>
        </div>
      )}

      <div className='map-play__board' ref={board.wrapRef}>
      <svg className='map-play__svg' viewBox={`0 0 ${svgWidth} ${svgHeight}`} role='img'>
        <AvatarClip />
        <defs>
          <filter id='map-paper' x='0' y='0' width='100%' height='100%'>
            <feTurbulence type='fractalNoise' baseFrequency='0.9' numOctaves='3' seed='4' result='noise' />
            <feColorMatrix in='noise' type='matrix' values='0 0 0 0 0.45  0 0 0 0 0.32  0 0 0 0 0.16  0 0 0 0.22 0' />
          </filter>
          <radialGradient id='map-vignette' cx='50%' cy='50%' r='75%'>
            <stop offset='55%' stopColor='#6a4a22' stopOpacity='0' />
            <stop offset='100%' stopColor='#6a4a22' stopOpacity='0.38' />
          </radialGradient>
        </defs>
        <rect className='map-play__paper' x={0} y={0} width={svgWidth} height={svgHeight} rx={18} />
        <rect x={0} y={0} width={svgWidth} height={svgHeight} rx={18} filter='url(#map-paper)' pointerEvents='none' />
        <rect x={0} y={0} width={svgWidth} height={svgHeight} rx={18} fill='url(#map-vignette)' pointerEvents='none' />
        <rect className='map-play__frame' x={PAD / 2} y={PAD / 2} width={svgWidth - PAD} height={svgHeight - PAD} rx={14} />

        {/* 방 사이 틈의 복도(실선)와 움직이는 계단(점선) */}
        {view.edges.map((edge) => {
          const a = byId.get(edge.a);
          const b = byId.get(edge.b);
          if (!a || !b) return null;
          const line = gapLine(a, b);
          const title = edge.stairs ? '움직이는 계단' : '복도';
          const lines = edge.stairs ? ['점선 · 몇 턴마다 연결이 바뀝니다'] : ['방과 방을 잇는 길'];
          return (
            <g
              key={`${edge.a}-${edge.b}`}
              onMouseEnter={(event) => { board.api.show(event.currentTarget, `${title}: ${a.name} ↔ ${b.name}`, lines); }}
              onMouseLeave={board.api.hide}
            >
              <line {...line} className={edge.stairs ? 'map-play__edge map-play__edge--stairs' : 'map-play__edge'} />
              <line {...line} className='map-play__edge-hit' />
            </g>
          );
        })}

        {/* 학생이 지나온 길 (관전·끝난 판) */}
        {view.revealed && trailPoints.length > 1 && <polyline className='map-play__trail' points={trailPoints.join(' ')} />}

        {view.rooms.map((room) => {
          const x = PAD + (room.x * CELL) + INSET;
          const y = PAD + (room.y * CELL) + INSET;
          const mid = TILE / 2;
          const reachable = canPick && view.moves.includes(room.id);
          const here = room.id === view.position;
          const clue = lastClue.get(room.id);
          // 내 팀 말은 방금 고른 방에 바로 가 있다 (출발한 방에는 흐린 표시만)
          const follows = (token: Token) => (student ? token.student : token.me) && view.position !== null;
          const tokens = view.tokens.filter((token) => (follows(token) ? myRoom === room.id : token.room === room.id));
          const origin = view.position === room.id && myRoom !== room.id;
          const spread = tokens.length > 3 ? 22 : 30;
          return (
            <g
              key={room.id}
              className={['map-play__room', reachable && 'map-play__room--reachable', canPick && !reachable && 'map-play__room--dim', here && 'map-play__room--selected', targets.has(room.id) && 'map-play__room--target'].filter(Boolean).join(' ')}
              onClick={() => { if (reachable) handleRoom(room); }}
              onMouseEnter={(event) => {
                const lines = [
                  targets.has(room.id) ? (targets.get(room.id) ? '목표 장소 (다녀옴)' : '목표 장소') : null,
                  clue ? ({ footprint: '발자국이 남아 있습니다', target: '누군가 다녀간 흔적', revelio: '호메눔 레벨리오를 쓴 곳' }[clue.kind] ?? null) : null,
                  tokens.length > 0 ? `${tokens.map((token) => token.name).join(', ')}` : null,
                  reachable ? '눌러서 이동' : null,
                ].filter((line): line is string => Boolean(line));
                board.api.show(event.currentTarget, room.name, lines);
              }}
              onMouseLeave={board.api.hide}
            >
              <rect x={x} y={y} width={TILE} height={TILE} rx={8} />
              <text x={x + mid} y={y + 22} textAnchor='middle' className='map-play__name'>{room.name}</text>
              {origin && <circle className='map-play__origin' cx={x + mid} cy={y + mid} r={14} />}
              {targets.has(room.id) && <MapGlyph name={targets.get(room.id) ? 'visited' : 'target'} x={x + mid - 9} y={y + TILE - 28} size={18} />}
              {clue && CLUE_GLYPH[clue.kind] && <MapGlyph name={CLUE_GLYPH[clue.kind]} x={x + TILE - 24} y={y + 6} size={17} className={`map-glyph--${clue.kind}`} />}
              {tokens.map((token, index) => (
                <AvatarPin
                  key={token.seat}
                  x={x + mid + ((index - ((tokens.length - 1) / 2)) * spread)}
                  y={y + mid}
                  r={12}
                  name={token.name}
                  avatar={view.players.find((person) => person.seat === token.seat)?.avatar}
                  color={token.student ? '#c0392b' : '#2f5f8f'}
                  ring={token.student ? 'student' : token.me ? 'me' : null}
                  tip={board.api}
                  lines={[token.student ? studentName : prefectName]}
                />
              ))}
            </g>
          );
        })}

        {/* 비밀 통로: 칸 위에 점선으로 겹쳐 그린다 (학생 팀과 관전자만 보임) */}
        {view.secret.map((edge) => {
          const a = byId.get(edge.a);
          const b = byId.get(edge.b);
          if (!a || !b) return null;
          const path = secretPath(a, b);
          return (
            <g key={`s${edge.a}-${edge.b}`} className='map-play__secret-wrap'>
              <path d={path.d} className='map-play__secret-halo' />
              <path d={path.d} className='map-play__secret' />
              {[[path.start, a, b], [path.end, b, a]].map(([point, from, to]) => {
                const [px, py] = point as number[];
                const target = to as Room;
                return (
                  <g
                    key={(from as Room).id}
                    className='map-play__secret-end'
                    onMouseEnter={(event) => { board.api.show(event.currentTarget, '비밀 통로', [`${(from as Room).name} → ${target.name}`, '학생 팀만 쓸 수 있습니다']); }}
                    onMouseLeave={board.api.hide}
                  >
                    <circle cx={px} cy={py} r={11} />
                    <MapGlyph name='secret' x={px - 7} y={py - 7} size={14} />
                  </g>
                );
              })}
            </g>
          );
        })}
      </svg>
      <BoardTip tip={board.tip} />
      </div>

      {/* 범례: 지도 위 그림이 무엇인지 */}
      <ul className='map-legend'>
        <li><LegendLine kind='corridor' /><FormattedMessage id='map.legend.corridor' defaultMessage='Corridor' /></li>
        {hasStairs && <li><LegendLine kind='stairs' /><FormattedMessage id='map.legend.stairs' defaultMessage='Moving stairs (dotted, change every few turns)' /></li>}
        {(student || view.revealed) && <li><LegendLine kind='secret' /><FormattedMessage id='map.legend.secret' defaultMessage='Secret passage (student team only)' /></li>}
        <li><LegendGlyph name='target' /><FormattedMessage id='map.legend.target' defaultMessage='Goal room' /></li>
        {student || view.revealed ? <li><LegendGlyph name='visited' /><FormattedMessage id='map.legend.visited' defaultMessage='Visited' /></li> : null}
        {(hasFootprint || prefect || view.revealed) && <li><LegendGlyph name='foot' /><FormattedMessage id='map.legend.foot' defaultMessage='Footprints (left on the room where a secret passage ended)' /></li>}
        {prefect && <li><LegendGlyph name='eye' /><FormattedMessage id='map.legend.eye' defaultMessage='Revelio used here' /></li>}
      </ul>

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

      {/* 팀 채팅: 같은 팀(학생 팀·사감 팀)끼리만 보인다 */}
      {(student || prefect) && (
        <div className='map-play__chat'>
          <strong className='map-play__chat-title'>
            <FormattedMessage id='map.team_chat' defaultMessage='Team chat' />
          </strong>
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
