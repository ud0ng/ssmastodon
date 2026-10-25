// 트라이위저드 미로 게임방 (웹 전용 이벤트, 불의 잔): 안개 낀 산울타리 미로를 3/4 시점으로.
//   시작: 불의 잔 — 파란 불꽃이 붉게 타오르며 참가자 이름이 적힌 양피지가 튀어나오고, 산울타리가 솟아오른다 → 규칙 안내 [확인했습니다]
//   턴: 내 주변(시야)만 밝고, 지나온 곳은 흐릿하게, 나머지는 안개. 갈 수 있는 칸을 눌러 길을 고르면 모두 동시에 움직인다.
//   조우: 같은 칸·옆 칸에 다른 참가자가 있으면 두 사람(여러 명)을 클로즈업해 몰래 협력/방해를 고른다 → 악수 / 주문이 오간다.
//   마법 생물: 힌트를 보고 주문을 고른다. 가짜 우승컵은 소용돌이에 빨려 입구로, 진짜 우승컵은 하늘이 열리고 폭죽.
import { useCallback, useEffect, useMemo, useRef, useState } from 'react';

import { useHistory } from 'react-router-dom';

import { AnimatePresence, motion } from 'framer-motion';
import { createPortal } from 'react-dom';

import { apiRequestGet, apiRequestPost } from 'mastodon/api';
import { GameIcon } from 'mastodon/components/game_icons';

import { sendCommand } from './board';
import { useStageLayout } from './lobby';
import { BOGGART, COMPASS, CUP, DEMENTOR, FIREWORK, FLAME, GOBLET, HEDGE, SKREWT, SPHINX, SPIDER, TRAP, VORTEX, WAND } from './maze_art';

// ── 화면 데이터 ──
interface MPlayer { seat: number; name: string; account_id: string; avatar?: string | null; acct?: string | null; team: string | null; stunned: number; lumos: number; out: boolean; chosen: boolean }
interface MCreature { x: number; y: number; kind: string; name: string; hint: string | null }
interface MEvent { kind: string; seat?: number; seats?: number[]; target?: number; at?: [number, number]; to?: [number, number]; item?: string; creature?: string; spell?: string | null }
interface MRank { seat: number; rank: number; dist: number | null; out: boolean }
interface MTeamRank { team: string; name: string; color: string | null; score: number; rank: number }

interface MView {
  status: string;
  turn: number;
  max_turns: number;
  phase: 'move' | 'encounter' | 'finished';
  size: number;
  deadline_at: string | null;
  now: string;
  team_mode: boolean;
  teams: Record<string, { name: string; color: string | null }>;
  hostile: { from: number; to: number }[];
  players: MPlayer[];
  log: string[];
  waiting: string[];
  commands: Record<string, string>;
  spells: { key: string; name: string }[];
  lumos_turns: number;
  steps: number;
  finish: { ranks: MRank[]; team_ranks: MTeamRank[]; reached: number[]; test: boolean } | null;
  me: number | null;
  spectator: boolean;
  full: boolean;
  position: [number, number] | null;
  vision: number;
  cells: Record<string, number>;
  visible: number[];
  cups: { x: number; y: number; broken?: boolean; real?: boolean }[];
  traps: { x: number; y: number }[];
  creatures: MCreature[];
  items: { x: number; y: number; kind: string }[];
  tokens: { seat: number; x: number; y: number }[];
  trails: Record<string, [number, number][]>;
  gates: [number, number][];
  hint: { dir: string; turn: number; from: [number, number] } | null;
  inventory: { pointme: number; lumos: number };
  stunned: number;
  lumos: number;
  reachable: { x: number; y: number; path: string[] }[];
  planned: string[] | null;
  submitted: boolean;
  encounter: { creature: MCreature | null; group: number[] | null; picks: { spell?: string; stance?: string; target?: number } } | null;
  last: { turn: number; moves: Record<string, [number, number][]>; events: MEvent[] } | null;
}

export interface MzChat { id: string; mine: boolean; name: string; acct: string; avatar: string; text: string; team: string | null }

const REFRESH_MS = 2_500;
const SOUND_KEY = 'ssm:mz-sound';

// ── 효과음 (Web Audio, 소리 끄기 버튼을 따른다) ──
const soundOn = () => {
  try { return window.localStorage.getItem(SOUND_KEY) !== 'off'; } catch { return true; }
};
let audioContext: AudioContext | null = null;
const audio = () => {
  if (!soundOn()) return null;
  try {
    audioContext ??= new AudioContext();
    if (audioContext.state === 'suspended') void audioContext.resume();
    return audioContext;
  } catch {
    return null;
  }
};
const tone = (freq: number, at: number, length: number, options: { type?: OscillatorType; volume?: number; to?: number } = {}) => {
  const context = audio();
  if (!context) return;
  const start = context.currentTime + at;
  const oscillator = context.createOscillator();
  const gain = context.createGain();
  oscillator.type = options.type ?? 'sine';
  oscillator.frequency.setValueAtTime(freq, start);
  if (options.to) oscillator.frequency.exponentialRampToValueAtTime(options.to, start + length);
  gain.gain.setValueAtTime(0.0001, start);
  gain.gain.exponentialRampToValueAtTime(options.volume ?? 0.2, start + 0.03);
  gain.gain.exponentialRampToValueAtTime(0.0001, start + length);
  oscillator.connect(gain);
  gain.connect(context.destination);
  oscillator.start(start);
  oscillator.stop(start + length + 0.05);
};
const noise = (at: number, length: number, volume: number, frequency: number, type: BiquadFilterType = 'highpass') => {
  const context = audio();
  if (!context) return;
  const start = context.currentTime + at;
  const buffer = context.createBuffer(1, Math.ceil(context.sampleRate * length), context.sampleRate);
  const data = buffer.getChannelData(0);
  for (let index = 0; index < data.length; index += 1) data[index] = ((Math.random() * 2) - 1) * Math.sin((index / data.length) * Math.PI);
  const source = context.createBufferSource();
  source.buffer = buffer;
  const filter = context.createBiquadFilter();
  filter.type = type;
  filter.frequency.value = frequency;
  const gain = context.createGain();
  gain.gain.value = volume;
  source.connect(filter);
  filter.connect(gain);
  gain.connect(context.destination);
  source.start(start);
};
const sfx = {
  // 불의 잔: 푸른 불꽃이 확 붙는 소리
  flame: (at = 0) => { noise(at, 1.2, 0.3, 400, 'lowpass'); tone(90, at, 1.2, { type: 'sawtooth', volume: 0.06, to: 160 }); },
  // 양피지가 튀어나온다
  paper: (at = 0) => { noise(at, 0.25, 0.3, 2500); },
  // 산울타리가 솟는다
  rustle: (at = 0) => { noise(at, 1.4, 0.18, 1200, 'bandpass'); },
  step: (at = 0) => { tone(150, at, 0.08, { type: 'triangle', volume: 0.12, to: 90 }); },
  pick: () => { tone(660, 0, 0.12, { volume: 0.12 }); tone(990, 0.08, 0.18, { volume: 0.1 }); },
  // 함정이 탁
  snap: (at = 0) => { noise(at, 0.08, 0.7, 1500); tone(200, at, 0.3, { type: 'square', volume: 0.08, to: 60 }); },
  // 주문
  zap: (at = 0) => { tone(1800, at, 0.4, { type: 'sawtooth', volume: 0.06, to: 300 }); noise(at, 0.3, 0.2, 4000); },
  chime: (at = 0) => { [784, 988, 1175, 1568].forEach((freq, index) => { tone(freq, at + (index * 0.09), 0.5, { type: 'triangle', volume: 0.1 }); }); },
  growl: (at = 0) => { tone(75, at, 1.2, { type: 'sawtooth', volume: 0.1, to: 50 }); },
  // 포트키 소용돌이
  vortex: (at = 0) => { tone(200, at, 1.6, { type: 'sine', volume: 0.12, to: 1400 }); noise(at, 1.6, 0.2, 800, 'bandpass'); },
  thud: (at = 0) => { tone(90, at, 0.5, { type: 'triangle', volume: 0.5, to: 35 }); },
  // 하늘이 열리고 폭죽
  fanfare: (at = 0) => { [523, 659, 784, 1047, 1319].forEach((freq, index) => { tone(freq, at + (index * 0.13), 0.9, { type: 'triangle', volume: 0.14 }); }); },
  pop: (at = 0) => { noise(at, 0.15, 0.5, 600); tone(1200, at + 0.05, 0.4, { volume: 0.05, to: 400 }); },
  handshake: (at = 0) => { tone(520, at, 0.3, { type: 'triangle', volume: 0.1 }); tone(780, at + 0.15, 0.5, { type: 'triangle', volume: 0.1 }); },
};

