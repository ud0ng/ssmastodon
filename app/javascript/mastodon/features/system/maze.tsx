// 트라이위저드 미로 (웹 전용) 진행판: 내 시야의 미로, 이번 턴 경로 고르기, 태도(협력/방해), 내기.
// 서버: Game::Web::Maze#view_for / #submit_move! (GET/POST /api/v1/system/sessions/:id/view|move)
import { useCallback, useEffect, useMemo, useState } from 'react';

import { FormattedMessage } from 'react-intl';

import { apiRequestGet, apiRequestPost } from 'mastodon/api';
import { RelativeTimestamp } from 'mastodon/components/relative_timestamp';

type Dir = 'N' | 'E' | 'S' | 'W';

const DIRS: Record<Dir, [number, number, number]> = {
  N: [0, -1, 1],
  E: [1, 0, 2],
  S: [0, 1, 4],
  W: [-1, 0, 8],
};

interface MazeView {
  size: number;
  me: number;
  position: [number, number];
  cells: Record<string, number>;
  visible: number[];
  cup: [number, number] | null;
  cup_direction: string | null;
  items: { x: number; y: number; item: string; name: string }[];
  creatures: { x: number; y: number; name: string }[];
  others: { seat: number; name: string; x: number; y: number; hostile: boolean }[];
  steps: number;
  stunned: boolean;
  lumos: number;
  submitted: boolean;
  waiting: string[];
  turn: number;
  deadline_at: string | null;
  log: string[];
}

interface ViewResponse {
  web: boolean;
  status: string;
  view: MazeView | null;
}

const REFRESH_MS = 10_000;

