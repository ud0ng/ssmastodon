// 비행 대결 게임방 (이벤트, 웹 전용): 구름이 떠다니는 하늘, 출발선에 선 토큰들, 라운드마다 앞길을 골라 날아가고 부딪힌 토큰은 떨어진다.
//   마지막 1인(더 줄일 수 없으면 2인)이 남을 때까지 이어가고, 끝나면 '종료!!' → 시상대(1등이 가장 크게, 좌우로 2·3등) → 점수·재화·아이템 → 오늘의 MVP(가장 바보 같았던 장면 다시보기).
//   서버: Game::Kinds::Flying#view_for (GET /api/v1/system/sessions/:id/view), 길 고르기는 POST /api/v1/system/commands [비행/번호]
//   애니메이션은 framer-motion. 라운드 기록(history)이 새로 생기면 그 라운드를 한 번 틀어 주고, 끝난 라운드는 언제든 다시 볼 수 있다.
import React, { useCallback, useEffect, useMemo, useRef, useState } from 'react';

import { defineMessages, FormattedMessage, useIntl } from 'react-intl';

import { useHistory } from 'react-router-dom';

import { animate, AnimatePresence, motion } from 'framer-motion';
import { createPortal } from 'react-dom';

import { apiRequestGet, apiRequestPost } from 'mastodon/api';

import { sendCommand } from './board';
import { GameToken } from './game_token';
import type { TokenHouse } from './game_token';
import { useStageLayout } from './lobby';

// ── 서버가 보내는 판 ──
interface FlyPlayer {
  seat: number;
  account_id: string;
  acct?: string;
  name: string;
  avatar?: string | null;
  house: TokenHouse | null;
  alive: boolean;
  out_round: number | null;
  chosen: boolean;
  // 지금 빗자루 내구도
  hp: number;
  result: 'win' | 'lose' | 'draw' | null;
}

type Outcome = 'pass' | 'crash' | 'idle';

interface RoundEntry {
  round: number;
  lanes: number;
  routes: string[];
  alive_before: string[];
  choices: Record<string, number | undefined>;
  results: Record<string, Outcome>;
  // 금빛 고리 길 번호, 라운드 앞뒤 내구도, 고리로 +1 한 자리, 추락한 자리, 모두 추락해 무효가 된 라운드
  ring?: number | null;
  hp_before?: Record<string, number>;
  hp_after?: Record<string, number>;
  ring_gain?: string[];
  fell?: string[];
  void?: boolean;
}

interface Scene {
  kind: string;
  round: number;
  lane: number | null;
  seats: number[];
  title: string;
  text: string;
  score: number;
}

interface Reward {
  result: 'win' | 'lose' | 'draw';
  points: number;
  money: number;
  items: string[];
}

interface FinishView {
  ranks: { rank: number; seats: number[] }[];
  mvp: Scene[];
  currency: string;
  test: boolean;
  rewards: Record<string, Reward | null>;
}

interface FlyView {
  status: 'active' | 'finished' | string;
  round: number;
  lanes: number;
  routes: string[];
  deadline_at: string | null;
  now: string;
  round_seconds: number;
  me: number | null;
  spectator: boolean;
  commands: { fly: string };
  my_choice: number | null;
  durability: number;
  ring: number | null;
  players: FlyPlayer[];
  history: RoundEntry[];
  finish: FinishView | null;
}

interface ViewResponse {
  view: FlyView | null;
}

export interface FlyChatMessage {
  id: string;
  mine: boolean;
  name: string;
  acct: string;
  avatar: string;
  text: string;
}

const messages = defineMessages({
  chatPlaceholder: { id: 'flying.chat_placeholder', defaultMessage: 'Say something' },
  send: { id: 'flying.send', defaultMessage: 'Send' },
  rankN: { id: 'flying.rank_n', defaultMessage: '#{rank}' },
});

const LINE_Y = 80;
const LANE_Y = 36;
const REFRESH_MS = 1_500;
const FINISHED_REFRESH_MS = 6_000;
const BUBBLE_MS = 6_000;

// ── 토큰 위치 (무대 크기에 대한 %) ──
interface TokenPos {
  x: number;
  y: number;
  rot: number;
  scale: number;
  opacity: number;
  dur: number;
  ease: 'easeInOut' | 'easeIn' | 'easeOut' | 'linear';
  shake?: boolean;
}

interface Burst {
  id: string;
  x: number;
  y: number;
}

const slotX = (index: number, count: number) => (count <= 1 ? 50 : 12 + ((index * 76) / (count - 1)));
const laneX = (lane: number, lanes: number) => 10 + (((lane - 0.5) * 80) / lanes);
// 길 칸 너비: 칸 사이에 간격이 생기게 자기 몫(80/n %)보다 조금 좁게
const LANE_W = (lanes: number) => (80 / lanes) - Math.min(3.2, 14 / lanes);
const wait = (ms: number) => new Promise<void>((resolve) => { window.setTimeout(resolve, ms); });

// 추락한 자리 / 이번 라운드를 버틴 자리 (내구도가 없던 옛 기록은 통과한 자리만 버틴 것으로)
const fellOf = (entry: RoundEntry): string[] => entry.fell ?? entry.alive_before.filter((seat) => entry.results[seat] !== 'pass');
const survivorsOf = (entry: RoundEntry): string[] => entry.alive_before.filter((seat) => !fellOf(entry).includes(seat));