const useClock = () => {
  const [now, setNow] = useState(() => Date.now());
  useEffect(() => {
    const timer = window.setInterval(() => { setNow(Date.now()); }, 500);
    return () => { window.clearInterval(timer); };
  }, []);
  return now;
};
const mmss = (ms: number) => {
  const seconds = Math.max(0, Math.floor(ms / 1000));
  return `${String(Math.floor(seconds / 60)).padStart(2, '0')}:${String(seconds % 60).padStart(2, '0')}`;
};

const Icon512: React.FC<{ paths: string[]; className?: string }> = ({ paths, className }) => (
  <svg className={className} viewBox='0 0 512 512' aria-hidden>
    {paths.map((d) => <path key={d} d={d} fill='currentColor' />)}
  </svg>
);

const CREATURE_ART: Record<string, string[]> = { boggart: BOGGART, skrewt: SKREWT, acromantula: SPIDER, dementor: DEMENTOR, sphinx: SPHINX };

// 반짝이·불씨·폭죽 입자
const Sparks: React.FC<{ count: number; delay?: number; tone?: 'gold' | 'red' | 'blue' | 'rainbow'; spread?: number }> = ({ count, delay = 0, tone: color = 'gold', spread = 6 }) => (
  <span className={`mz-sparks mz-sparks--${color}`} aria-hidden>
    {Array.from({ length: count }, (_, index) => {
      const angle = (index / count) * Math.PI * 2;
      const distance = 40 + ((index * 37) % 60);
      return (
        <motion.i
          // eslint-disable-next-line react/no-array-index-key
          key={index}
          style={color === 'rainbow' ? { background: `hsl(${(index * 47) % 360} 90% 65%)` } : undefined}
          initial={{ opacity: 0, x: 0, y: 0, scale: 0.4 }}
          animate={{ opacity: [0, 1, 0], x: Math.cos(angle) * distance * (spread / 6), y: Math.sin(angle) * distance * (spread / 6), scale: [0.4, 1.2, 0.3] }}
          transition={{ delay: delay + ((index % 6) * 0.04), duration: 1.2, ease: 'easeOut' }}
        />
      );
    })}
  </span>
);

// 크게 타오르는 제목 글씨 (한 글자씩)
const FlameTitle: React.FC<{ text: string; delay?: number; tone?: 'fire' | 'blue' | 'gold'; className?: string }> = ({ text, delay = 0, tone: color = 'fire', className }) => (
  <p className={['mz-title', `mz-title--${color}`, className].filter(Boolean).join(' ')}>
    {text.split('').map((char, index) => (
      <motion.span
        // eslint-disable-next-line react/no-array-index-key
        key={index}
        initial={{ opacity: 0, y: 20, scale: 1.6, filter: 'blur(8px) brightness(2.4)' }}
        animate={{ opacity: 1, y: 0, scale: 1, filter: 'blur(0px) brightness(1)' }}
        transition={{ delay: delay + (index * 0.08), duration: 0.5, ease: 'easeOut' }}
      >
        {char}
      </motion.span>
    ))}
  </p>
);

// ── 오프닝: 불의 잔 ──
const Opening: React.FC<{ players: MPlayer[]; onDone: () => void }> = ({ players, onDone }) => {
  const done = useRef(onDone);
  done.current = onDone;
  const [stage, setStage] = useState<'goblet' | 'hedges'>('goblet');
  useEffect(() => {
    sfx.flame(0.3);
    sfx.flame(2.2);
    players.forEach((_, index) => { sfx.paper(2.6 + (index * 0.35)); });
    const names = 2.6 + (players.length * 0.35) + 1.4;
    const toHedges = window.setTimeout(() => { setStage('hedges'); sfx.rustle(0); sfx.rustle(0.6); }, names * 1000);
    const finish = window.setTimeout(() => { done.current(); }, (names + 4.2) * 1000);
    return () => { window.clearTimeout(toHedges); window.clearTimeout(finish); };
  }, [players]);
  return (
    <motion.div className='mz-opening' initial={{ opacity: 0 }} animate={{ opacity: 1 }} exit={{ opacity: 0, transition: { duration: 1 } }}>
      <AnimatePresence mode='wait'>
        {stage === 'goblet' ? (
          <motion.div key='goblet' className='mz-opening__hall' exit={{ opacity: 0, scale: 1.2, transition: { duration: 0.8 } }}>
            {/* 푸른 불꽃이 피어오르다가 붉게 타오르며 이름이 튀어나온다 */}
            <motion.span className='mz-goblet__flame' initial={{ scaleY: 0, opacity: 0 }} animate={{ scaleY: [0, 1, 1, 1.4, 1], opacity: 1, filter: ['hue-rotate(0deg)', 'hue-rotate(0deg)', 'hue-rotate(0deg)', 'hue-rotate(170deg)', 'hue-rotate(170deg)'] }} transition={{ duration: 3, times: [0, 0.25, 0.6, 0.8, 1] }} />
            <motion.span className='mz-goblet' initial={{ y: 40, opacity: 0 }} animate={{ y: 0, opacity: 1 }} transition={{ duration: 1 }}>
              <Icon512 paths={GOBLET} />
            </motion.span>
            <ul className='mz-opening__names'>
              {players.map((player, index) => (
                <motion.li
                  key={player.seat}
                  initial={{ opacity: 0, y: 60, scale: 0.3, rotate: -20 }}
                  animate={{ opacity: 1, y: -170 - ((index % 3) * 26), x: ((index - ((players.length - 1) / 2)) * 92), scale: 1, rotate: ((index * 13) % 20) - 10 }}
                  transition={{ delay: 2.6 + (index * 0.35), duration: 0.9, type: 'spring', stiffness: 90, damping: 12 }}
                >
                  <span className='mz-opening__face'>{player.avatar ? <img src={player.avatar} alt='' /> : null}</span>
                  <b>{player.name}</b>
                </motion.li>
              ))}
            </ul>
            <FlameTitle text='불의 잔이 선택했다' delay={2} tone='blue' className='mz-opening__title' />
          </motion.div>
        ) : (
          <motion.div key='hedges' className='mz-opening__hedges' initial={{ opacity: 0 }} animate={{ opacity: 1 }}>
            <FlameTitle text='트라이위저드 미로' tone='gold' className='mz-opening__title' />
            <motion.p className='mz-opening__lead' initial={{ opacity: 0 }} animate={{ opacity: 1 }} transition={{ delay: 1.2 }}>안개 속 어딘가에 우승컵이 있다. 가장 먼저 손에 넣어라.</motion.p>
            <div className='mz-opening__wall' aria-hidden>
              {Array.from({ length: 14 }, (_, index) => (
                <motion.span
                  // eslint-disable-next-line react/no-array-index-key
                  key={index}
                  initial={{ y: 220, scaleY: 0.2 }}
                  animate={{ y: 0, scaleY: 1 }}
                  transition={{ delay: 0.2 + ((index % 7) * 0.12), duration: 0.9, type: 'spring', stiffness: 80, damping: 12 }}
                  style={{ left: `${(index * 7.4) - 2}%` }}
                >
                  <Icon512 paths={HEDGE} />
                </motion.span>
              ))}
            </div>
          </motion.div>
        )}
      </AnimatePresence>
    </motion.div>
  );
};

