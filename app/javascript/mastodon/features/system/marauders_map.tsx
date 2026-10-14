// 도둑 지도 (웹 전용) 진행판: 호그와트 방 25개 지도, 갈 수 있는 방 고르기, 투명 망토(학생)·호메눔 레벨리오(사감).
// 서버: Game::Web::MaraudersMap#view_for / #submit_move!
import { useCallback, useEffect, useState } from 'react';

import { FormattedMessage } from 'react-intl';

import { apiRequestGet, apiRequestPost } from 'mastodon/api';
import { RelativeTimestamp } from 'mastodon/components/relative_timestamp';

interface Room { id: number; name: string; x: number; y: number }
interface Token { seat: number; name: string; room: number; student: boolean; me: boolean }
interface Clue { turn: number; kind: 'footprint' | 'target' | 'revelio' | 'zone'; room?: number; zone?: string }

interface MapView {
  map: true;
  rooms: Room[];
  edges: { a: number; b: number; stairs: boolean }[];
  secret: { a: number; b: number }[];
  role: 'student' | 'prefect';
  role_name: string;
  position: number;
  moves: number[];
  tokens: Token[];
  targets: { room: number; visited: boolean }[];
  clues: Clue[];
  cloak_available: boolean;
  cloak: number;
  revelio_available: boolean;
  submitted: boolean;
  waiting: string[];
  turn: number;
  max_turns: number;
  deadline_at: string | null;
}

const REFRESH_MS = 10_000;
const CELL = 120;
const PAD = 12;

const center = (room: Room) => [PAD + (room.x * CELL) + (CELL / 2), PAD + (room.y * CELL) + (CELL / 2)] as const;

export const MaraudersMapPlay: React.FC<{ sessionId: string; onMoved?: () => void }> = ({ sessionId, onMoved }) => {
  const [view, setView] = useState<MapView | null>(null);
  const [choice, setChoice] = useState<number | null>(null);
  const [special, setSpecial] = useState(false);
  const [busy, setBusy] = useState(false);

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

  useEffect(() => {
    load();
    const timer = window.setInterval(load, REFRESH_MS);
    return () => {
      window.clearInterval(timer);
    };
  }, [load]);

  const handleSubmit = useCallback(() => {
    if (!view) return;
    setBusy(true);
    const stance = special ? (view.role === 'student' ? 'cloak' : 'revelio') : '';
    apiRequestPost<{ view: MapView | null }>(`v1/system/sessions/${sessionId}/move`, { path: [String(choice ?? view.position)], stance })
      .then((response) => {
        setView(response.view);
        setChoice(null);
        setSpecial(false);
        onMoved?.();
        return response;
      })
      .finally(() => {
        setBusy(false);
      });
  }, [view, sessionId, choice, special, onMoved]);

  if (!view?.map) return null;

  const byId = new Map(view.rooms.map((room) => [room.id, room]));
  const width = (PAD * 2) + (CELL * 5);
  const targets = new Map(view.targets.map((target) => [target.room, target.visited]));
  const lastClue = new Map<number, Clue>();
  view.clues.forEach((clue) => {
    if (clue.room !== undefined) lastClue.set(clue.room, clue);
  });
  const zoneClue = [...view.clues].reverse().find((clue) => clue.kind === 'zone');
  const canPick = !view.submitted;

  return (
    <div className='map-play'>
      <div className='maze-play__head'>
        <strong>
          <FormattedMessage id='maze.turn' defaultMessage='Turn {turn}' values={{ turn: view.turn }} /> / {view.max_turns}
        </strong>
        <span className='map-play__role'>{view.role_name}</span>
        {view.deadline_at && <span>⏳ <RelativeTimestamp timestamp={view.deadline_at} futureDate /></span>}
        {view.cloak > 0 && <span>🧥 {view.cloak}</span>}
        {zoneClue && <span>🔭 {zoneClue.zone} ({zoneClue.turn})</span>}
      </div>

      <svg className='map-play__svg' viewBox={`0 0 ${width} ${width}`} role='img'>
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

        {view.rooms.map((room) => {
          const x = PAD + (room.x * CELL) + 8;
          const y = PAD + (room.y * CELL) + 8;
          const reachable = canPick && (view.moves.includes(room.id) || room.id === view.position);
          const selected = (choice ?? view.position) === room.id && canPick;
          const clue = lastClue.get(room.id);
          const tokens = view.tokens.filter((token) => token.room === room.id);
          return (
            <g
              key={room.id}
              className={['map-play__room', reachable && 'map-play__room--reachable', selected && 'map-play__room--selected', targets.has(room.id) && 'map-play__room--target'].filter(Boolean).join(' ')}
              onClick={() => { if (reachable) setChoice(room.id); }}
            >
              <rect x={x} y={y} width={CELL - 16} height={CELL - 16} rx={8} />
              <text x={x + ((CELL - 16) / 2)} y={y + 22} textAnchor='middle' className='map-play__name'>{room.name}</text>
              {targets.has(room.id) && <text x={x + ((CELL - 16) / 2)} y={y + 44} textAnchor='middle'>{targets.get(room.id) ? '✅' : '⭐'}</text>}
              {clue && (
                <text x={x + (CELL - 30)} y={y + 22} textAnchor='middle'>
                  {{ footprint: '👣', target: '✨', revelio: '🔦', zone: '' }[clue.kind]}
                </text>
              )}
              {tokens.map((token, index) => (
                <g key={token.seat}>
                  <circle cx={x + 18 + (index * 22)} cy={y + CELL - 38} r={9} className={token.student ? 'map-play__token map-play__token--student' : token.me ? 'map-play__token map-play__token--me' : 'map-play__token'} />
                  <title>{token.name}</title>
                </g>
              ))}
            </g>
          );
        })}
      </svg>

      <div className='maze-play__controls'>
        {view.submitted ? (
          <p>
            <FormattedMessage id='maze.submitted' defaultMessage='Move sent. Waiting for: {names}' values={{ names: view.waiting.join(', ') || '-' }} />
          </p>
        ) : (
          <>
            <p className='maze-play__hint'>
              <FormattedMessage id='map.hint' defaultMessage='Click a highlighted room next to you (or your own room to stay), then send.' />
            </p>
            <div className='maze-play__stance'>
              {view.cloak_available && (
                <button type='button' className={special ? 'maze-play__toggle maze-play__toggle--on' : 'maze-play__toggle'} onClick={() => { setSpecial(!special); }}>
                  🧥 <FormattedMessage id='map.cloak' defaultMessage='Invisibility cloak' />
                </button>
              )}
              {view.revelio_available && (
                <button type='button' className={special ? 'maze-play__toggle maze-play__toggle--on' : 'maze-play__toggle'} onClick={() => { setSpecial(!special); }}>
                  🔦 <FormattedMessage id='map.revelio' defaultMessage='Homenum Revelio' />
                </button>
              )}
            </div>
            <div className='maze-play__actions'>
              <button type='button' className='content-card__action' onClick={handleSubmit} disabled={busy}>
                {choice === null || choice === view.position ? (
                  <FormattedMessage id='maze.stay' defaultMessage='Stay here' />
                ) : (
                  <FormattedMessage id='map.go' defaultMessage='Go to {room}' values={{ room: byId.get(choice)?.name }} />
                )}
              </button>
            </div>
          </>
        )}
      </div>
    </div>
  );
};