// 한 라운드를 틀어 주는 장치: 출발선에서 고른 길로 날아가 → 부딪힘(깃털·잔가지, 내구도 -1) → 내구도가 0이면 떨어짐 → 살아남은 토큰이 출발선으로 돌아온다
const useRoundPlayer = () => {
  const [pos, setPos] = useState<Record<string, TokenPos>>({});
  const [bursts, setBursts] = useState<Burst[]>([]);
  const [flying, setFlying] = useState(false);
  // 살아남은 토큰이 출발선으로 돌아오는 동안 (배경이 반대로 흐른다)
  const [returning, setReturning] = useState(false);
  // 자리 → 지금 보여 줄 내구도, 이번 라운드에 내구도가 깎여 휘청이는 자리, 금빛 고리로 +1 한 자리, 무효가 된 라운드
  const [hp, setHp] = useState<Record<string, number>>({});
  const [wobble, setWobble] = useState<string[]>([]);
  const [gains, setGains] = useState<string[]>([]);
  const [voided, setVoided] = useState(false);
  const mounted = useRef(true);

  useEffect(() => {
    mounted.current = true;
    return () => { mounted.current = false; };
  }, []);

  // 이 자리들만 출발선에 세운다 (나머지는 안 보인다)
  const settle = useCallback((seats: string[], dur = 0.7) => {
    const next: Record<string, TokenPos> = {};
    seats.forEach((seat, index) => {
      next[seat] = { x: slotX(index, seats.length), y: LINE_Y, rot: 0, scale: 1, opacity: 1, dur, ease: 'easeInOut' };
    });
    setPos(next);
  }, []);

  const play = useCallback(async (entry: RoundEntry, options: { returnToLine: boolean }) => {
    const before = entry.alive_before;
    const fell = fellOf(entry);
    const groups: Record<number, string[]> = {};
    before.forEach((seat) => {
      const lane = entry.choices[seat];
      if (lane) (groups[lane] ??= []).push(seat);
    });
    setFlying(true);
    if (entry.hp_before) setHp((prev) => ({ ...prev, ...entry.hp_before }));

    // 1) 고른 길로 날아간다 (같은 길의 토큰은 나란히 겹친다)
    setPos((prev) => {
      const next = { ...prev };
      before.forEach((seat) => {
        const lane = entry.choices[seat];
        const base = prev[seat] ?? { x: 50, y: LINE_Y, rot: 0, scale: 1, opacity: 1, dur: 0.7, ease: 'easeInOut' as const };
        if (!lane) {
          next[seat] = { ...base, rot: 0, dur: 0.3 };
          return;
        }
        const group = groups[lane] ?? [seat];
        const index = group.indexOf(seat);
        const spread = Math.min(3.4, 9 / group.length);
        next[seat] = { x: laneX(lane, entry.lanes) + ((index - ((group.length - 1) / 2)) * spread), y: LANE_Y + (group.length > 1 ? (index % 2) * 3 : 0), rot: 0, scale: 1, opacity: 1, dur: 1.3, ease: 'easeInOut' };
      });
      return next;
    });
    await wait(1_500);
    if (!mounted.current) return;

    // 2) 부딪힌다: 깃털과 잔가지가 터지고 내구도가 깎인다 (빗자루가 휘청). 금빛 고리를 혼자 지난 사람은 내구도 +1
    const crashed = Object.entries(groups).filter(([, group]) => group.length > 1);
    const idle = before.filter((seat) => !entry.choices[seat]);
    setBursts(crashed.map(([lane]) => ({ id: `${entry.round}-${lane}-${Date.now()}`, x: laneX(Number(lane), entry.lanes), y: LANE_Y })));
    setPos((prev) => {
      const next = { ...prev };
      crashed.forEach(([, group]) => group.forEach((seat, index) => {
        const base = prev[seat];
        if (base) next[seat] = { ...base, rot: index % 2 ? 22 : -22, scale: 1.18, dur: 0.25, ease: 'easeOut', shake: true };
      }));
      return next;
    });
    const hurt = [...crashed.flatMap(([, group]) => group), ...idle];
    setWobble(hurt);
    setGains(entry.ring_gain ?? []);
    if (entry.hp_after) setHp((prev) => ({ ...prev, ...entry.hp_after }));
    setVoided(Boolean(entry.void));
    await wait(entry.void ? 1_400 : 650);
    if (!mounted.current) return;

    // 3) 내구도가 0이 된 토큰이 떨어진다
    setPos((prev) => {
      const next = { ...prev };
      before.forEach((seat) => {
        const base = prev[seat];
        if (!base) return;
        if (!fell.includes(seat)) {
          next[seat] = { ...base, rot: 0, scale: 1, dur: 0.3, ease: 'easeOut', shake: false };
          return;
        }
        next[seat] = { ...base, y: 128, rot: (seat.charCodeAt(0) % 2 ? 1 : -1) * (110 + (Number(seat) * 37 % 90)), scale: 0.55, opacity: 0, dur: 1.1, ease: 'easeIn', shake: false };
      });
      return next;
    });
    await wait(fell.length > 0 ? 1_150 : 500);
    if (!mounted.current) return;
    setBursts([]);
    setWobble([]);
    setGains([]);
    setVoided(false);

    // 4) 살아남은 토큰이 환호하고 출발선으로 돌아온다
    const survivors = survivorsOf(entry);
    setPos((prev) => {
      const next = { ...prev };
      survivors.forEach((seat) => {
        const base = prev[seat];
        if (base) next[seat] = { ...base, scale: 1.14, dur: 0.3, ease: 'easeOut' };
      });
      return next;
    });
    await wait(650);
    if (!mounted.current) return;
    if (options.returnToLine) {
      setReturning(true);
      settle(survivors, 1.5);
    }
    await wait(options.returnToLine ? 1_600 : 100);
    if (!mounted.current) return;
    setReturning(false);
    setFlying(false);
  }, [settle]);

  return { pos, bursts, flying, returning, hp, setHp, wobble, gains, voided, settle, play };
};

// ── 서버 시계 기준 남은 초 ──
const useRemaining = (view: FlyView | null) => {
  const offset = useMemo(() => (view ? Date.parse(view.now) - Date.now() : 0), [view]);
  const [tick, setTick] = useState(0);

  useEffect(() => {
    const timer = window.setInterval(() => { setTick((value) => value + 1); }, 250);
    return () => { window.clearInterval(timer); };
  }, []);

  void tick;
  if (!view?.deadline_at || view.status !== 'active') return null;
  return Math.max(0, Math.ceil((Date.parse(view.deadline_at) - (Date.now() + offset)) / 1000));
};

// ── 하늘 장면 (호그와트의 밤하늘 · 출발선 · 길 · 토큰). 판과 다시보기가 같이 쓴다 ──
// 달과 별, 멀리 성(탑마다 창불이 깜빡인다), 둥둥 떠다니는 양초, 부엉이, 달빛에 물든 구름과 안개
const STARS = Array.from({ length: 70 }, (_, index) => ({
  left: (index * 53.7) % 100,
  top: (index * 29.3) % 46,
  size: 1 + ((index * 7) % 3),
  delay: ((index * 13) % 40) / 10,
}));

const WINDOWS: [number, number][] = [[590, 100], [610, 100], [590, 130], [610, 130], [465, 150], [748, 130], [748, 170], [470, 190], [520, 200], [580, 200], [640, 200], [700, 200], [350, 190], [872, 170], [524, 150], [669, 160]];

const Castle: React.FC = () => (
  <svg className='fl-castle' viewBox='0 0 1200 300' preserveAspectRatio='xMidYMax slice' aria-hidden>
    <g fill='currentColor'>
      <path d='M0 300 L0 262 C200 250 330 270 470 240 L760 240 C880 262 1000 246 1200 258 L1200 300 Z' />
      <rect x='420' y='170' width='360' height='75' />
      <rect x='560' y='60' width='80' height='185' />
      <polygon points='550,60 600,0 650,60' />
      <rect x='440' y='100' width='50' height='145' />
      <polygon points='432,100 465,40 498,100' />
      <rect x='720' y='90' width='56' height='155' />
      <polygon points='712,90 748,22 784,90' />
      <rect x='330' y='150' width='40' height='100' />
      <polygon points='324,150 350,100 376,150' />
      <rect x='850' y='140' width='44' height='110' />
      <polygon points='844,140 872,92 900,140' />
      <rect x='515' y='120' width='18' height='125' />
      <polygon points='511,120 524,70 537,120' />
      <rect x='660' y='130' width='18' height='115' />
      <polygon points='656,130 669,84 682,130' />
      <rect x='776' y='188' width='76' height='10' />
      {Array.from({ length: 16 }, (_, index) => <rect key={index} x={420 + (index * 24)} y='162' width='12' height='8' />)}
    </g>
    <g className='fl-castle__windows'>
      {WINDOWS.map(([x, y], index) => <rect key={`${x}-${y}`} x={x} y={y} width='6' height='10' style={{ animationDelay: `${(index * 0.7) % 5}s` }} />)}
    </g>
  </svg>
);