// ── 규칙 안내 ──
const RulesModal: React.FC<{ view: MView; onClose: () => void }> = ({ view, onClose }) => (
  <motion.div className='mz-modal' initial={{ opacity: 0 }} animate={{ opacity: 1 }} exit={{ opacity: 0 }}>
    <motion.div className='mz-modal__card' initial={{ y: 30, scale: 0.94 }} animate={{ y: 0, scale: 1 }} transition={{ type: 'spring', stiffness: 160, damping: 16 }}>
      <span className='mz-modal__cup'><Icon512 paths={CUP} /></span>
      <h2>우승컵을 먼저 잡아라</h2>
      <p className='mz-modal__lead'>{view.size}×{view.size} 미로 · 최대 {view.max_turns}턴{view.team_mode ? ' · 기숙사 팀전' : ' · 개인전'}</p>
      <ul className='mz-modal__rules'>
        <li><b>길 고르기</b> 빛나는 칸을 눌러 한 턴에 {view.steps}칸까지. 모두 고르면 함께 움직입니다. 안 고르면 제자리.</li>
        <li><b>시야</b> 주변 2칸만 보입니다. 지나온 길은 지도에 남습니다.</li>
        <li><b>함정·마법 생물</b> 함정은 1턴 정지. 생물은 힌트를 보고 주문을 고르세요 (틀리면 2턴 정지).</li>
        <li><b>아이템</b> 포인트 미는 진짜 우승컵 방향을 한 번, 루모스는 {view.lumos_turns}턴 동안 시야 +1.</li>
        <li><b>조우</b> 옆 칸에서 마주치면 몰래 협력(지도 나눔) 또는 방해(1턴 정지). 방해하면 '적대'가 모두에게 보입니다.</li>
        <li><b>가짜 우승컵</b> 똑같이 생긴 포트키 함정. 잡으면 입구로 날아갑니다.</li>
        <li><b>붉은 불꽃</b> 쏘아 올리면 기권(탈락)입니다.</li>
      </ul>
      <button type='button' className='mz-button' onClick={onClose}>확인했습니다</button>
    </motion.div>
  </motion.div>
);

// ── 3/4 시점 미로 ──
const CELL = 64;
const WALL = 30; // 산울타리 높이 (위로)
const THICK = 10;

const DIR_STEP: Record<string, [number, number]> = { N: [0, -1], E: [1, 0], S: [0, 1], W: [-1, 0] };