export const MazePlay: React.FC<{ sessionId: string; onMoved?: () => void }> = ({ sessionId, onMoved }) => {
  const [data, setData] = useState<ViewResponse | null>(null);
  const [path, setPath] = useState<Dir[]>([]);
  const [stance, setStance] = useState<'cooperate' | 'hinder'>('cooperate');
  const [busy, setBusy] = useState(false);

  const load = useCallback(() => {
    apiRequestGet<ViewResponse>(`v1/system/sessions/${sessionId}/view`)
      .then((response) => {
        setData(response);
        return response;
      })
      .catch(() => {
        setData(null);
      });
  }, [sessionId]);

  useEffect(() => {
    load();
    const timer = window.setInterval(load, REFRESH_MS);
    return () => {
      window.clearInterval(timer);
    };
  }, [load]);

  const view = data?.view ?? null;

  // 고른 경로를 따라간 칸들
  const trail = useMemo(() => {
    if (!view) return [];
    const points: [number, number][] = [];
    let [x, y] = view.position;
    for (const dir of path) {
      x += DIRS[dir][0];
      y += DIRS[dir][1];
      points.push([x, y]);
    }
    return points;
  }, [view, path]);

  const handleCell = useCallback(
    (cx: number, cy: number) => {
      if (!view || view.submitted || view.stunned) return;
      const [x, y] = trail[trail.length - 1] ?? view.position;
      // 지금 끝 칸과 붙어 있고 벽이 없을 때만 한 칸 더
      const dir = (Object.keys(DIRS) as Dir[]).find((key) => x + DIRS[key][0] === cx && y + DIRS[key][1] === cy);
      if (!dir) return;
      const cell = view.cells[String((y * view.size) + x)] ?? 0;
      if ((cell & DIRS[dir][2]) === 0) return;
      // 한 칸 되돌아가면 경로를 줄인다
      const before = trail[trail.length - 2] ?? view.position;
      if (trail.length > 0 && before[0] === cx && before[1] === cy) {
        setPath((current) => current.slice(0, -1));
        return;
      }
      if (path.length >= view.steps) return;
      setPath((current) => [...current, dir]);
    },
    [view, trail, path],
  );

  const handleSubmit = useCallback(() => {
    setBusy(true);
    apiRequestPost<ViewResponse>(`v1/system/sessions/${sessionId}/move`, { path, stance })
      .then((response) => {
        setData(response);
        setPath([]);
        onMoved?.();
        return response;
      })
      .finally(() => {
        setBusy(false);
      });
  }, [sessionId, path, stance, onMoved]);

  if (!view) return null;

  const visible = new Set(view.visible);
  const trailKeys = new Set(trail.map(([x, y]) => `${x},${y}`));
  const at = (list: { x: number; y: number }[], x: number, y: number) => list.find((item) => item.x === x && item.y === y);

  return (
    <div className='maze-play'>
      <div className='maze-play__head'>
        <strong>
          <FormattedMessage id='maze.turn' defaultMessage='Turn {turn}' values={{ turn: view.turn }} />
        </strong>
        {view.deadline_at && (
          <span>⏳ <RelativeTimestamp timestamp={view.deadline_at} futureDate /></span>
        )}
        {view.cup_direction && (
          <span className='maze-play__compass' title='Point Me'>
            🧭 {view.cup_direction}
          </span>
        )}
        {view.lumos > 0 && <span>💡 {view.lumos}</span>}
      </div>

      <div className='maze-play__grid' style={{ '--maze-size': view.size } as React.CSSProperties}>
        {Array.from({ length: view.size * view.size }, (_, index) => {
          const x = index % view.size;
          const y = Math.floor(index / view.size);
          const known = view.cells[String(index)];
          const seen = known !== undefined;
          const lit = visible.has(index);
          const bits = known ?? 0;
          const me = view.position[0] === x && view.position[1] === y;
          const item = lit ? at(view.items, x, y) : undefined;
          const creature = lit ? at(view.creatures, x, y) : undefined;
          const other = at(view.others, x, y);
          const cup = view.cup && view.cup[0] === x && view.cup[1] === y;

          return (
            <button
              key={index}
              type='button'
              className={[
                'maze-play__cell',
                !seen && 'maze-play__cell--fog',
                seen && !lit && 'maze-play__cell--memory',
                trailKeys.has(`${x},${y}`) && 'maze-play__cell--trail',
                (bits & 1) === 0 && 'maze-play__cell--wall-n',
                (bits & 2) === 0 && 'maze-play__cell--wall-e',
                (bits & 4) === 0 && 'maze-play__cell--wall-s',
                (bits & 8) === 0 && 'maze-play__cell--wall-w',
              ].filter(Boolean).join(' ')}
              onClick={() => { handleCell(x, y); }}
              tabIndex={-1}
              aria-label={`${x},${y}`}
            >
              {me && <span className='maze-play__token maze-play__token--me'>●</span>}
              {!me && other && <span className={other.hostile ? 'maze-play__token maze-play__token--hostile' : 'maze-play__token'} title={other.name}>●</span>}
              {!me && !other && cup && <span title='Cup'>🏆</span>}
              {!me && !other && !cup && item && <span title={item.name}>{item.item === 'lumos' ? '💡' : '🧭'}</span>}
              {!me && !other && !cup && creature && <span title={creature.name}>🐾</span>}
            </button>
          );
        })}
      </div>

      <div className='maze-play__controls'>
        {view.stunned ? (
          <p><FormattedMessage id='maze.stunned' defaultMessage='You are resting this turn.' /></p>
        ) : view.submitted ? (
          <p>
            <FormattedMessage id='maze.submitted' defaultMessage='Move sent. Waiting for: {names}' values={{ names: view.waiting.join(', ') || '-' }} />
          </p>
        ) : (
          <>
            <p className='maze-play__hint'>
              <FormattedMessage id='maze.hint' defaultMessage='Click neighbouring open squares to plan up to {steps} steps ({used} chosen).' values={{ steps: view.steps, used: path.length }} />
            </p>
            <div className='maze-play__stance'>
              <button type='button' className={stance === 'cooperate' ? 'maze-play__toggle maze-play__toggle--on' : 'maze-play__toggle'} onClick={() => { setStance('cooperate'); }}>
                🤝 <FormattedMessage id='maze.cooperate' defaultMessage='Cooperate' />
              </button>
              <button type='button' className={stance === 'hinder' ? 'maze-play__toggle maze-play__toggle--on' : 'maze-play__toggle'} onClick={() => { setStance('hinder'); }}>
                ⚔️ <FormattedMessage id='maze.hinder' defaultMessage='Hinder' />
              </button>
            </div>
            <div className='maze-play__actions'>
              <button type='button' className='content-card__action content-card__action--secondary' onClick={() => { setPath([]); }} disabled={path.length === 0}>
                <FormattedMessage id='maze.reset' defaultMessage='Reset' />
              </button>
              <button type='button' className='content-card__action' onClick={handleSubmit} disabled={busy}>
                {path.length === 0 ? (
                  <FormattedMessage id='maze.stay' defaultMessage='Stay here' />
                ) : (
                  <FormattedMessage id='maze.go' defaultMessage='Move {count} steps' values={{ count: path.length }} />
                )}
              </button>
            </div>
          </>
        )}
      </div>
    </div>
  );
};