const CANDLES = Array.from({ length: 14 }, (_, index) => ({
  left: 4 + ((index * 37.3) % 92),
  top: 5 + ((index * 23.1) % 24),
  delay: (index % 5) * 0.6,
  drift: 6 + ((index * 5) % 10),
}));

// ── 배경 여러 개 (호그와트 분위기): 날아갈 때마다 이 안에서 무작위로 바뀐다 ──
const SCENE_KEYS = ['castle', 'forest', 'pitch', 'lake', 'aurora'] as const;
type SceneKey = typeof SCENE_KEYS[number];

// 라운드마다 배경이 바뀐다. 방 번호와 라운드로 정해져서, 게임 중·다시 보기·MVP에서 그 라운드는 항상 같은 배경이다 (바로 앞 라운드와는 다르게)
const sceneFor = (sessionId: string, round: number): SceneKey => {
  let scene: SceneKey = 'castle';
  const base = (Number(sessionId.slice(-6)) || 7) * 31;
  for (let each = 1; each <= round; each += 1) {
    const others = SCENE_KEYS.filter((key) => key !== scene);
    scene = others[(base + (each * 97)) % others.length] ?? 'castle';
  }
  return scene;
};

const Fireflies: React.FC<{ count: number; color?: string }> = ({ count, color = '#d8ff8a' }) => (
  <>
    {Array.from({ length: count }, (_, index) => (
      <motion.span
        key={index}
        className='fl-firefly'
        style={{ left: `${6 + ((index * 41) % 88)}%`, top: `${38 + ((index * 23) % 40)}%`, background: color, boxShadow: `0 0 8px 2px ${color}` }}
        animate={{ y: [0, -14, 6, -8, 0], x: [0, 10, -6, 4, 0], opacity: [0.2, 1, 0.4, 1, 0.2] }}
        transition={{ duration: 5 + (index % 4), repeat: Infinity, ease: 'easeInOut', delay: (index % 5) * 0.5 }}
      />
    ))}
  </>
);

// 금지된 숲: 짙은 초록 하늘과 소나무 실루엣, 반딧불
const Pines: React.FC<{ className: string; shift: number; tall: number }> = ({ className, shift, tall }) => (
  <svg className={className} viewBox='0 0 1200 300' preserveAspectRatio='none' aria-hidden>
    <g fill='currentColor'>
      <rect x='0' y='290' width='1200' height='10' />
      {Array.from({ length: 24 }, (_, index) => {
        const x = (index * 52) + shift;
        const height = tall + ((index * 37) % 60);
        return <polygon key={index} points={`${x},300 ${x + 26},${300 - height} ${x + 52},300`} />;
      })}
    </g>
  </svg>
);

const ForestScene: React.FC = () => (
  <>
    <span className='fl-moon fl-moon--small' />
    <Pines className='fl-pines fl-pines--far' shift={-10} tall={150} />
    <Pines className='fl-pines fl-pines--near' shift={20} tall={200} />
    <span className='fl-mist fl-mist--a' />
    <Fireflies count={16} />
  </>
);

// 해질녘 퀴디치 경기장: 노을 하늘, 골대 세 개, 관중석 실루엣
const Hoop: React.FC<{ left: string; height: number }> = ({ left, height }) => (
  <svg className='fl-hoop' style={{ left }} viewBox='0 0 60 200' aria-hidden>
    <rect x='28' y={200 - height} width='4' height={height} fill='#2b1b3d' />
    <ellipse cx='30' cy={200 - height} rx='24' ry='24' fill='none' stroke='#f3d36b' strokeWidth='4' />
  </svg>
);

const PitchScene: React.FC = () => (
  <>
    <span className='fl-sun' />
    <svg className='fl-stands' viewBox='0 0 1200 200' preserveAspectRatio='none' aria-hidden>
      <g fill='currentColor'>
        <path d='M0 200 L0 120 L120 100 L120 70 L250 90 L250 60 L420 80 L420 110 L700 100 L700 70 L880 90 L880 50 L1050 80 L1050 110 L1200 100 L1200 200 Z' />
      </g>
    </svg>
    <Hoop left='18%' height={120} />
    <Hoop left='48%' height={150} />
    <Hoop left='78%' height={120} />
    <Fireflies count={8} color='#ffd9a0' />
  </>
);

// 검은 호수: 달빛 아래 물결, 먼 산 실루엣과 작은 배의 불빛
const LakeScene: React.FC = () => (
  <>
    <span className='fl-moon' />
    <svg className='fl-ridge' viewBox='0 0 1200 220' preserveAspectRatio='none' aria-hidden>
      <path fill='currentColor' d='M0 220 L0 150 L130 90 L230 140 L380 60 L520 130 L650 80 L800 150 L950 70 L1080 130 L1200 100 L1200 220 Z' />
    </svg>
    <div className='fl-water'>
      {[0, 1, 2, 3, 4, 5].map((index) => <span key={index} style={{ top: `${12 + (index * 14)}%`, animationDelay: `${index * 0.6}s` }} />)}
    </div>
    <span className='fl-boat fl-boat--a' />
    <span className='fl-boat fl-boat--b' />
  </>
);

// 천문탑 위 오로라: 초록·청록·보라색 띠가 일렁인다
const AuroraScene: React.FC = () => (
  <>
    {STARS.slice(0, 50).map((star, index) => (
      <span key={index} className='fl-star' style={{ left: `${star.left}%`, top: `${star.top}%`, width: star.size, height: star.size, animationDelay: `${star.delay}s` }} />
    ))}
    {[0, 1, 2].map((index) => (
      <motion.span
        key={index}
        className={`fl-aurora fl-aurora--${index}`}
        animate={{ x: ['-8%', '8%', '-8%'], skewX: [-14, 10, -14], opacity: [0.55, 0.9, 0.55] }}
        transition={{ duration: 9 + (index * 3), repeat: Infinity, ease: 'easeInOut' }}
      />
    ))}
    <svg className='fl-ridge' viewBox='0 0 1200 220' preserveAspectRatio='none' aria-hidden>
      <path fill='currentColor' d='M0 220 L0 170 L200 130 L360 160 L560 110 L760 150 L980 120 L1200 160 L1200 220 Z' />
    </svg>
  </>
);

const CastleScene: React.FC = () => (
  <>
    <span className='fl-moon' />
    {STARS.map((star, index) => (
      <span key={index} className='fl-star' style={{ left: `${star.left}%`, top: `${star.top}%`, width: star.size, height: star.size, animationDelay: `${star.delay}s` }} />
    ))}
    <Castle />
    <span className='fl-mist fl-mist--a' />
    <span className='fl-mist fl-mist--b' />

    {[0, 1, 2, 3, 4].map((index) => (
      <motion.span
        key={index}
        className={`fl-cloud fl-cloud--${index % 3}`}
        style={{ top: `${14 + ((index * 17) % 44)}%` }}
        initial={{ x: `${-30 + (index * 26)}vw` }}
        animate={{ x: ['-30vw', '120vw'] }}
        transition={{ duration: 60 + (index * 11), repeat: Infinity, ease: 'linear', delay: -index * 9 }}
      />
    ))}

    {CANDLES.map((candle, index) => (
      <motion.span
        key={index}
        className='fl-candle'
        style={{ left: `${candle.left}%`, top: `${candle.top}%` }}
        animate={{ y: [0, -candle.drift, 0], x: [0, candle.drift / 2, 0] }}
        transition={{ duration: 5 + (index % 4), repeat: Infinity, ease: 'easeInOut', delay: candle.delay }}
      />
    ))}

    {[0, 1].map((index) => (
      <motion.span
        key={index}
        className='fl-owl'
        style={{ top: `${9 + (index * 11)}%` }}
        initial={{ x: '-12vw' }}
        animate={{ x: ['-12vw', '112vw'], y: [0, -14, 6, -10, 0] }}
        transition={{ duration: 34 + (index * 17), repeat: Infinity, ease: 'linear', delay: index * 15 }}
      >
        🦉
      </motion.span>
    ))}
  </>
);