const MazeBoard: React.FC<{
  view: MView;
  hover: { x: number; y: number; path: string[] } | null;
  onHover: (cell: { x: number; y: number; path: string[] } | null) => void;
  onPick: (cell: { x: number; y: number; path: string[] }) => void;
}> = ({ view, hover, onHover, onPick }) => {
  const size = view.size;
  const visible = useMemo(() => new Set(view.visible), [view.visible]);
  // 보이는 범위: 참가자는 내 주변 (시야 + 4칸), 관전·끝난 판은 미로 전체
  const [cx, cy] = view.position ?? [Math.floor(size / 2), Math.floor(size / 2)];
  const radius = view.full ? size : view.vision + 4;
  const x0 = Math.max(0, Math.min(cx - radius, size - (radius * 2) - 1));
  const y0 = Math.max(0, Math.min(cy - radius, size - (radius * 2) - 1));
  const x1 = Math.min(size - 1, x0 + (radius * 2));
  const y1 = Math.min(size - 1, y0 + (radius * 2));
  const bits = (x: number, y: number) => view.cells[String((y * size) + x)];
  const known = (x: number, y: number) => bits(x, y) !== undefined;
  const lit = (x: number, y: number) => view.full || visible.has((y * size) + x);
  const reach = new Map(view.reachable.map((cell) => [`${cell.x},${cell.y}`, cell]));
  const hoverPath = new Set<string>();
  if (hover && view.position) {
    let [px, py] = view.position;
    hover.path.forEach((dir) => { const step = DIR_STEP[dir] ?? [0, 0]; px += step[0]; py += step[1]; hoverPath.add(`${px},${py}`); });
  }
  const tokenAt = (x: number, y: number) => view.tokens.filter((token) => token.x === x && token.y === y);
  const playerOf = (seat: number) => view.players.find((player) => player.seat === seat);
  const myTrail = view.me !== null ? (view.trails[String(view.me)] ?? []) : [];
  const trailSet = new Set(myTrail.map(([x, y]) => `${x},${y}`));
  const width = ((x1 - x0) + 1) * CELL;
  const height = ((y1 - y0) + 1) * CELL;
  const pos = (x: number, y: number) => [(x - x0) * CELL, ((y - y0) * CELL) + WALL] as const;
  const lastPath = (seat: number) => view.last?.moves[String(seat)];

  const rows = [];
  for (let y = y0; y <= y1; y += 1) {
    const floor = [];
    const walls = [];
    const things = [];
    for (let x = x0; x <= x1; x += 1) {
      const [sx, sy] = pos(x, y);
      if (!known(x, y)) continue;
      const cell = bits(x, y) ?? 0;
      const bright = lit(x, y);
      const key = `${x},${y}`;
      const option = reach.get(key);
      floor.push(
        <rect
          key={`f${key}`}
          className={['mz-floor', bright ? 'is-lit' : 'is-dim', trailSet.has(key) && 'is-trail', option && 'is-reach', hoverPath.has(key) && 'is-path', view.gates.some(([gx, gy]) => gx === x && gy === y) && 'is-gate'].filter(Boolean).join(' ')}
          x={sx}
          y={sy}
          width={CELL}
          height={CELL}
          onMouseEnter={option ? () => { onHover(option); } : undefined}
          onMouseLeave={option ? () => { onHover(null); } : undefined}
          onClick={option ? () => { onPick(option); } : undefined}
        />,
      );
      // 산울타리: 위쪽(북) 벽은 앞면이 보이는 띠로, 왼쪽(서) 벽은 위에서 본 얇은 띠로
      if (!(cell & 1)) walls.push(<g key={`n${key}`} className={bright ? 'mz-hedge is-lit' : 'mz-hedge'}><rect className='mz-hedge__top' x={sx - (THICK / 2)} y={sy - WALL - (THICK / 2)} width={CELL + THICK} height={THICK} /><rect className='mz-hedge__face' x={sx - (THICK / 2)} y={sy - WALL + (THICK / 2)} width={CELL + THICK} height={WALL} /></g>);
      if (!(cell & 8)) walls.push(<g key={`w${key}`} className={bright ? 'mz-hedge is-lit' : 'mz-hedge'}><rect className='mz-hedge__top' x={sx - (THICK / 2)} y={sy - WALL} width={THICK} height={CELL} /><rect className='mz-hedge__face' x={sx - (THICK / 2)} y={sy + CELL - WALL} width={THICK} height={WALL} /></g>);
      if (x === size - 1 && !(cell & 2)) walls.push(<g key={`e${key}`} className={bright ? 'mz-hedge is-lit' : 'mz-hedge'}><rect className='mz-hedge__top' x={sx + CELL - (THICK / 2)} y={sy - WALL} width={THICK} height={CELL} /><rect className='mz-hedge__face' x={sx + CELL - (THICK / 2)} y={sy + CELL - WALL} width={THICK} height={WALL} /></g>);
      // 칸 위의 것들 (보이는 칸만)
      if (view.traps.some((trap) => trap.x === x && trap.y === y)) things.push(<g key={`t${key}`} className='mz-thing mz-thing--trap' transform={`translate(${sx + 14} ${sy + 14}) scale(${36 / 512})`}><Icon512Paths paths={TRAP} /></g>);
      const item = view.items.find((each) => each.x === x && each.y === y);
      if (item) things.push(<g key={`i${key}`} className={`mz-thing mz-thing--item mz-thing--${item.kind}`} transform={`translate(${sx + 18} ${sy + 8}) scale(${28 / 512})`}><Icon512Paths paths={item.kind === 'pointme' ? COMPASS : WAND} /></g>);
      const cup = view.cups.find((each) => each.x === x && each.y === y);
      if (cup) {
        things.push(
          <g key={`c${key}`} className={['mz-cup', cup.broken && 'is-broken', cup.real === false && 'is-fake', cup.real && 'is-real'].filter(Boolean).join(' ')} transform={`translate(${sx + 8} ${sy - 18})`}>
            <circle className='mz-cup__glow' cx={24} cy={30} r={30} />
            <g transform={`scale(${48 / 512})`}><Icon512Paths paths={CUP} /></g>
          </g>,
        );
      }
      const creature = view.creatures.find((each) => each.x === x && each.y === y);
      if (creature) things.push(<motion.g key={`m${key}`} className={`mz-creature mz-creature--${creature.kind}`} initial={{ opacity: 0, scale: 0.5 }} animate={{ opacity: 1, scale: 1 }}><g transform={`translate(${sx + 6} ${sy - 24}) scale(${52 / 512})`}><Icon512Paths paths={CREATURE_ART[creature.kind] ?? BOGGART} /></g></motion.g>);
      tokenAt(x, y).forEach((token, index) => {
        const player = playerOf(token.seat);
        if (!player) return;
        const path = lastPath(token.seat);
        const frames = path && path.length > 1 ? path.map(([px, py]) => pos(px, py)) : null;
        const me = token.seat === view.me;
        const hostileToMe = view.me !== null && view.hostile.some((pair) => pair.from === token.seat && pair.to === view.me);
        const color = player.team ? view.teams[player.team]?.color ?? null : null;
        const offset = index * 10;
        things.push(
          <motion.g
            key={`p${token.seat}`}
            className={['mz-token', me && 'is-me', player.stunned > 0 && 'is-stunned', hostileToMe && 'is-hostile'].filter(Boolean).join(' ')}
            initial={frames ? { x: frames[0]?.[0] ?? sx, y: frames[0]?.[1] ?? sy } : { x: sx, y: sy }}
            animate={frames ? { x: frames.map((frame) => frame[0]), y: frames.map((frame) => frame[1]) } : { x: sx, y: sy }}
            transition={{ duration: frames ? 0.45 * frames.length : 0.3, ease: 'easeInOut' }}
          >
            <ellipse className='mz-token__shadow' cx={(CELL / 2) + offset} cy={CELL - 12} rx={18} ry={6} />
            <circle className='mz-token__ring' cx={(CELL / 2) + offset} cy={CELL / 2 - 10} r={21} style={color ? { stroke: color } : undefined} />
            <clipPath id={`mz-face-${token.seat}`}><circle cx={(CELL / 2) + offset} cy={CELL / 2 - 10} r={18} /></clipPath>
            {player.avatar ? <image href={player.avatar} x={(CELL / 2) - 18 + offset} y={(CELL / 2) - 28} width={36} height={36} clipPath={`url(#mz-face-${token.seat})`} preserveAspectRatio='xMidYMid slice' /> : null}
            {player.stunned > 0 && <text className='mz-token__stun' x={(CELL / 2) + offset} y={4}>✦ ✦</text>}
            {hostileToMe && <text className='mz-token__hostile' x={(CELL / 2) + 18 + offset} y={6}>⚔</text>}
          </motion.g>,
        );
      });
    }
    rows.push(<g key={`r${y}`}>{floor}{walls}{things}</g>);
  }
  // 맨 아래 줄 아래쪽 벽
  const bottom = [];
  if (y1 === size - 1) {
    for (let x = x0; x <= x1; x += 1) {
      if (!known(x, y1) || (bits(x, y1) ?? 0) & 4) continue;
      const [sx, sy] = pos(x, y1);
      bottom.push(<g key={`s${x}`} className={lit(x, y1) ? 'mz-hedge is-lit' : 'mz-hedge'}><rect className='mz-hedge__top' x={sx - (THICK / 2)} y={sy + CELL - WALL - (THICK / 2)} width={CELL + THICK} height={THICK} /><rect className='mz-hedge__face' x={sx - (THICK / 2)} y={sy + CELL - WALL + (THICK / 2)} width={CELL + THICK} height={WALL} /></g>);
    }
  }
  // 포인트 미 화살표
  const hint = view.hint && view.position ? view.hint : null;
  return (
    <div className='mz-board'>
      <svg className='mz-board__svg' viewBox={`${-THICK} 0 ${width + (THICK * 2)} ${height + WALL}`} preserveAspectRatio='xMidYMid meet'>
        <defs>
          <radialGradient id='mz-fog' cx='50%' cy='50%' r='60%'>
            <stop offset='55%' stopColor='#000' stopOpacity='0' />
            <stop offset='100%' stopColor='#000' stopOpacity='0.85' />
          </radialGradient>
        </defs>
        {rows}
        {bottom}
        {!view.full && <rect x={-THICK} y={0} width={width + (THICK * 2)} height={height + WALL} fill='url(#mz-fog)' pointerEvents='none' />}
      </svg>
      {hint && (
        <motion.span className='mz-hint' initial={{ scale: 0, rotate: -90 }} animate={{ scale: 1, rotate: 0 }} title={`${hint.turn}턴에 포인트 미가 가리킨 방향`}>
          <Icon512 paths={COMPASS} className='mz-hint__icon' />
          <b>{hint.dir}</b>
        </motion.span>
      )}
    </div>
  );
};

// SVG 안에 넣는 아이콘 (svg 안 svg 대신 path 만)
const Icon512Paths: React.FC<{ paths: string[] }> = ({ paths }) => <>{paths.map((d) => <path key={d} d={d} fill='currentColor' />)}</>;

