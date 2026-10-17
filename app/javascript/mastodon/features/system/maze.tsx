// 트라이위저드 미로 (웹 전용) 진행판: 그래픽 지도. 내 시야만 보이고, 지나온 길은 기록된다.
// 이동할 수 있는 칸이 표시되고, 누르면 시스템에게 DM 으로 자동 전송된다 (마법 결투 주문 고르기와 같은 방식).
// 주문·협력/방해 고르기는 방 입력창 위 버튼(카드 행동)에서 한다.
// 서버: Game::Web::Maze#view_for (GET /api/v1/system/sessions/:id/view), 명령은 POST /api/v1/system/commands
import { useCallback, useEffect, useMemo, useState } from 'react';

import { FormattedMessage } from 'react-intl';

import { apiRequestGet, apiRequestPost } from 'mastodon/api';
import { GameIcon } from 'mastodon/components/game_icons';

import { BoardHeader } from './board_header';

type Dir = 'N' | 'E' | 'S' | 'W';

const DIRS: Record<Dir, { dx: number; dy: number; bit: number; name: string }> = {
  N: { dx: 0, dy: -1, bit: 1, name: '북' },
  E: { dx: 1, dy: 0, bit: 2, name: '동' },
  S: { dx: 0, dy: 1, bit: 4, name: '남' },
  W: { dx: -1, dy: 0, bit: 8, name: '서' },
};

interface Cell { x: number; y: number }

interface MazePerson {
  seat: number;
  name: string;
  account_id: string;
  avatar?: string | null;
  stunned: number;
  boost: boolean;
  lumos: number;
  x?: number;
  y?: number;
}

interface MazeView {
  width: number;
  height: number;
  me: number | null;
  position: [number, number] | null;
  players: MazePerson[];
  trails?: Record<string, [number, number][]>;
  hostile?: string[];
  revealed: boolean;
  spectator?: boolean;
  max_turns: number;
  status: string;
  cells: Record<string, number>;
  visible: number[];
  cup: [number, number] | null;
  hint: { direction: string; turn: number } | null;
  reachable: { x: number; y: number; path: Dir[] }[];
  creatures: { x: number; y: number; name: string }[];
  traps: Cell[];
  others: { seat: number; name: string; x: number; y: number; hostile: boolean }[];
  inventory: { portkey: number; lumos: number };
  planned: Dir[] | null;
  commands: Record<string, string>;
  item_info: Record<string, string>;
  steps: number;
  vision: number;
  stunned: number;
  lumos: number;
  phase: 'move' | 'fight' | 'meet';
  need: ('spell' | 'stance')[];
  fight: string | null;
  meet: string[];
  submitted: boolean;
  waiting: string[];
  turn: number;
  deadline_at: string | null;
}

interface ViewResponse {
  web: boolean;
  status: string;
  view: MazeView | null;
}

const REFRESH_MS = 10_000;
const CELL = 36;
const PAD = 4;
const OTHER_COLORS = ['#e0603c', '#3f7fd0', '#8a58c9', '#2f9e8f'];