const SCENE_VIEWS: Record<SceneKey, React.FC> = { castle: CastleScene, forest: ForestScene, pitch: PitchScene, lake: LakeScene, aurora: AuroraScene };

// 배경이 바뀌면 이전 배경은 서서히 사라지고 새 배경이 나타난다
const Backdrop: React.FC<{ scene: SceneKey }> = React.memo(({ scene }) => {
  const View = SCENE_VIEWS[scene];
  return (
    <div className='fl-backdrop' aria-hidden>
      <AnimatePresence initial={false}>
        <motion.div key={scene} className={`fl-scene fl-scene--${scene}`} initial={{ opacity: 0 }} animate={{ opacity: 1 }} exit={{ opacity: 0 }} transition={{ duration: 1.1 }}>
          <View />
        </motion.div>
      </AnimatePresence>
    </div>
  );
});
Backdrop.displayName = 'Backdrop';

interface SkyProps {
  players: FlyPlayer[];
  pos: Record<string, TokenPos>;
  bursts: Burst[];
  lanes: number;
  routes: string[];
  selectable: boolean;
  mine: number | null;
  showChosen: boolean;
  highlight?: number[];
  // 처음 내구도, 자리 → 지금 내구도, 휘청이는·고리로 회복한 자리, 금빛 고리 길 번호
  durability?: number;
  hp?: Record<string, number>;
  wobble?: string[];
  gains?: string[];
  ring?: number | null;
  // 날아가는 동안: 길 표시는 사라지고 배경이 함께 흘러간다
  moving?: boolean;
  returning?: boolean;
  scene?: SceneKey;
  onPick?: (lane: number) => void;
  children?: React.ReactNode;
  size?: number;
}

// 아바타 밑 빗자루: 내구도가 깎이면 휘청이고, 0이면 부러져 함께 추락한다
export const Broom: React.FC<{ hp: number; base: number; wobble: boolean; size: number }> = ({ hp, base, wobble, size }) => (
  <motion.span
    className={['fl-broom', hp <= 1 && base > 1 && 'is-low', hp <= 0 && 'is-broken'].filter(Boolean).join(' ')}
    style={{ width: size * 1.35 }}
    animate={wobble ? { rotate: [0, -14, 11, -8, 5, 0], y: [0, 3, -2, 2, 0, 0] } : { rotate: 0, y: 0 }}
    transition={{ duration: 0.9, ease: 'easeInOut' }}
    aria-hidden
  >
    <svg viewBox='0 0 100 22'>
      <rect x='2' y='9' width='62' height='4' rx='2' className='fl-broom__stick' />
      <path d='M62 11 C72 2 90 1 98 4 C94 8 94 14 98 18 C90 21 72 20 62 11 Z' className='fl-broom__bristle' />
      <path d='M70 8 L92 6 M70 14 L92 16 M70 11 L94 11' className='fl-broom__line' />
    </svg>
  </motion.span>
);

// 이름 밑 배지: 빗자루 아이콘 | 지금 내구도/처음 내구도
export const HpBadge: React.FC<{ hp: number; base: number; gained: boolean }> = ({ hp, base, gained }) => (
  <span className={['fl-hp', hp <= 1 && base > 1 && 'is-low', gained && 'is-gain'].filter(Boolean).join(' ')}>
    <svg viewBox='0 0 100 22' aria-hidden>
      <rect x='2' y='9' width='62' height='4' rx='2' />
      <path d='M62 11 C72 2 90 1 98 4 C94 8 94 14 98 18 C90 21 72 20 62 11 Z' />
    </svg>
    <b>{Math.max(hp, 0)}/{base}</b>
    {gained && <motion.em initial={{ opacity: 0, y: 4 }} animate={{ opacity: [0, 1, 1, 0], y: [4, -10, -14, -22] }} transition={{ duration: 1.5 }}>+1</motion.em>}
  </span>
);

const STREAKS = Array.from({ length: 14 }, (_, index) => ({ left: 4 + ((index * 37) % 92), delay: ((index * 17) % 10) / 10, length: 8 + ((index * 5) % 12) }));

const Sky: React.FC<SkyProps> = ({ players, pos, bursts, lanes, routes, selectable, mine, showChosen, highlight, durability = 2, hp = {}, wobble = [], gains = [], ring = null, moving = false, returning = false, scene = 'castle', onPick, children, size = 64 }) => (
  <div className={['fl-sky', moving && 'is-moving', returning && 'is-returning'].filter(Boolean).join(' ')} style={{ '--fl-size': `${size}px` } as React.CSSProperties}>
    <Backdrop scene={scene} />
    <div className='fl-streaks' aria-hidden>
      {STREAKS.map((streak, index) => <span key={index} style={{ left: `${streak.left}%`, height: `${streak.length}%`, animationDelay: `${streak.delay}s` }} />)}
    </div>

    {lanes > 0 && (
      <div className='fl-lanes' style={{ top: `${LANE_Y - 8}%` }}>
        {Array.from({ length: lanes }, (_, index) => index + 1).map((lane) => (
          <button
            key={lane}
            type='button'
            className={['fl-lane', mine === lane && 'is-mine', selectable && 'is-open', ring === lane && 'is-ring'].filter(Boolean).join(' ')}
            style={{ left: `${laneX(lane, lanes) - (LANE_W(lanes) / 2)}%`, width: `${LANE_W(lanes)}%`, '--fl-i': lane } as React.CSSProperties}
            disabled={!selectable}
            onClick={() => { onPick?.(lane); }}
          >
            <b>{lane}</b>
            <small>{routes[lane - 1]}</small>
            {ring === lane && <i className='fl-lane__ring' aria-hidden />}
            {ring === lane && <em className='fl-lane__tag'><FormattedMessage id='flying.ring' defaultMessage='Golden ring +1' /></em>}
          </button>
        ))}
      </div>
    )}

    {players.map((player) => {
      const at = pos[String(player.seat)];
      if (!at) return null;
      return (
        <motion.div
          key={player.seat}
          className={['fl-token', highlight?.includes(player.seat) && 'is-hot', at.shake && 'is-shake', wobble.includes(String(player.seat)) && 'is-wobble'].filter(Boolean).join(' ')}
          initial={false}
          animate={{ left: `${at.x}%`, top: `${at.y}%`, rotate: at.rot, scale: at.scale, opacity: at.opacity }}
          transition={{ duration: at.dur, ease: at.ease }}
        >
          <div>
            <motion.div
              animate={at.y === LINE_Y || at.y === LANE_Y ? { y: [0, -5, 0] } : { y: 0 }}
              transition={{ duration: 2.2 + ((player.seat % 4) * 0.3), repeat: Infinity, ease: 'easeInOut' }}
            >
              <GameToken
                accountId={player.account_id}
                avatar={player.avatar}
                name={player.name}
                house={player.house}
                size={size}
                footer={<HpBadge hp={hp[String(player.seat)] ?? player.hp} base={durability} gained={gains.includes(String(player.seat))} />}
              >
                <Broom hp={hp[String(player.seat)] ?? player.hp} base={durability} wobble={wobble.includes(String(player.seat))} size={size} />
                {showChosen && player.chosen && player.alive && <span className='fl-token__done'>✓ <FormattedMessage id='flying.chosen' defaultMessage='Ready' /></span>}
              </GameToken>
            </motion.div>
          </div>
        </motion.div>
      );
    })}

    <AnimatePresence>
      {bursts.map((burst) => (
        <motion.span
          key={burst.id}
          className='fl-burst'
          style={{ left: `${burst.x}%`, top: `${burst.y}%` }}
          initial={{ scale: 0.2, opacity: 1, rotate: -20 }}
          animate={{ scale: [0.2, 1.7, 1.3], opacity: [1, 1, 0], rotate: [-20, 14, 0] }}
          exit={{ opacity: 0 }}
          transition={{ duration: 1.1, ease: 'easeOut' }}
        >
          💥
          {Array.from({ length: 10 }, (_, index) => (
            <motion.b
              key={index}
              className='fl-burst__bit'
              initial={{ x: 0, y: 0, opacity: 1, rotate: 0 }}
              animate={{ x: Math.cos(index * 0.63) * (60 + ((index * 17) % 40)), y: (Math.sin(index * 0.63) * (50 + ((index * 13) % 30))) - 26, opacity: 0, rotate: (index % 2 ? 1 : -1) * 220 }}
              transition={{ duration: 1.1, ease: 'easeOut' }}
            >
              {index % 3 === 0 ? '🌿' : '🪶'}
            </motion.b>
          ))}
        </motion.span>
      ))}
    </AnimatePresence>
    {children}
  </div>
);