// ── 조우·마법 생물: 클로즈업 ──
const EncounterPanel: React.FC<{ view: MView; busy: boolean; onSend: (command: string, options?: { args?: string; target?: string | null }) => void }> = ({ view, busy, onSend }) => {
  const encounter = view.encounter;
  if (!encounter) return null;
  const me = view.players.find((player) => player.seat === view.me);
  const others = (encounter.group ?? []).filter((seat) => seat !== view.me).map((seat) => view.players.find((player) => player.seat === seat)).filter(Boolean) as MPlayer[];
  const creature = encounter.creature;
  const needSpell = Boolean(creature) && !encounter.picks.spell;
  const needStance = others.length > 0 && !encounter.picks.stance;
  const left = view.deadline_at ? Date.parse(view.deadline_at) - Date.parse(view.now) : 0;
  return (
    <motion.div className='mz-encounter' initial={{ opacity: 0 }} animate={{ opacity: 1 }} exit={{ opacity: 0 }}>
      <motion.div className='mz-encounter__card' initial={{ scale: 0.8, y: 30 }} animate={{ scale: 1, y: 0 }} transition={{ type: 'spring', stiffness: 150, damping: 15 }}>
        {creature && (
          <section className={encounter.picks.spell ? 'mz-encounter__creature is-done' : 'mz-encounter__creature'}>
            <motion.span className={`mz-encounter__beast mz-creature--${creature.kind}`} initial={{ scale: 0.3, opacity: 0 }} animate={{ scale: [0.3, 1.15, 1], opacity: 1 }} transition={{ duration: 0.7 }}>
              <Icon512 paths={CREATURE_ART[creature.kind] ?? BOGGART} />
            </motion.span>
            <h3>{creature.name}{'이(가) 길을 막았다!'}</h3>
            <p className='mz-encounter__hint'>힌트 · {creature.hint}</p>
            {needSpell ? (
              <div className='mz-encounter__spells'>
                {view.spells.map((spell, index) => (
                  <motion.button key={spell.key} type='button' className='mz-spell' disabled={busy} initial={{ opacity: 0, y: 10 }} animate={{ opacity: 1, y: 0 }} transition={{ delay: 0.3 + (index * 0.06) }} onClick={() => { sfx.zap(); onSend(view.commands.spell ?? '주문', { args: spell.key }); }}>
                    <GameIcon name='sparkle' /> {spell.name}
                  </motion.button>
                ))}
              </div>
            ) : <p className='mz-encounter__wait'>주문을 외웠습니다…</p>}
          </section>
        )}
        {others.length > 0 && (
          <section className='mz-encounter__meet'>
            <h3>안개 속에서 마주쳤다</h3>
            <div className='mz-encounter__faces'>
              <motion.span className='mz-encounter__face is-me' initial={{ x: -80, opacity: 0 }} animate={{ x: 0, opacity: 1 }}>{me?.avatar ? <img src={me.avatar} alt='' /> : null}<b>{me?.name}</b></motion.span>
              <span className='mz-encounter__vs'>?</span>
              {others.map((other, index) => (
                <motion.span key={other.seat} className={view.hostile.some((pair) => pair.from === other.seat && pair.to === view.me) ? 'mz-encounter__face is-hostile' : 'mz-encounter__face'} initial={{ x: 80, opacity: 0 }} animate={{ x: 0, opacity: 1 }} transition={{ delay: index * 0.1 }}>
                  {other.avatar ? <img src={other.avatar} alt='' /> : null}
                  <b>{other.name}</b>
                </motion.span>
              ))}
            </div>
            {needStance ? (
              <div className='mz-encounter__choices'>
                <button type='button' className='mz-button mz-button--coop' disabled={busy} onClick={() => { sfx.handshake(); onSend(view.commands.cooperate ?? '협력'); }}>🤝 협력하기 <small>지도를 나눈다</small></button>
                {others.map((other) => (
                  <button key={other.seat} type='button' className='mz-button mz-button--hinder' disabled={busy} onClick={() => { sfx.zap(); onSend(view.commands.hinder ?? '방해', { target: other.acct }); }}>⚡ {other.name} 방해 <small>1턴 정지</small></button>
                ))}
              </div>
            ) : <p className='mz-encounter__wait'>선택했습니다. 상대의 선택을 기다립니다…</p>}
          </section>
        )}
        <small className='mz-encounter__timer'>남은 시간 {mmss(left)} · 고르지 않으면 {creature ? '주문 실패' : '협력'}</small>
      </motion.div>
    </motion.div>
  );
};

// ── 지난 턴 연출 (악수 · 주문 · 함정 · 포트키) ──
type Cue = { id: string; kind: 'coop' | 'hinder' | 'trap' | 'fake' | 'creature_win' | 'creature_lose' | 'item' | 'cup'; event: MEvent };

const CUE_MS: Record<Cue['kind'], number> = { coop: 2600, hinder: 2400, trap: 1800, fake: 3600, creature_win: 2200, creature_lose: 2200, item: 1400, cup: 5200 };

const playCue = (kind: Cue['kind']) => {
  if (kind === 'coop') { sfx.handshake(0.3); sfx.chime(0.9); }
  if (kind === 'hinder') { sfx.zap(0.2); sfx.thud(0.9); }
  if (kind === 'trap') sfx.snap(0.1);
  if (kind === 'fake') { sfx.vortex(0.2); sfx.thud(2.4); }
  if (kind === 'creature_win') { sfx.zap(0); sfx.chime(0.6); }
  if (kind === 'creature_lose') { sfx.growl(0); sfx.thud(0.5); }
  if (kind === 'item') sfx.chime(0);
  if (kind === 'cup') { sfx.fanfare(0.4); [1, 1.4, 1.8, 2.3, 2.8, 3.3].forEach((at) => { sfx.pop(at); }); }
};