export const MazePlay: React.FC<{ sessionId: string; onMoved?: () => void }> = ({ sessionId, onMoved }) => {
  const [view, setView] = useState<MazeView | null>(null);
  const [busy, setBusy] = useState(false);

  const load = useCallback(() => {
    apiRequestGet<ViewResponse>(`v1/system/sessions/${sessionId}/view`)
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

  const reachable = useMemo(() => new Map((view?.reachable ?? []).map((cell) => [`${cell.x},${cell.y}`, cell.path])), [view]);

  // 이번 턴에 정한 길 (내 위치에서 이어지는 칸들)
  const plannedCells = useMemo(() => {
    if (!view?.planned?.length || !view.position) return [];
    let [x, y] = view.position;
    return view.planned.map((dir) => {
      x += DIRS[dir].dx;
      y += DIRS[dir].dy;
      return { x, y };
    });
  }, [view]);

  if (!view) return null;

  const { width, height } = view;
  const visible = new Set(view.visible);
  const center = (x: number, y: number) => [PAD + (x * CELL) + (CELL / 2), PAD + (y * CELL) + (CELL / 2)] as const;
  const canMove = !view.revealed && view.phase === 'move' && view.stunned === 0;
  const at = <T extends Cell>(list: T[], x: number, y: number) => list.find((item) => item.x === x && item.y === y);
  const lastPlanned = plannedCells[plannedCells.length - 1];
  const cmd = view.commands;

  const handleMove = (path: Dir[]) => {
    if (busy || !canMove) return;
    send(cmd.move ?? '이동', path.map((dir) => DIRS[dir].name).join('/'));
  };

  const status = () => {
    if (view.phase === 'fight' && view.need.includes('spell')) {
      return <FormattedMessage id='maze.fight' defaultMessage='You met {creature}! Choose a spell with the buttons below.' values={{ creature: view.fight ?? '' }} />;
    }
    if (view.phase === 'meet' && view.need.includes('spell')) {
      return <FormattedMessage id='maze.meet_hostile' defaultMessage='You met a hostile rival! Choose a spell with the buttons below.' />;
    }
    if (view.phase === 'meet' && view.need.includes('stance')) {
      return <FormattedMessage id='maze.meet' defaultMessage='You met {names}. Choose cooperate or hinder with the buttons below.' values={{ names: view.meet.join(', ') }} />;
    }
    if (view.phase !== 'move') {
      return <FormattedMessage id='maze.wait_others' defaultMessage='Waiting for: {names}' values={{ names: view.waiting.join(', ') || '-' }} />;
    }
    if (view.stunned > 0) {
      return <FormattedMessage id='maze.stunned' defaultMessage='You are resting this turn.' />;
    }
    if (view.submitted) {
      return <FormattedMessage id='maze.sent' defaultMessage='Move sent. Waiting for: {names}. Tap another square to change it.' values={{ names: view.waiting.join(', ') || '-' }} />;
    }
    return <FormattedMessage id='maze.pick' defaultMessage='Tap a highlighted square to move (up to {steps} squares).' values={{ steps: view.steps }} />;
  };

  return (
    <div className='maze-play'>
      <BoardHeader
        icon='compass'
        title={<FormattedMessage id='maze.turn' defaultMessage='Turn {turn}' values={{ turn: view.turn }} />}
        subtitle={<FormattedMessage id='maze.turns_max' defaultMessage='up to {max} turns' values={{ max: view.max_turns }} />}
        deadline={view.status === 'active' ? view.deadline_at : null}
        people={view.players.map((person) => ({ key: person.seat, name: person.name, avatar: person.avatar, out: person.stunned > 0 }))}
        peopleNote={view.status === 'finished' ? <FormattedMessage id='maze.finished' defaultMessage='Finished' /> : <FormattedMessage id='maze.live' defaultMessage='Live' />}
      />

      {!view.revealed && (view.stunned > 0 || view.lumos > 0 || view.hint) && (
        <div className='maze-play__head'>
          {view.stunned > 0 && <span className='maze-play__chip maze-play__chip--bad'><GameIcon name='stun' /> {view.stunned}</span>}
          {view.lumos > 0 && <span className='maze-play__chip'><GameIcon name='bulb' /> {view.lumos}</span>}
          {view.hint && (
            <span className='maze-play__chip' title={cmd.portkey}>
              <GameIcon name='compass' /> <span className='maze-play__arrow'>{view.hint.direction}</span>
            </span>
          )}
        </div>
      )}

      <svg className='maze-play__svg' viewBox={`0 0 ${(width * CELL) + (PAD * 2)} ${(height * CELL) + (PAD * 2)}`} role='img'>
        <rect className='maze-play__fog' x={0} y={0} width={(width * CELL) + (PAD * 2)} height={(height * CELL) + (PAD * 2)} />

        {Object.keys(view.cells).map((key) => {
          const index = Number(key);
          const x = index % width;
          const y = Math.floor(index / width);
          const lit = visible.has(index);
          const move = canMove ? reachable.get(`${x},${y}`) : undefined;
          return (
            <rect
              key={key}
              className={['maze-play__floor', lit ? 'maze-play__floor--lit' : 'maze-play__floor--memory'].filter(Boolean).join(' ')}
              x={PAD + (x * CELL)}
              y={PAD + (y * CELL)}
              width={CELL}
              height={CELL}
              onClick={move ? () => { handleMove(move); } : undefined}
            />
          );
        })}

        {/* 이번 턴에 정한 길 */}
        {plannedCells.length > 0 && (
          <polyline
            className='maze-play__route'
            points={[view.position, ...plannedCells.map((cell) => [cell.x, cell.y] as [number, number])].map(([x, y]) => center(x, y).join(',')).join(' ')}
          />
        )}

        {/* 갈 수 있는 칸 */}
        {canMove && view.reachable.map((cell) => {
          const [cx, cy] = center(cell.x, cell.y);
          const planned = lastPlanned && lastPlanned.x === cell.x && lastPlanned.y === cell.y;
          return (
            <g
              key={`r${cell.x},${cell.y}`}
              className={planned ? 'maze-play__move maze-play__move--planned' : 'maze-play__move'}
              role='button'
              tabIndex={0}
              aria-label={`${cell.x},${cell.y}`}
              onClick={() => { handleMove(cell.path); }}
              onKeyDown={(event) => { if (event.key === 'Enter' || event.key === ' ') handleMove(cell.path); }}
            >
              <rect x={PAD + (cell.x * CELL) + 2} y={PAD + (cell.y * CELL) + 2} width={CELL - 4} height={CELL - 4} rx={6} />
              <circle cx={cx} cy={cy} r={4} />
            </g>
          );
        })}

        {/* 벽 */}
        <g className='maze-play__walls'>
          {Object.entries(view.cells).flatMap(([key, bits]) => {
            const index = Number(key);
            const x = index % width;
            const y = Math.floor(index / width);
            const x0 = PAD + (x * CELL);
            const y0 = PAD + (y * CELL);
            const lines: React.ReactElement[] = [];
            if ((bits & DIRS.N.bit) === 0) lines.push(<line key={`${key}n`} x1={x0} y1={y0} x2={x0 + CELL} y2={y0} />);
            if ((bits & DIRS.E.bit) === 0) lines.push(<line key={`${key}e`} x1={x0 + CELL} y1={y0} x2={x0 + CELL} y2={y0 + CELL} />);
            if ((bits & DIRS.S.bit) === 0) lines.push(<line key={`${key}s`} x1={x0} y1={y0 + CELL} x2={x0 + CELL} y2={y0 + CELL} />);
            if ((bits & DIRS.W.bit) === 0) lines.push(<line key={`${key}w`} x1={x0} y1={y0} x2={x0} y2={y0 + CELL} />);
            return lines;
          })}
        </g>

        {/* 우승컵·함정·마법 생물 */}
        {view.cup && <GameIcon className='maze-play__cup' name='tournament' x={PAD + (view.cup[0] * CELL) + 5} y={PAD + (view.cup[1] * CELL) + 5} size={CELL - 10} />}
        {view.traps.map((trap) => (
          <GameIcon key={`t${trap.x},${trap.y}`} className='maze-play__trap' name='stun' x={PAD + (trap.x * CELL) + 8} y={PAD + (trap.y * CELL) + 8} size={CELL - 16} />
        ))}
        {view.creatures.map((creature) => (
          <g key={`c${creature.x},${creature.y}`}>
            <title>{creature.name}</title>
            <GameIcon className='maze-play__creature' name='foot' x={PAD + (creature.x * CELL) + 6} y={PAD + (creature.y * CELL) + 6} size={CELL - 12} />
          </g>
        ))}

        {/* 지나온 길 (관전·끝난 판) */}
        {view.revealed && Object.entries(view.trails ?? {}).map(([seat, trail]) => (
          <polyline
            key={`trail${seat}`}
            className='maze-play__trail'
            style={{ stroke: OTHER_COLORS[Number(seat) % OTHER_COLORS.length] }}
            points={trail.map(([x, y]) => center(x, y).join(',')).join(' ')}
          />
        ))}

        {/* 사람 */}
        {view.revealed ? view.players.map((person) => {
          if (person.x === undefined || person.y === undefined) return null;
          const [cx, cy] = center(person.x, person.y);
          const mine = person.seat === view.me;
          return (
            <g key={person.seat} className='maze-play__token'>
              <title>{person.name}</title>
              {mine && <circle className='maze-play__me-ring' cx={cx} cy={cy} r={15} />}
              <circle cx={cx + 3} cy={cy - 3} r={11} style={{ fill: OTHER_COLORS[person.seat % OTHER_COLORS.length] }} />
              <text x={cx + 3} y={cy + 1} textAnchor='middle'>{[...person.name][0]}</text>
              {person.stunned > 0 && <GameIcon className='maze-play__trap' name='stun' x={cx + 8} y={cy - 20} size={12} />}
            </g>
          );
        }) : (
          <>
            {view.others.map((other) => {
              const [cx, cy] = center(other.x, other.y);
              return (
                <g key={other.seat} className={other.hostile ? 'maze-play__token maze-play__token--hostile' : 'maze-play__token'}>
                  <title>{other.name}</title>
                  <circle cx={cx + 5} cy={cy - 5} r={9} style={{ fill: OTHER_COLORS[other.seat % OTHER_COLORS.length] }} />
                  <text x={cx + 5} y={cy - 1} textAnchor='middle'>{[...other.name][0]}</text>
                  {other.hostile && <GameIcon className='maze-play__hostile' name='sword' x={cx + 8} y={cy - 18} size={12} />}
                </g>
              );
            })}
            {view.position && (() => {
              const [cx, cy] = center(view.position[0], view.position[1]);
              return (
                <g className='maze-play__token maze-play__token--me'>
                  <circle className='maze-play__me-ring' cx={cx} cy={cy} r={14} />
                  <circle cx={cx} cy={cy} r={9} />
                </g>
              );
            })()}
          </>
        )}
      </svg>

      <div className='maze-play__foot'>
        <p className='maze-play__hint'>
          {view.revealed ? (
            view.status === 'finished'
              ? <FormattedMessage id='maze.replay' defaultMessage='Finished game: the whole maze and every path are shown.' />
              : <FormattedMessage id='maze.watching' defaultMessage='Spectating: every position is shown live.' />
          ) : status()}
        </p>
        {!view.revealed && <div className='maze-play__items'>
          <button
            type='button'
            className='maze-play__item'
            title={view.item_info.portkey}
            disabled={busy || view.phase !== 'move' || view.inventory.portkey <= 0}
            onClick={() => { send(cmd.portkey ?? '포트키'); }}
          >
            <GameIcon name='compass' /> {cmd.portkey} <span className='maze-play__count'>{view.inventory.portkey}</span>
          </button>
          <button
            type='button'
            className='maze-play__item'
            title={view.item_info.lumos}
            disabled={busy || view.phase !== 'move' || view.inventory.lumos <= 0}
            onClick={() => { send(cmd.lumos ?? '루모스'); }}
          >
            <GameIcon name='bulb' /> {cmd.lumos} <span className='maze-play__count'>{view.inventory.lumos}</span>
          </button>
        </div>}
      </div>
    </div>
  );
};