// ── 다시보기: 한 라운드를 처음부터 틀어 준다 (라운드 되돌아보기 · MVP 장면) ──
const Replay: React.FC<{ view: FlyView; entry: RoundEntry; highlight?: number[]; size?: number; scene?: SceneKey }> = ({ view, entry, highlight, size = 52, scene = 'castle' }) => {
  const player = useRoundPlayer();
  const [run, setRun] = useState(0);
  const { settle, play, setHp } = player;
  const seatsKey = entry.alive_before.join(',');

  useEffect(() => {
    let active = true;
    settle(entry.alive_before, 0.01);
    if (entry.hp_before) setHp(entry.hp_before);
    let again = 0;
    const timer = window.setTimeout(() => {
      // 끝나면 잠깐 쉬었다가 처음부터 계속 되풀이한다
      if (active) void play(entry, { returnToLine: false }).then(() => { if (active) again = window.setTimeout(() => { setRun((value) => value + 1); }, 1_800); return true; });
    }, 700);
    return () => {
      active = false;
      window.clearTimeout(timer);
      window.clearTimeout(again);
    };
    // 장면이 바뀌면 처음부터
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [entry.round, seatsKey, run]);

  return (
    <div className='fl-replay'>
      <Sky
        players={view.players}
        pos={player.pos}
        bursts={player.bursts}
        lanes={0}
        routes={entry.routes}
        selectable={false}
        mine={null}
        showChosen={false}
        highlight={highlight}
        durability={view.durability}
        hp={player.hp}
        wobble={player.wobble}
        gains={player.gains}
        moving={player.flying}
        scene={scene}
        size={size}
      />
    </div>
  );
};

// ── 올라가는 숫자 ──
const CountUp: React.FC<{ to: number; delay?: number }> = ({ to, delay = 0 }) => {
  const [value, setValue] = useState(0);

  useEffect(() => {
    const controls = animate(0, to, { duration: 1.1, delay, ease: 'easeOut', onUpdate: (latest) => { setValue(Math.round(latest)); } });
    return () => { controls.stop(); };
  }, [to, delay]);

  return <>{value}</>;
};

const RewardLine: React.FC<{ reward: Reward | null | undefined; currency: string; test: boolean; delay: number }> = ({ reward, currency, test, delay }) => {
  if (test) {
    return <small className='fl-reward fl-reward--none'><FormattedMessage id='flying.test_play' defaultMessage='Test play: no rewards' /></small>;
  }
  if (!reward) return null;
  return (
    <span className='fl-reward'>
      <span><FormattedMessage id='flying.points' defaultMessage='{points} pts' values={{ points: <CountUp to={reward.points} delay={delay} /> }} /></span>
      {reward.money > 0 && <span><CountUp to={reward.money} delay={delay + 0.15} /> {currency}</span>}
      {reward.items.map((item) => <span key={item} className='fl-reward__item'>{item}</span>)}
    </span>
  );
};

// ── 시상대 ──
const Podium: React.FC<{ view: FlyView; finish: FinishView; onNext: () => void }> = ({ view, finish, onNext }) => {
  const intl = useIntl();
  const byseat = useMemo(() => new Map(view.players.map((player) => [player.seat, player])), [view.players]);
  const groups = finish.ranks.slice(0, 3);
  // 올림픽처럼 가운데 1등, 왼쪽 2등, 오른쪽 3등
  const order = [groups[1], groups[0], groups[2]];
  const delayOf = (rank: number) => (rank === 3 ? 0.4 : rank === 2 ? 1.4 : 2.4);
  const mine = view.me !== null ? view.players.find((player) => player.seat === view.me) : null;
  const rest = finish.ranks.slice(3).flatMap((group) => group.seats.map((seat) => ({ rank: group.rank, seat })));
  const myGroup = mine ? finish.ranks.find((group) => group.seats.includes(mine.seat)) : null;
  // 순위가 모두 발표된 뒤에 보상이 올라가며 나타나고, 그다음에 [다음]이 뜬다
  const [rewardsOn, setRewardsOn] = useState(false);
  const [ready, setReady] = useState(false);

  useEffect(() => {
    const first = window.setTimeout(() => { setRewardsOn(true); }, 3_900);
    const second = window.setTimeout(() => { setReady(true); }, 6_300);
    return () => { window.clearTimeout(first); window.clearTimeout(second); };
  }, []);

  return (
    <motion.div className='fl-result' initial={{ opacity: 0 }} animate={{ opacity: 1 }} exit={{ opacity: 0 }}>
      <motion.h2 initial={{ y: -30, opacity: 0 }} animate={{ y: 0, opacity: 1 }} transition={{ type: 'spring', stiffness: 160, damping: 14 }}>
        <FormattedMessage id='flying.result_title' defaultMessage='Results' />
      </motion.h2>

      <div className='fl-podium'>
        {order.map((group, slot) => {
          if (!group) return <div key={slot} className='fl-podium__slot fl-podium__slot--empty' />;
          return (
            <div key={group.rank} className={`fl-podium__slot fl-podium__slot--${group.rank}`}>
              <motion.div
                className='fl-podium__tokens'
                initial={{ y: -260, opacity: 0, scale: 0.6 }}
                animate={{ y: 0, opacity: 1, scale: 1 }}
                transition={{ type: 'spring', stiffness: 110, damping: 11, delay: delayOf(group.rank) }}
              >
                {group.rank === 1 && <motion.span className='fl-podium__crown' animate={{ rotate: [-8, 8, -8], y: [0, -4, 0] }} transition={{ duration: 2, repeat: Infinity }}>👑</motion.span>}
                {group.seats.map((seat) => {
                  const player = byseat.get(seat);
                  return player ? (
                    <GameToken key={seat} accountId={player.account_id} avatar={player.avatar} name={player.name} house={player.house} size={group.rank === 1 ? 84 : 64} />
                  ) : null;
                })}
              </motion.div>
              <motion.div
                className='fl-podium__stand'
                initial={{ scaleY: 0 }}
                animate={{ scaleY: 1 }}
                style={{ originY: 1 }}
                transition={{ duration: 0.6, delay: delayOf(group.rank) - 0.4, ease: 'easeOut' }}
              >
                <b>{group.rank}</b>
                {group.seats.length > 1 && <small><FormattedMessage id='flying.joint' defaultMessage='Joint' /></small>}
              </motion.div>
              {/* 보상은 시상대(1·2·3) 바로 아래 */}
              <div className='fl-podium__reward'>
                {rewardsOn && <RewardLine reward={finish.rewards[String(group.seats[0])]} currency={finish.currency} test={finish.test} delay={0.1} />}
              </div>
            </div>
          );
        })}
      </div>

      {myGroup && myGroup.rank > 3 && (
        <p className='fl-result__mine'>
          <FormattedMessage id='flying.my_rank' defaultMessage='Your rank: {rank}' values={{ rank: myGroup.rank }} />
          {' '}
          {rewardsOn && <RewardLine reward={finish.rewards[String(mine?.seat)]} currency={finish.currency} test={finish.test} delay={0.1} />}
        </p>
      )}
      {rest.length > 0 && (
        <p className='fl-result__rest'>
          {rest.map(({ rank, seat }) => `${intl.formatMessage(messages.rankN, { rank })} ${byseat.get(seat)?.name ?? ''}`).join(' · ')}
        </p>
      )}

      {/* 자리를 미리 잡아 둔다: 버튼이 나타날 때 화면이 밀려 올라가 글자를 가리지 않게 */}
      <motion.button
        type='button'
        className='fl-big-button'
        initial={false}
        animate={{ opacity: ready ? 1 : 0, y: ready ? 0 : 12 }}
        style={{ pointerEvents: ready ? 'auto' : 'none' }}
        tabIndex={ready ? 0 : -1}
        aria-hidden={!ready}
        onClick={onNext}
      >
        <FormattedMessage id='flying.next' defaultMessage='Next' />
      </motion.button>
    </motion.div>
  );
};

// ── 오늘의 MVP ──
const Mvp: React.FC<{ view: FlyView; finish: FinishView; sessionId: string; onLeave: () => void; onClose: () => void }> = ({ view, finish, sessionId, onLeave, onClose }) => {
  const [index, setIndex] = useState(0);
  const scene = finish.mvp[index];
  const entry = scene ? view.history.find((each) => each.round === scene.round) : undefined;
  const names = scene ? scene.seats.map((seat) => view.players.find((player) => player.seat === seat)?.name).filter(Boolean).join(', ') : '';

  return (
    <motion.div className='fl-result fl-result--mvp' initial={{ opacity: 0 }} animate={{ opacity: 1 }} exit={{ opacity: 0 }}>
      <motion.h2 initial={{ scale: 0.4, opacity: 0 }} animate={{ scale: 1, opacity: 1 }} transition={{ type: 'spring', stiffness: 180, damping: 12 }}>
        🏆 <FormattedMessage id='flying.mvp' defaultMessage="Today's MVP" />
      </motion.h2>

      {scene && entry ? (
        <>
          <AnimatePresence mode='wait'>
            <motion.div key={`${scene.kind}-${scene.round}-${index}`} className='fl-mvp__card' initial={{ opacity: 0, y: 16 }} animate={{ opacity: 1, y: 0 }} exit={{ opacity: 0, y: -16 }}>
              <small className='game-stage__eyebrow'><FormattedMessage id='flying.mvp_scene' defaultMessage='#{rank} · Round {round}' values={{ rank: index + 1, round: scene.round }} /></small>
              <strong>{scene.title}</strong>
              <span className='fl-mvp__names'>{names}</span>
              <p>{scene.text}</p>
            </motion.div>
          </AnimatePresence>
          <Replay view={view} entry={entry} highlight={scene.seats} scene={sceneFor(sessionId, scene.round)} />
          {finish.mvp.length > 1 && (
            <div className='fl-mvp__chips'>
              {finish.mvp.map((each, position) => (
                <button key={`${each.kind}-${each.round}-${position}`} type='button' className={position === index ? 'is-on' : undefined} onClick={() => { setIndex(position); }}>
                  {position + 1}
                </button>
              ))}
            </div>
          )}
        </>
      ) : (
        <p className='fl-result__rest'><FormattedMessage id='flying.mvp_none' defaultMessage='No silly scenes this time.' /></p>
      )}

      <div className='fl-result__buttons'>
        <button type='button' className='fl-big-button fl-big-button--ghost' onClick={onClose}>
          <FormattedMessage id='flying.stay' defaultMessage='Stay and watch' />
        </button>
        <button type='button' className='fl-big-button' onClick={onLeave}>
          <FormattedMessage id='flying.leave' defaultMessage='Leave room' />
        </button>
      </div>
    </motion.div>
  );
};

// ── 채팅: 토큰 위 말풍선(최대 2개, 잠깐 보였다 사라진다) + 아래 가운데 입력창과 그 위 채팅 목록 ──
const ChatLayer: React.FC<{
  sessionId: string;
  chat: FlyChatMessage[];
  players: FlyPlayer[];
  pos: Record<string, TokenPos>;
  canChat: boolean;
  onSent: () => void;
}> = ({ sessionId, chat, players, pos, canChat, onSent }) => {
  const intl = useIntl();
  const [text, setText] = useState('');
  const [recent, setRecent] = useState<(FlyChatMessage & { at: number })[]>([]);
  const seen = useRef<Set<string> | null>(null);
  const listRef = useRef<HTMLUListElement>(null);

  // 처음 읽은 것은 이미 본 것으로, 그 뒤에 온 것만 말풍선으로
  useEffect(() => {
    if (seen.current === null) {
      seen.current = new Set(chat.map((message) => message.id));
      return;
    }
    const fresh = chat.filter((message) => !seen.current?.has(message.id));
    if (fresh.length === 0) return;
    fresh.forEach((message) => seen.current?.add(message.id));
    const now = Date.now();
    setRecent((prev) => [...prev, ...fresh.map((message) => ({ ...message, at: now }))].slice(-2));
  }, [chat]);

  useEffect(() => {
    if (recent.length === 0) return undefined;
    const timer = window.setTimeout(() => {
      setRecent((prev) => prev.filter((message) => Date.now() - message.at < BUBBLE_MS));
    }, BUBBLE_MS);
    return () => { window.clearTimeout(timer); };
  }, [recent]);

  // 새 채팅이 오면 맨 아래로
  useEffect(() => {
    if (listRef.current) listRef.current.scrollTop = listRef.current.scrollHeight;
  }, [chat]);

  const submit = useCallback((event: React.FormEvent) => {
    event.preventDefault();
    const value = text.trim();
    if (!value) return;
    setText('');
    apiRequestPost(`v1/system/sessions/${sessionId}/chat`, { text: value })
      .then(() => {
        onSent();
        return true;
      })
      .catch(() => {
        onSent();
      });
  }, [sessionId, text, onSent]);

  return (
    <>
      <div className='fl-bubbles' aria-live='polite'>
        <AnimatePresence>
          {recent.map((message) => {
            const speaker = players.find((player) => player.acct === message.acct);
            const at = speaker ? pos[String(speaker.seat)] : undefined;
            return (
              <motion.div
                key={message.id}
                className='fl-bubble'
                style={{ left: `${at ? at.x : 50}%`, top: `${at ? Math.max(at.y - 15, 6) : 12}%` }}
                initial={{ opacity: 0, y: 10, scale: 0.8 }}
                animate={{ opacity: 1, y: 0, scale: 1 }}
                exit={{ opacity: 0, y: -10 }}
                transition={{ duration: 0.25 }}
              >
                {message.text}
              </motion.div>
            );
          })}
        </AnimatePresence>
      </div>

      {/* 입력창 위 채팅 목록: 아바타 | 이름 : 내용 (대기방처럼, 높이는 작게, 호버할 때만 스크롤바) */}
      <ul className='fl-chatlog' ref={listRef}>
        {chat.map((message) => (
          <li key={message.id} className={message.mine ? 'is-mine' : undefined}>
            <img src={message.avatar} alt='' />
            <strong>{message.name}</strong>
            <span>: {message.text}</span>
          </li>
        ))}
      </ul>

      {canChat && (
        <form className='fl-chat-input' onSubmit={submit}>
          <input type='text' value={text} maxLength={200} placeholder={intl.formatMessage(messages.chatPlaceholder)} onChange={(event) => { setText(event.target.value); }} />
          <button type='submit' disabled={!text.trim()}>{intl.formatMessage(messages.send)}</button>
        </form>
      )}
    </>
  );
};

// ── 게임방 ──
export const FlyingStage: React.FC<{
  sessionId: string;
  name: string;
  chat: FlyChatMessage[];
  staff: boolean;
  isPlayer: boolean;
  onChanged: () => void;
}> = ({ sessionId, name, chat, staff, isPlayer, onChanged }) => {
  const history = useHistory();
  const [view, setView] = useState<FlyView | null>(null);
  const [mineLocal, setMineLocal] = useState<number | null>(null);
  const [shown, setShown] = useState<number | null>(null);
  const [ending, setEnding] = useState<'none' | 'overlay' | 'podium' | 'mvp' | 'closed'>('none');
  const [review, setReview] = useState<RoundEntry | null>(null);
  const [reviewRun, setReviewRun] = useState(0);
  // 지금 틀어 주는 라운드 (그 라운드의 길 칸을 날아가는 동안 계속 보여 준다)
  const [flightEntry, setFlightEntry] = useState<RoundEntry | null>(null);
  const [scene, setScene] = useState<SceneKey>('castle');
  const player = useRoundPlayer();
  const { settle, play, setHp } = player;
  const playing = useRef(false);
  const remaining = useRemaining(view);

  // 라운드마다 배경이 호그와트의 다른 풍경으로 바뀐다 (그 라운드를 날아가기 시작할 때)
  useEffect(() => {
    if (player.flying && flightEntry) setScene(sceneFor(sessionId, flightEntry.round));
  }, [player.flying, flightEntry, sessionId]);

  // 날아가지 않는 동안: 방금까지 본 라운드의 배경 (새로 들어온 사람·다시 보기 포함)
  useEffect(() => {
    if (review) setScene(sceneFor(sessionId, review.round));
    else if (!player.flying && shown !== null) setScene(sceneFor(sessionId, shown));
  }, [player.flying, shown, review, sessionId]);

  useStageLayout(true);

  const load = useCallback(() => {
    apiRequestGet<ViewResponse>(`v1/system/sessions/${sessionId}/view`)
      .then((response) => {
        if (response.view) setView(response.view);
        return response;
      })
      .catch(() => undefined);
  }, [sessionId]);

  useEffect(() => {
    load();
    const timer = window.setInterval(load, view?.status === 'finished' ? FINISHED_REFRESH_MS : REFRESH_MS);
    return () => { window.clearInterval(timer); };
  }, [load, view?.status]);

  // n 라운드를 본 뒤 서 있는 자리들 (마지막 라운드가 끝났으면 우승자)
  const standing = useCallback((current: FlyView, count: number): string[] => {
    if (count === 0) return current.players.map((each) => String(each.seat));
    if (current.finish && count >= current.history.length) return (current.finish.ranks[0]?.seats ?? []).map(String);
    const entry = current.history[count - 1];
    return entry ? survivorsOf(entry) : [];
  }, []);

  // 처음 들어왔을 때는 지금 상태 그대로, 새 라운드 기록이 생기면 그 라운드를 틀어 준다
  useEffect(() => {
    if (!view) return;
    if (shown === null) {
      setShown(view.history.length);
      settle(standing(view, view.history.length), 0.01);
      setHp(Object.fromEntries(view.players.map((each) => [String(each.seat), each.hp])));
      if (view.finish) setEnding('closed');
      return;
    }
    if (playing.current || view.history.length <= shown) return;
    const entry = view.history[shown];
    if (!entry) return;

    playing.current = true;
    setMineLocal(null);
    setFlightEntry(entry);
    const last = shown + 1 >= view.history.length && Boolean(view.finish);
    play(entry, { returnToLine: !last })
      .then(() => {
        playing.current = false;
        setFlightEntry(null);
        setShown(shown + 1);
        if (last) setEnding('overlay');
        return true;
      })
      .catch(() => {
        playing.current = false;
        setFlightEntry(null);
      });
  }, [view, shown, play, settle, setHp, standing]);

  // 끝난 방: 고른 라운드를 메인 화면에서 처음부터 다시 틀어 준다
  useEffect(() => {
    if (!review) return undefined;
    let active = true;
    playing.current = true;
    settle(review.alive_before, 0.01);
    if (review.hp_before) setHp(review.hp_before);
    const timer = window.setTimeout(() => {
      if (!active) return;
      play(review, { returnToLine: false })
        .catch(() => undefined)
        .finally(() => { playing.current = false; });
    }, 700);
    return () => {
      active = false;
      window.clearTimeout(timer);
      playing.current = false;
    };
  }, [review, reviewRun, settle, setHp, play]);

  // 다시보기를 마치면 우승자가 선 모습으로
  const stopReview = useCallback(() => {
    setReview(null);
    if (view) {
      settle(standing(view, view.history.length), 0.6);
      setHp(Object.fromEntries(view.players.map((each) => [String(each.seat), each.hp])));
    }
  }, [view, settle, setHp, standing]);

  // 끝났다 → 검은 막에 '종료!!' → 시상대
  useEffect(() => {
    if (ending !== 'overlay') return undefined;
    const timer = window.setTimeout(() => { setEnding('podium'); }, 2_600);
    return () => { window.clearTimeout(timer); };
  }, [ending]);

  const pick = useCallback((lane: number) => {
    if (!view) return;
    setMineLocal(lane);
    sendCommand({ session_id: sessionId, command: view.commands.fly, args: String(lane) })
      .then(() => {
        load();
        return true;
      })
      .catch(() => {
        setMineLocal(null);
      });
  }, [view, sessionId, load]);

  if (!view) return null;

  const me = view.me !== null ? view.players.find((each) => each.seat === view.me) : undefined;
  const choosing = view.status === 'active' && !player.flying && shown !== null && view.history.length === shown;
  const canPick = choosing && Boolean(me?.alive);
  const myLane = mineLocal ?? view.my_choice;
  const aliveCount = view.players.filter((each) => each.alive).length;
  const shownEntry = review ?? flightEntry ?? view.history[(shown ?? 1) - 1];
  const lanes = review ?? flightEntry ? (review ?? flightEntry)?.lanes ?? 0 : choosing ? view.lanes : (shownEntry?.lanes ?? 0);
  const routes = review ?? flightEntry ? (review ?? flightEntry)?.routes ?? [] : choosing ? view.routes : (shownEntry?.routes ?? []);
  const finished = view.status === 'finished' && ending !== 'none';
  const finish = view.finish;

  const total = view.round_seconds || 30;

  return createPortal(
    <div className='game-stage game-stage--flying' role='region' aria-label={name}>
      {/* 맨 위: 라운드 · 제한 시간 · 생존 */}
      <header className='fl-top'>
        <span className='fl-chip'>
          {review ? <FormattedMessage id='flying.round' defaultMessage='Round {round}' values={{ round: review.round }} /> : view.status === 'finished' ? <FormattedMessage id='flying.finished' defaultMessage='Finished' /> : <FormattedMessage id='flying.round' defaultMessage='Round {round}' values={{ round: view.round }} />}
        </span>
        {remaining !== null && choosing && (
          <span className={remaining <= 5 ? 'fl-timer is-low' : 'fl-timer'}>
            <span className='fl-timer__bar'><motion.i animate={{ width: `${Math.min(100, (remaining / total) * 100)}%` }} transition={{ duration: 0.3 }} /></span>
            <b>{remaining}</b>
          </span>
        )}
        <span className='fl-chip'><FormattedMessage id='flying.alive' defaultMessage='{count} alive' values={{ count: aliveCount }} /></span>
        {!me && <span className='fl-chip fl-chip--dim'><FormattedMessage id='flying.spectating' defaultMessage='Spectating' /></span>}
        {me && !me.alive && view.status === 'active' && <span className='fl-chip fl-chip--dim'><FormattedMessage id='flying.fallen' defaultMessage='You fell. Watching' /></span>}
        <button type='button' className='fl-exit' onClick={() => { history.push('/system/group'); }}>
          <FormattedMessage id='flying.exit' defaultMessage='Exit' />
        </button>
      </header>

      <Sky
        players={view.players}
        pos={player.pos}
        bursts={player.bursts}
        lanes={view.status === 'active' && isPlayer && !review ? lanes : 0}
        routes={routes}
        selectable={canPick}
        mine={review ?? flightEntry ? ((review ?? flightEntry)?.choices[String(view.me)] ?? null) : choosing ? myLane : (shownEntry?.choices[String(view.me)] ?? null)}
        showChosen={choosing}
        durability={view.durability}
        hp={player.hp}
        wobble={player.wobble}
        gains={player.gains}
        ring={review ?? flightEntry ? (review ?? flightEntry)?.ring ?? null : choosing ? view.ring : (shownEntry?.ring ?? null)}
        moving={player.flying}
        returning={player.returning}
        scene={scene}
        onPick={pick}
      >
        <AnimatePresence>
          {player.voided && (
            <motion.p key='void' className='fl-void' initial={{ opacity: 0, scale: 0.7 }} animate={{ opacity: 1, scale: 1 }} exit={{ opacity: 0 }} transition={{ type: 'spring', stiffness: 180, damping: 14 }}>
              <FormattedMessage id='flying.void' defaultMessage='Everyone would fall — this round is void!' />
            </motion.p>
          )}
          {choosing && (
            <motion.p
              key={view.round}
              className='fl-where'
              initial={{ opacity: 0, scale: 0.7, y: 20 }}
              animate={{ opacity: 1, scale: 1, y: 0 }}
              exit={{ opacity: 0, y: -20 }}
              transition={{ type: 'spring', stiffness: 180, damping: 14 }}
            >
              {canPick ? <FormattedMessage id='flying.where' defaultMessage='Where to fly?' /> : <FormattedMessage id='flying.waiting' defaultMessage='The others are choosing…' />}
            </motion.p>
          )}
        </AnimatePresence>
      </Sky>

      {/* 끝난 방: 라운드별로 다시 보기 · 결과 다시 보기 */}
      {view.status === 'finished' && ending === 'closed' && (
        <div className='fl-review'>
          <span><FormattedMessage id='flying.rounds' defaultMessage='Rounds' /></span>
          {view.history.map((entry) => (
            <button key={entry.round} type='button' className={review?.round === entry.round ? 'is-on' : undefined} onClick={() => { setReview(entry); setReviewRun((value) => value + 1); }}>{entry.round}</button>
          ))}
          {review && (
            <button type='button' className='fl-small-button' onClick={stopReview}>
              <FormattedMessage id='flying.review_end' defaultMessage='Back to the end' />
            </button>
          )}
          <button type='button' className='fl-small-button' onClick={() => { stopReview(); setEnding('podium'); }}>
            <FormattedMessage id='flying.show_results' defaultMessage='Results' />
          </button>
        </div>
      )}

      <ChatLayer sessionId={sessionId} chat={chat} players={view.players} pos={player.pos} canChat={isPlayer || staff} onSent={onChanged} />

      {/* 끝: 검은 막 '종료!!' → 시상대 → MVP */}
      <AnimatePresence>
        {finished && ending === 'overlay' && (
          <motion.div key='over' className='fl-over' initial={{ opacity: 0 }} animate={{ opacity: 1 }} exit={{ opacity: 0 }}>
            <motion.strong initial={{ scale: 3, opacity: 0, rotate: -8 }} animate={{ scale: 1, opacity: 1, rotate: 0 }} transition={{ type: 'spring', stiffness: 140, damping: 11 }}>
              <FormattedMessage id='flying.over' defaultMessage='Finished!!' />
            </motion.strong>
          </motion.div>
        )}
        {finished && finish && ending === 'podium' && (
          <motion.div key='podium' className='fl-curtain' initial={{ opacity: 0 }} animate={{ opacity: 1 }} exit={{ opacity: 0 }}>
            <Podium view={view} finish={finish} onNext={() => { setEnding('mvp'); }} />
          </motion.div>
        )}
        {finished && finish && ending === 'mvp' && (
          <motion.div key='mvp' className='fl-curtain' initial={{ opacity: 0 }} animate={{ opacity: 1 }} exit={{ opacity: 0 }}>
            <Mvp view={view} finish={finish} sessionId={sessionId} onLeave={() => { history.push('/system/group'); }} onClose={() => { setEnding('closed'); }} />
          </motion.div>
        )}
      </AnimatePresence>
    </div>,
    document.body,
  );
};