const CueOverlay: React.FC<{ cue: Cue; view: MView }> = ({ cue, view }) => {
  const who = (seat?: number) => view.players.find((player) => player.seat === seat);
  const face = (seat?: number) => { const player = who(seat); return player?.avatar ? <img src={player.avatar} alt='' /> : null; };
  const event = cue.event;
  if (cue.kind === 'coop') {
    const seats = event.seats ?? [];
    return (
      <motion.div className='mz-cue mz-cue--coop' initial={{ opacity: 0 }} animate={{ opacity: 1 }} exit={{ opacity: 0 }}>
        <div className='mz-cue__pair'>
          {seats.map((seat, index) => (
            <motion.span key={seat} className='mz-cue__face' initial={{ x: index === 0 ? -160 : 160 }} animate={{ x: index === 0 ? -34 : 34 }} transition={{ duration: 0.8, ease: 'easeOut' }}>{face(seat)}</motion.span>
          ))}
          <motion.span className='mz-cue__hands' initial={{ scale: 0 }} animate={{ scale: [0, 1.4, 1] }} transition={{ delay: 0.8, duration: 0.5 }}>🤝</motion.span>
          <Sparks count={18} delay={0.9} />
        </div>
        <motion.h2 initial={{ opacity: 0, y: 10 }} animate={{ opacity: 1, y: 0 }} transition={{ delay: 1 }}>지도를 나눴다</motion.h2>
        <p>{seats.map((seat) => who(seat)?.name).join(' · ')}</p>
      </motion.div>
    );
  }
  if (cue.kind === 'hinder') {
    return (
      <motion.div className='mz-cue mz-cue--hinder' initial={{ opacity: 0 }} animate={{ opacity: 1 }} exit={{ opacity: 0 }}>
        <div className='mz-cue__pair'>
          <span className='mz-cue__face'>{face(event.seat)}</span>
          <motion.i className='mz-cue__bolt' initial={{ scaleX: 0 }} animate={{ scaleX: 1 }} transition={{ delay: 0.3, duration: 0.35 }} />
          <motion.span className='mz-cue__face is-hit' animate={{ x: [0, 0, -10, 10, -6, 0], rotate: [0, 0, -8, 8, 0, 0] }} transition={{ delay: 0.6, duration: 0.6 }}>{face(event.target)}</motion.span>
          <Sparks count={14} delay={0.65} tone='red' />
        </div>
        <motion.h2 initial={{ opacity: 0 }} animate={{ opacity: 1 }} transition={{ delay: 0.9 }}>{who(event.seat)?.name}의 방해!</motion.h2>
        <p>{who(event.target)?.name} 1턴 정지 · {who(event.seat)?.name}에게 적대 표시</p>
      </motion.div>
    );
  }
  if (cue.kind === 'fake') {
    return (
      <motion.div className='mz-cue mz-cue--fake' initial={{ opacity: 0 }} animate={{ opacity: 1 }} exit={{ opacity: 0 }}>
        <motion.span className='mz-cue__vortex' initial={{ scale: 0.2, rotate: 0 }} animate={{ scale: [0.2, 1.4, 1.6], rotate: 720 }} transition={{ duration: 2.4, ease: 'easeIn' }}><Icon512 paths={VORTEX} /></motion.span>
        <motion.span className='mz-cue__face' initial={{ scale: 1, rotate: 0 }} animate={{ scale: [1, 0.6, 0], rotate: [0, 360, 900], opacity: [1, 1, 0] }} transition={{ delay: 0.4, duration: 1.8, ease: 'easeIn' }}>{face(event.seat)}</motion.span>
        <motion.h2 initial={{ opacity: 0 }} animate={{ opacity: 1 }} transition={{ delay: 2.2 }}>포트키였다!</motion.h2>
        <motion.p initial={{ opacity: 0 }} animate={{ opacity: 1 }} transition={{ delay: 2.5 }}>가짜 우승컵에 빨려 들어가 입구로 떨어졌습니다.</motion.p>
      </motion.div>
    );
  }
  if (cue.kind === 'trap') {
    return (
      <motion.div className='mz-cue mz-cue--trap' initial={{ opacity: 0 }} animate={{ opacity: 1, x: [0, -8, 8, -5, 5, 0] }} exit={{ opacity: 0 }} transition={{ x: { delay: 0.1, duration: 0.4 } }}>
        <motion.span className='mz-cue__icon' initial={{ scale: 2, opacity: 0 }} animate={{ scale: 1, opacity: 1 }} transition={{ type: 'spring', stiffness: 260, damping: 12 }}><Icon512 paths={TRAP} /></motion.span>
        <h2>함정!</h2>
        <p>{who(event.seat)?.name} 1턴 정지</p>
      </motion.div>
    );
  }
  if (cue.kind === 'creature_win' || cue.kind === 'creature_lose') {
    const win = cue.kind === 'creature_win';
    const spell = view.spells.find((each) => each.key === event.spell)?.name;
    return (
      <motion.div className={win ? 'mz-cue mz-cue--win' : 'mz-cue mz-cue--lose'} initial={{ opacity: 0 }} animate={{ opacity: 1 }} exit={{ opacity: 0 }}>
        <motion.span className={`mz-cue__icon mz-creature--${event.creature}`} animate={win ? { scale: [1, 1.2, 0], opacity: [1, 1, 0], rotate: [0, -10, 40] } : { scale: [1, 1.3, 1], x: [0, -30, 0] }} transition={{ delay: 0.5, duration: 0.9 }}>
          <Icon512 paths={CREATURE_ART[event.creature ?? ''] ?? BOGGART} />
        </motion.span>
        {spell && <motion.b className='mz-cue__spell' initial={{ opacity: 0, scale: 0.6 }} animate={{ opacity: 1, scale: 1 }}>“{spell}!”</motion.b>}
        <Sparks count={16} delay={0.5} tone={win ? 'blue' : 'red'} />
        <h2>{win ? '물리쳤다!' : '당했다…'}</h2>
        <p>{who(event.seat)?.name}{win ? '' : ' · 2턴 정지'}</p>
      </motion.div>
    );
  }
  if (cue.kind === 'item') {
    return (
      <motion.div className='mz-cue mz-cue--item' initial={{ opacity: 0, y: 20 }} animate={{ opacity: 1, y: 0 }} exit={{ opacity: 0 }}>
        <span className='mz-cue__icon'><Icon512 paths={event.item === 'pointme' ? COMPASS : WAND} /></span>
        <p>{event.item === 'pointme' ? '포인트 미' : '루모스'}를 주웠다!</p>
      </motion.div>
    );
  }
  // 진짜 우승컵: 하늘이 열리고 폭죽
  return (
    <motion.div className='mz-cue mz-cue--cup' initial={{ opacity: 0 }} animate={{ opacity: 1 }} exit={{ opacity: 0 }}>
      <motion.i className='mz-cue__sky' initial={{ clipPath: 'inset(0 50% 100% 50%)' }} animate={{ clipPath: 'inset(0 0% 0% 0%)' }} transition={{ duration: 1.6, ease: 'easeOut' }} />
      {Array.from({ length: 6 }, (_, index) => (
        // eslint-disable-next-line react/no-array-index-key
        <span key={index} className='mz-cue__firework' style={{ left: `${12 + (index * 15)}%`, top: `${12 + ((index * 23) % 30)}%` }}>
          <Sparks count={22} delay={1 + (index * 0.45)} tone='rainbow' spread={9} />
        </span>
      ))}
      <motion.span className='mz-cue__cup' initial={{ y: 80, scale: 0.4, opacity: 0 }} animate={{ y: 0, scale: 1, opacity: 1 }} transition={{ delay: 0.6, type: 'spring', stiffness: 90, damping: 11 }}><Icon512 paths={CUP} /></motion.span>
      <FlameTitle text={`${who(event.seat)?.name ?? ''} 우승컵을 잡았다!`} delay={1.4} tone='gold' />
    </motion.div>
  );
};

// ── 끝: 순위 ──
const EndScreen: React.FC<{ view: MView; onLeave: () => void }> = ({ view, onLeave }) => {
  const finish = view.finish;
  useEffect(() => { sfx.fanfare(0.3); }, []);
  if (!finish) return null;
  const who = (seat: number) => view.players.find((player) => player.seat === seat);
  const winners = finish.ranks.filter((row) => finish.reached.includes(row.seat));
  const title = winners.length === 0 ? '우승자 없음' : view.team_mode ? `${finish.team_ranks[0]?.name ?? ''} 팀 우승!` : `${winners.map((row) => who(row.seat)?.name).join(' · ')} 우승!`;
  return (
    <motion.div className='mz-end' initial={{ opacity: 0 }} animate={{ opacity: 1 }}>
      <motion.span className='mz-end__cup' initial={{ scale: 0, rotate: -30 }} animate={{ scale: 1, rotate: 0 }} transition={{ type: 'spring', stiffness: 100, damping: 10 }}><Icon512 paths={CUP} /></motion.span>
      <FlameTitle text={title} delay={0.4} tone='gold' className='mz-end__title' />
      {finish.test && <p className='mz-end__note'>(테스트 플레이라 점수와 보상은 없습니다)</p>}
      {view.team_mode && finish.team_ranks.length > 0 && (
        <ol className='mz-end__teams'>
          {finish.team_ranks.map((team, index) => (
            <motion.li key={team.team} style={team.color ? { borderColor: team.color } : undefined} initial={{ opacity: 0, y: 12 }} animate={{ opacity: 1, y: 0 }} transition={{ delay: 1 + (index * 0.12) }}>
              <b>{team.rank}위</b> {team.name} <small>{team.score}점</small>
            </motion.li>
          ))}
        </ol>
      )}
      <ol className='mz-end__ranks'>
        {finish.ranks.map((row, index) => {
          const player = who(row.seat);
          return (
            <motion.li key={row.seat} className={[row.rank === 1 && finish.reached.includes(row.seat) && 'is-winner', row.out && 'is-out'].filter(Boolean).join(' ')} initial={{ opacity: 0, x: -20 }} animate={{ opacity: 1, x: 0 }} transition={{ delay: 1.2 + (index * 0.1) }}>
              <em>{row.rank}</em>
              <span className='mz-end__face'>{player?.avatar ? <img src={player.avatar} alt='' /> : null}</span>
              <b>{player?.name}</b>
              <small>{row.out ? '붉은 불꽃 (기권)' : row.dist === 0 ? '우승컵!' : row.dist === null ? '-' : `우승컵까지 ${row.dist}칸`}</small>
            </motion.li>
          );
        })}
      </ol>
      <button type='button' className='mz-button' onClick={onLeave}>나가기</button>
    </motion.div>
  );
};

// ── 채팅 (전체 · 팀전이면 팀) ──
const ChatDock: React.FC<{ sessionId: string; chat: MzChat[]; teamMode: boolean; canChat: boolean; onSent: () => void }> = ({ sessionId, chat, teamMode, canChat, onSent }) => {
  const [tab, setTab] = useState<'all' | 'team'>('all');
  const [text, setText] = useState('');
  const listRef = useRef<HTMLUListElement>(null);
  const shown = tab === 'team' ? chat.filter((message) => message.team) : chat;
  useEffect(() => { if (listRef.current) listRef.current.scrollTop = listRef.current.scrollHeight; }, [shown.length, tab]);
  return (
    <section className='mz-chat'>
      <div className='mz-chat__tabs'>
        <button type='button' className={tab === 'all' ? 'is-on' : undefined} onClick={() => { setTab('all'); }}>전체</button>
        {teamMode && <button type='button' className={tab === 'team' ? 'is-on' : undefined} onClick={() => { setTab('team'); }}>우리 팀</button>}
      </div>
      <ul ref={listRef} className='mz-chat__list'>
        {shown.map((message) => (
          <li key={message.id} className={message.mine ? 'is-mine' : undefined}>
            {message.team && tab === 'all' && <em>[팀]</em>}
            {message.avatar && <img src={message.avatar} alt='' />}
            <strong>{message.name}</strong>
            <span>: {message.text}</span>
          </li>
        ))}
      </ul>
      {canChat && (
        <form onSubmit={(event) => {
          event.preventDefault();
          const value = text.trim();
          if (!value) return;
          setText('');
          apiRequestPost(`v1/system/sessions/${sessionId}/chat`, { text: value, channel: tab === 'team' ? 'team' : 'all' })
            .then(() => { onSent(); return true; })
            .catch(() => { onSent(); });
        }}
        >
          <input type='text' value={text} maxLength={200} placeholder={tab === 'team' ? '팀에게만…' : '안개 너머로 외치기…'} onChange={(event) => { setText(event.target.value); }} />
          <button type='submit' className='mz-button mz-button--small' disabled={!text.trim()}>보내기</button>
        </form>
      )}
    </section>
  );
};

// ── 무대 ──
export const MazeStage: React.FC<{ sessionId: string; name: string; chat: MzChat[]; staff: boolean; isPlayer: boolean; onChanged: () => void }> = ({ sessionId, name, chat, isPlayer, onChanged }) => {
  const history = useHistory();
  const [view, setView] = useState<MView | null>(null);
  const [busy, setBusy] = useState(false);
  const [hover, setHover] = useState<{ x: number; y: number; path: string[] } | null>(null);
  const [intro, setIntro] = useState<'pending' | 'opening' | 'rules' | 'done'>('pending');
  const [cues, setCues] = useState<Cue[]>([]);
  const [ended, setEnded] = useState(false);
  const [sound, setSound] = useState(soundOn);
  const [flareAsk, setFlareAsk] = useState(false);
  const now = useClock();
  useStageLayout(true);

  const load = useCallback(() => {
    apiRequestGet<{ view: MView | null }>(`v1/system/sessions/${sessionId}/view`)
      .then((response) => { if (response.view) setView(response.view); return response; })
      .catch(() => undefined);
  }, [sessionId]);
  useEffect(() => {
    load();
    const timer = window.setInterval(load, REFRESH_MS);
    return () => { window.clearInterval(timer); };
  }, [load]);

  // 처음: 첫 턴이면 불의 잔 오프닝 → 규칙, 아니면 규칙만 (참가자), 관전자는 첫 턴이면 오프닝만
  const introChecked = useRef(false);
  useEffect(() => {
    if (!view || introChecked.current) return;
    introChecked.current = true;
    let seen = false;
    try { seen = window.sessionStorage.getItem(`ssm:mz-intro:${sessionId}`) === '1'; } catch { seen = false; }
    const firstTurn = view.turn <= 1 && view.status === 'active';
    if (seen || view.status === 'finished') setIntro('done');
    else if (view.spectator) setIntro(firstTurn ? 'opening' : 'done');
    else setIntro(firstTurn ? 'opening' : 'rules');
  }, [view, sessionId]);
  const finishIntro = useCallback(() => {
    setIntro('done');
    try { window.sessionStorage.setItem(`ssm:mz-intro:${sessionId}`, '1'); } catch { /* 이번만 */ }
  }, [sessionId]);

  // 지난 턴이 바뀌면 그 턴의 일(내가 아는 것)을 연출 차례에
  const seenTurn = useRef<number | null>(null);
  useEffect(() => {
    if (!view?.last) return;
    const before = seenTurn.current;
    seenTurn.current = view.last.turn;
    if (before === null || before === view.last.turn) return;
    const mine = (event: MEvent) => view.full || event.seat === view.me || (event.seats ?? []).includes(view.me ?? -1) || event.target === view.me || event.kind === 'cup';
    const next: Cue[] = view.last.events.filter(mine).map((event, index) => ({ id: `${view.last?.turn}-${index}`, kind: event.kind as Cue['kind'], event }));
    if (next.length > 0) setCues((current) => [...current, ...next]);
    [0.1, 0.4, 0.7].forEach((at) => { sfx.step(at); });
  }, [view]);
  const cue = cues[0];
  useEffect(() => {
    if (!cue || intro !== 'done') return undefined;
    playCue(cue.kind);
    const timer = window.setTimeout(() => { setCues((current) => current.slice(1)); }, CUE_MS[cue.kind] ?? 2000);
    return () => { window.clearTimeout(timer); };
  }, [cue, intro]);
  useEffect(() => {
    if (view?.status === 'finished' && cues.length === 0) {
      const timer = window.setTimeout(() => { setEnded(true); }, 900);
      return () => { window.clearTimeout(timer); };
    }
    return undefined;
  }, [view?.status, cues.length]);

  const send = useCallback((command: string, options: { args?: string; target?: string | null } = {}) => {
    setBusy(true);
    sendCommand({ session_id: sessionId, command, ...(options.target ? { target: options.target } : {}), ...(options.args ? { args: options.args } : {}) })
      .then(() => { load(); onChanged(); return true; })
      .catch(() => undefined)
      .finally(() => { setBusy(false); });
  }, [sessionId, load, onChanged]);
  const toggleSound = useCallback(() => {
    setSound((current) => {
      try { window.localStorage.setItem(SOUND_KEY, current ? 'off' : 'on'); } catch { /* 이번만 */ }
      return !current;
    });
  }, []);

  if (!view) return createPortal(<div className='game-stage mz-stage' role='region' aria-label={name} />, document.body);

  const me = view.players.find((player) => player.seat === view.me);
  const playing = view.status === 'active' && isPlayer && me && !me.out;
  const left = view.deadline_at ? Date.parse(view.deadline_at) - now : 0;
  const myTurn = playing && view.phase === 'move' && !view.submitted && view.stunned === 0;
  const pick = (cell: { path: string[] }) => { sfx.pick(); setHover(null); send(view.commands.move ?? '이동', { args: cell.path.join('/') }); };
  const askText = !playing ? (view.spectator ? '관전 중입니다. 미로 전체와 진짜 우승컵이 보입니다.' : me?.out ? '붉은 불꽃을 쏘아 올렸습니다. 끝까지 지켜보세요.' : '')
    : view.phase === 'encounter' ? (view.encounter ? '' : '다른 사람들이 조우 중입니다…')
      : view.stunned > 0 ? `움직일 수 없습니다 (${view.stunned}턴 정지)`
        : view.submitted ? `길을 골랐습니다. ${view.waiting.length > 0 ? `${view.waiting.join(', ')}을(를) 기다립니다` : ''}`
          : `빛나는 칸을 눌러 길을 고르세요 (${view.steps}칸까지)`;

  return createPortal(
    <div className={['game-stage mz-stage', view.phase === 'encounter' && 'is-encounter', intro === 'opening' && 'is-intro'].filter(Boolean).join(' ')} role='region' aria-label={name}>
      <div className='mz-backdrop' aria-hidden><i className='mz-fog mz-fog--a' /><i className='mz-fog mz-fog--b' /></div>

      <header className='mz-top'>
        <span className='mz-chip mz-chip--turn'>{view.turn} / {view.max_turns}턴</span>
        {view.status === 'active' && view.deadline_at && <span className={left < 20_000 ? 'mz-timer is-low' : 'mz-timer'}><GameIcon name='hourglass' /> {mmss(left)}</span>}
        <span className='mz-chip'>{view.size}×{view.size} · {view.team_mode ? '기숙사 팀전' : '개인전'}</span>
        <button type='button' className={sound ? 'mz-sound' : 'mz-sound is-off'} onClick={toggleSound} aria-pressed={sound}>{sound ? '♪' : '×'}</button>
        <button type='button' className='mz-exit' onClick={() => { history.push('/system/group'); }}>나가기</button>
      </header>

      <div className='mz-main'>
        <MazeBoard view={view} hover={myTurn ? hover : null} onHover={myTurn ? setHover : () => undefined} onPick={myTurn ? pick : () => undefined} />

        <aside className='mz-side'>
          <h3 className='mz-side__title'>참가자</h3>
          <ul className='mz-people'>
            {view.players.map((player) => {
              const team = player.team ? view.teams[player.team] : null;
              const hostile = view.hostile.filter((pair) => pair.from === player.seat).map((pair) => view.players.find((each) => each.seat === pair.to)?.name).filter(Boolean);
              return (
                <li key={player.seat} className={[player.seat === view.me && 'is-me', player.out && 'is-out'].filter(Boolean).join(' ')}>
                  <span className='mz-people__face' style={team?.color ? { boxShadow: `0 0 0 2px ${team.color}` } : undefined}>{player.avatar ? <img src={player.avatar} alt='' /> : null}</span>
                  <span className='mz-people__name'>
                    <b>{player.name}{player.seat === view.me ? ' (나)' : ''}</b>
                    <small>
                      {team && <em style={team.color ? { color: team.color } : undefined}>{team.name}</em>}
                      {player.out ? ' 🔥 기권' : player.stunned > 0 ? ` ✦ ${player.stunned}턴 정지` : view.status === 'active' ? (player.chosen ? ' ✓' : ' …') : ''}
                      {player.lumos > 0 && ' 💡'}
                      {hostile.length > 0 && <span className='mz-people__hostile'> ⚔ {hostile.join(', ')}</span>}
                    </small>
                  </span>
                </li>
              );
            })}
          </ul>
          {playing && (
            <div className='mz-items'>
              <button type='button' className='mz-item' disabled={busy || view.inventory.pointme === 0 || view.phase !== 'move'} title='진짜 우승컵이 있는 방향을 한 번 알려 줍니다' onClick={() => { sfx.chime(); send(view.commands.pointme ?? '포인트미'); }}>
                <Icon512 paths={COMPASS} /> 포인트 미 <b>{view.inventory.pointme}</b>
              </button>
              <button type='button' className='mz-item' disabled={busy || view.inventory.lumos === 0 || view.phase !== 'move' || view.lumos > 0} title={`${view.lumos_turns}턴 동안 시야 +1`} onClick={() => { sfx.chime(); send(view.commands.lumos ?? '루모스'); }}>
                <Icon512 paths={WAND} /> 루모스 <b>{view.lumos > 0 ? `${view.lumos}턴` : view.inventory.lumos}</b>
              </button>
              {myTurn && <button type='button' className='mz-item' disabled={busy} onClick={() => { send(view.commands.stay ?? '대기'); }}>제자리</button>}
              <button type='button' className='mz-item mz-item--flare' disabled={busy} onClick={() => { setFlareAsk(true); }}><Icon512 paths={FLAME} /> 붉은 불꽃</button>
            </div>
          )}
          {view.log.length > 0 && (
            <ul className='mz-log'>
              {view.log.map((line, index) => <li key={`${view.turn}-${index}`}>{line}</li>)}
            </ul>
          )}
        </aside>
      </div>

      <div className={askText ? 'mz-action is-on' : 'mz-action'}>{askText && <span>{askText}</span>}</div>

      <ChatDock sessionId={sessionId} chat={chat} teamMode={view.team_mode} canChat={isPlayer} onSent={onChanged} />

      <AnimatePresence>
        {playing && view.phase === 'encounter' && view.encounter && intro === 'done' && !cue && <EncounterPanel key='encounter' view={view} busy={busy} onSend={send} />}
      </AnimatePresence>
      <AnimatePresence>
        {flareAsk && (
          <motion.div className='mz-modal' initial={{ opacity: 0 }} animate={{ opacity: 1 }} exit={{ opacity: 0 }}>
            <div className='mz-modal__card mz-modal__card--flare'>
              <span className='mz-modal__cup is-red'><Icon512 paths={FLAME} /></span>
              <h2>붉은 불꽃을 쏘아 올릴까요?</h2>
              <p className='mz-modal__lead'>쏘아 올리면 기권(탈락)하고 되돌릴 수 없습니다.</p>
              <div className='mz-modal__actions'>
                <button type='button' className='mz-button mz-button--ghost' onClick={() => { setFlareAsk(false); }}>계속 탐험</button>
                <button type='button' className='mz-button mz-button--hinder' onClick={() => { setFlareAsk(false); sfx.flame(); send(view.commands.flare ?? '붉은불꽃'); }}>쏘아 올리기</button>
              </div>
            </div>
          </motion.div>
        )}
      </AnimatePresence>
      <AnimatePresence>
        {intro === 'opening' && <Opening key='opening' players={view.players} onDone={() => { if (view.spectator) finishIntro(); else setIntro('rules'); }} />}
      </AnimatePresence>
      <AnimatePresence>
        {intro === 'rules' && <RulesModal key='rules' view={view} onClose={finishIntro} />}
      </AnimatePresence>
      <AnimatePresence>
        {intro === 'done' && cue && <CueOverlay key={cue.id} cue={cue} view={view} />}
      </AnimatePresence>
      <AnimatePresence>
        {ended && <EndScreen key='end' view={view} onLeave={() => { history.push('/system/group'); }} />}
      </AnimatePresence>
    </div>,
    document.body,
  );
};
