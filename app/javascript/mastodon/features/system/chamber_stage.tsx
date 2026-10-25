// 비밀의 방 게임방 (웹 전용 이벤트, 마피아형): 해리포터 '비밀의 방' 분위기의 전체 화면 무대.
//   시작: 벽에 핏빛 글씨가 써지는 오프닝 → 역할 카드(뒤집기) 모달 2쪽 → [확인했습니다] → 본격 시작
//   가운데 원탁(뱀 문양 바닥) 둘레에 참가자 초상. 낮(횃불)에는 고발, 밤(초록 안개·바실리스크의 눈)에는 역할 행동
//   초상을 누르고 아래 행동 띠의 버튼으로 보낸다. 퇴학(진영 공개 카드)·석화(돌로 굳음)·무사한 밤은 전체 화면 연출
//   오른쪽: 내 쪽지(조사·예언·안내), 방주는 밀담·예언 만들기. 아래: 전체 채팅 / 진행 기록
// 서버: Game::Web::SecretChamber#view_for (GET /api/v1/system/sessions/:id/view), 행동은 POST /api/v1/system/commands (Game::WebCommand)
import { useCallback, useEffect, useMemo, useRef, useState } from 'react';

import { useHistory } from 'react-router-dom';

import { AnimatePresence, motion } from 'framer-motion';
import { createPortal } from 'react-dom';

import { apiRequestGet, apiRequestPost } from 'mastodon/api';
import { GameIcon } from 'mastodon/components/game_icons';

import { sendCommand } from './board';
import { BEAST_EYE, BED, CRYSTAL_BALL, DOOR, ENVELOPE, FOOTPRINT, LANTERN, OWL, SAND_SNAKE, SCROLL_TIED, SEA_SERPENT, SNAKE_SPIRAL, SNAKE_TONGUE } from './chamber_art';
import { TokenAvatar } from './game_token';
import { useStageLayout } from './lobby';

// ── 화면 데이터 ──
interface CPlayer {
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

interface COut { seat: number; role: string; by: 'vote' | 'petrify' | 'forfeit' | string; day: number; role_name: string; dark: boolean }

interface CView {
  phase: 'recruit' | 'day' | 'night' | 'finished' | null;
  day: number;
  phase_no: number;
  max_phases: number;
  deadline_at: string | null;
  ends_at: string | null;
  status: string;
  winner: 'light' | 'dark' | 'draw' | null;
  me: number | null;
  alive_me: boolean;
  spectator: boolean;
  faction_light: string;
  faction_dark: string;
  traitor_name: string;
  traitor_count: number;
  role_names: Record<string, string>;
  day_minutes: number;
  night_minutes: number;
  players: CPlayer[];
  my_role: { key: string; name: string; faction: string; dark: boolean; how: string; mates: number[] } | null;
  my_vote: number | null;
  votes: Record<string, number>;
  night: { kind: 'petrify' | 'investigate' | 'protect'; picked: number | null; used?: boolean; blocked?: number | null } | null;
  petrify_picks: Record<string, number>;
  notes: { day: number; text: string }[];
  dark_chat: { name: string; text: string }[];
  prophecy: string | null;
  prophecy_kinds: { key: string; label: string; count: number }[];
  commands: Record<string, string>;
  out_log: COut[];
}

export interface CsMessage {
  id: string;
  kind: 'chat' | 'system' | 'secret';
  mine: boolean;
  name: string;
  acct: string;
  avatar: string;
  text: string;
}

const REFRESH_MS = 2_500;
const SOUND_KEY = 'ssm:cs-sound';
const OPENING = '비밀의 방이 열렸다. 후계자의 적들이여, 조심하라.';

// ── 효과음 (Web Audio, 소리 끄기 버튼을 따른다) ──
const soundOn = () => {
  try {
    return window.localStorage.getItem(SOUND_KEY) !== 'off';
  } catch {
    return true;
  }
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
const hiss = (at: number, length: number, volume: number, frequency: number) => {
  const context = audio();
  if (!context) return;
  const start = context.currentTime + at;
  const buffer = context.createBuffer(1, Math.ceil(context.sampleRate * length), context.sampleRate);
  const data = buffer.getChannelData(0);
  for (let index = 0; index < data.length; index += 1) data[index] = (Math.random() * 2 - 1) * Math.sin((index / data.length) * Math.PI);
  const source = context.createBufferSource();
  source.buffer = buffer;
  const filter = context.createBiquadFilter();
  filter.type = 'highpass';
  filter.frequency.value = frequency;
  const gain = context.createGain();
  gain.gain.value = volume;
  source.connect(filter);
  filter.connect(gain);
  gain.connect(context.destination);
  source.start(start);
};
const sfx = {
  // 뱀의 쉿 소리 (오프닝·밤)
  hiss: (at = 0) => { hiss(at, 1.4, 0.35, 3500); },
  // 낮: 종소리
  bell: (at = 0) => { [392, 523, 659].forEach((freq, index) => { tone(freq, at + (index * 0.18), 1.2, { type: 'triangle', volume: 0.12 }); }); },
  // 밤: 낮게 깔리는 소리
  night: (at = 0) => { tone(110, at, 2.2, { type: 'sawtooth', volume: 0.05, to: 70 }); hiss(at + 0.4, 1.2, 0.18, 4000); },
  // 퇴학: 쾅
  gavel: (at = 0) => { tone(160, at, 0.4, { type: 'triangle', volume: 0.5, to: 50 }); tone(120, at + 0.18, 0.5, { type: 'triangle', volume: 0.35, to: 40 }); },
  // 석화: 돌 굳는 소리
  stone: (at = 0) => { tone(80, at, 1.4, { type: 'square', volume: 0.08, to: 40 }); hiss(at, 0.8, 0.3, 900); tone(1800, at + 0.1, 0.5, { volume: 0.06, to: 600 }); },
  // 무사한 아침
  safe: (at = 0) => { [523, 659, 784, 1047].forEach((freq, index) => { tone(freq, at + (index * 0.1), 0.6, { volume: 0.12 }); }); },
  // 고른 행동 보냄
  pick: () => { tone(660, 0, 0.12, { volume: 0.12 }); tone(990, 0.08, 0.18, { volume: 0.1 }); },
  // 비밀 쪽지
  note: () => { tone(1175, 0, 0.2, { type: 'triangle', volume: 0.1 }); tone(1568, 0.12, 0.3, { type: 'triangle', volume: 0.08 }); },
  // 승리
  win: (at = 0) => { [523, 659, 784, 1047, 1319].forEach((freq, index) => { tone(freq, at + (index * 0.13), 0.9, { type: 'triangle', volume: 0.14 }); }); },
  // 아침: 닭 울음 비슷한 올라가는 소리
  rooster: (at = 0) => { tone(700, at, 0.25, { type: 'triangle', volume: 0.08, to: 1100 }); tone(1100, at + 0.25, 0.5, { type: 'triangle', volume: 0.07, to: 800 }); },
  // 밤: 바람
  wind: (at = 0) => { hiss(at, 2.4, 0.16, 500); },
  // 반짝
  sparkle: (at = 0) => { [1568, 2093, 2637].forEach((freq, index) => { tone(freq, at + (index * 0.07), 0.25, { volume: 0.06 }); }); },
  // 북소리 (긴장)
  drum: (at = 0) => { [0, 0.35, 0.6, 0.85].forEach((offset) => { tone(70, at + offset, 0.3, { type: 'triangle', volume: 0.35, to: 40 }); }); },
  // 종이 찢김
  paper: (at = 0) => { hiss(at, 0.35, 0.4, 2500); hiss(at + 0.18, 0.25, 0.3, 3000); },
  // 정체 공개
  reveal: (at = 0) => { tone(330, at, 0.5, { type: 'triangle', volume: 0.14 }); tone(494, at + 0.12, 0.7, { type: 'triangle', volume: 0.12 }); },
  // 심장 소리
  heartbeat: (at = 0) => { [0, 0.22, 0.9, 1.12].forEach((offset) => { tone(60, at + offset, 0.18, { type: 'sine', volume: 0.5, to: 45 }); }); },
  // 바실리스크의 낮은 울음
  growl: (at = 0) => { tone(70, at, 1.8, { type: 'sawtooth', volume: 0.12, to: 45 }); tone(105, at + 0.2, 1.4, { type: 'sawtooth', volume: 0.06, to: 60 }); },
  // 눈이 마주친 섬광
  flash: (at = 0) => { tone(2400, at, 0.6, { volume: 0.12, to: 300 }); hiss(at, 0.4, 0.3, 6000); },
  // 돌에 금 가는 소리
  crack: (at = 0) => { hiss(at, 0.09, 0.6, 1800); tone(900, at, 0.08, { type: 'square', volume: 0.05, to: 200 }); },
  // 쿵
  thud: (at = 0) => { tone(90, at, 0.5, { type: 'triangle', volume: 0.5, to: 35 }); },
  // 돌문이 갈리며 열린다
  grind: (at = 0, length = 2) => { tone(55, at, length, { type: 'sawtooth', volume: 0.07, to: 48 }); hiss(at, length, 0.22, 300); },
  // 피 한 방울
  drip: (at = 0) => { tone(1400, at, 0.12, { volume: 0.07, to: 600 }); },
  // 부엉이 날갯짓
  flutter: (at = 0) => { [0, 0.12, 0.24].forEach((offset) => { hiss(at + offset, 0.09, 0.25, 900); }); },
  // 깃펜·붓이 긁히는 소리 (글씨가 써질 때)
  scrawl: (at = 0) => { hiss(at, 0.16, 0.12, 5200); },
  // 발소리 · 문 삐걱
  step: (at = 0) => { tone(140, at, 0.08, { type: 'triangle', volume: 0.12, to: 90 }); },
  creak: (at = 0) => { tone(320, at, 0.7, { type: 'sawtooth', volume: 0.03, to: 210 }); },
  // 뱀이 미끄러진다
  slither: (at = 0) => { hiss(at, 0.5, 0.22, 4500); },
};

// ── 남은 시간 (서버 시계 기준이 아니라 마감 시각까지) ──
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

// ── 그림 조각 ──
// 바실리스크의 눈: 어둠 속에서 노란 두 눈이 가끔 뜬다 (밤)
const BasiliskEyes: React.FC<{ open?: boolean }> = ({ open }) => (
  <motion.div className='cs-eyes' aria-hidden animate={open ? { opacity: 1 } : { opacity: [0, 0, 1, 1, 0] }} transition={open ? { duration: 0.3 } : { duration: 7, repeat: Infinity, times: [0, 0.55, 0.62, 0.8, 0.9] }}>
    <i />
    <i />
  </motion.div>
);

// 배경: 비밀의 방 복도처럼 양옆에 늘어선 돌 뱀 머리 (가까울수록 크게, 안쪽으로 갈수록 작게) + 물에 비친 바닥
const SerpentHead: React.FC<{ side: 'left' | 'right'; size: number; x: number; y: number; delay: number }> = ({ side, size, x, y, delay }) => (
  <motion.svg
    className={`cs-head cs-head--${side}`}
    viewBox='0 0 512 512'
    style={{ width: size, [side]: `${x}%`, top: `${y}%` }}
    initial={{ opacity: 0, x: side === 'left' ? -30 : 30 }}
    animate={{ opacity: 1, x: 0 }}
    transition={{ delay, duration: 1.2 }}
    aria-hidden
  >
    <defs>
      <linearGradient id={`cs-head-${side}`} x1='0' y1='0' x2='0.3' y2='1'>
        <stop offset='0' stopColor='#7b877c' />
        <stop offset='0.45' stopColor='#3a443b' />
        <stop offset='1' stopColor='#121812' />
      </linearGradient>
    </defs>
    {/* 왼쪽 뱀은 원래 그림이 오른쪽을 보니 그대로, 오른쪽 뱀은 뒤집어 가운데(복도 안쪽)를 보게 */}
    <g transform={side === 'right' ? 'translate(512 0) scale(-1 1)' : undefined}>
      <circle cx='310' cy='115' r='22' className='cs-head__eye' />
      {SEA_SERPENT.map((d) => <path key={d} d={d} fill={`url(#cs-head-${side})`} stroke='#8e9b8f' strokeWidth='3' strokeOpacity='0.5' />)}
    </g>
  </motion.svg>
);

const SerpentHall: React.FC = () => (
  <div className='cs-hall' aria-hidden>
    {[{ size: 210, x: -2, y: 66 }, { size: 150, x: 5, y: 44 }, { size: 105, x: 11, y: 28 }, { size: 72, x: 16, y: 17 }].map((head, index) => (
      <span key={index}>
        <SerpentHead side='left' size={head.size} x={head.x} y={head.y} delay={0.2 + (index * 0.15)} />
        <SerpentHead side='right' size={head.size} x={head.x} y={head.y} delay={0.2 + (index * 0.15)} />
      </span>
    ))}
    <i className='cs-hall__water' />
  </div>
);

// ── 낮: 호그와트 대연회장 — 높은 아치 창으로 드는 햇빛, 기숙사 깃발, 떠 있는 촛불, 돌벽 ──
const HOUSE_BANNERS = [
  { color: '#7f1418', trim: '#d7a640' },
  { color: '#1a4a2c', trim: '#c9ccc7' },
  { color: '#152e5c', trim: '#b08a52' },
  { color: '#b68a12', trim: '#2a2a2a' },
];

const HogwartsHall: React.FC = () => (
  <motion.div className='cs-hogwarts' aria-hidden initial={{ opacity: 0 }} animate={{ opacity: 1 }} exit={{ opacity: 0 }} transition={{ duration: 1.4 }}>
    <div className='cs-hogwarts__windows'>
      {Array.from({ length: 5 }, (_, index) => <i key={index} />)}
    </div>
    <div className='cs-hogwarts__rays' />
    <div className='cs-hogwarts__banners'>
      {HOUSE_BANNERS.map((banner, index) => (
        <motion.i
          key={banner.color}
          style={{ '--banner': banner.color, '--trim': banner.trim } as React.CSSProperties}
          animate={{ rotate: [-1.2, 1.2, -1.2] }}
          transition={{ duration: 5 + index, repeat: Infinity, ease: 'easeInOut' }}
        />
      ))}
    </div>
    {Array.from({ length: 14 }, (_, index) => (
      <motion.span
        // eslint-disable-next-line react/no-array-index-key
        key={index}
        className='cs-candle'
        style={{ left: `${4 + ((index * 37) % 92)}%`, top: `${6 + ((index * 23) % 26)}%` }}
        animate={{ y: [0, -8, 0] }}
        transition={{ duration: 3 + (index % 4), repeat: Infinity, ease: 'easeInOut', delay: (index % 5) * 0.4 }}
      />
    ))}
    <i className='cs-hogwarts__floor' />
  </motion.div>
);

// ── 밤: 비밀의 방 — 늘어선 뱀 석상, 물에 잠긴 바닥, 안쪽 어둠 속 거대한 석상과 바실리스크의 눈 ──
const ChamberHall: React.FC = () => (
  <motion.div className='cs-chamber' aria-hidden initial={{ opacity: 0 }} animate={{ opacity: 1 }} exit={{ opacity: 0 }} transition={{ duration: 1.4 }}>
    <div className='cs-chamber__statue'>
      {/* 살라자르 슬리데린 석상: 이마·눈두덩·코·벌어진 입(바실리스크가 나오는 곳)·길게 늘어진 수염 */}
      <svg className='cs-chamber__face' viewBox='0 0 300 340' preserveAspectRatio='xMidYMin meet'>
        <defs>
          <linearGradient id='cs-statue' x1='0' y1='0' x2='0' y2='1'>
            <stop offset='0' stopColor='#3a4640' />
            <stop offset='0.5' stopColor='#222b26' />
            <stop offset='1' stopColor='#0c100e' stopOpacity='0' />
          </linearGradient>
          <radialGradient id='cs-statue-light' cx='50%' cy='20%' r='60%'>
            <stop offset='0' stopColor='#7fa58c' stopOpacity='0.35' />
            <stop offset='1' stopColor='#7fa58c' stopOpacity='0' />
          </radialGradient>
        </defs>
        <path d='M150 6 C 215 6 250 50 252 104 C 254 140 246 160 240 176 C 262 214 252 270 218 340 L 82 340 C 48 270 38 214 60 176 C 54 160 46 140 48 104 C 50 50 85 6 150 6 Z' fill='url(#cs-statue)' />
        <path d='M150 6 C 215 6 250 50 252 104 C 254 140 246 160 240 176 C 262 214 252 270 218 340 L 82 340 C 48 270 38 214 60 176 C 54 160 46 140 48 104 C 50 50 85 6 150 6 Z' fill='url(#cs-statue-light)' />
        {/* 눈두덩 그늘 · 코 */}
        <path d='M84 104 C 104 92 128 96 138 108 C 120 118 100 118 84 104 Z M216 104 C 196 92 172 96 162 108 C 180 118 200 118 216 104 Z' fill='#070a08' opacity='0.45' />
        <path d='M150 110 L 138 160 C 146 166 154 166 162 160 Z' fill='#151b18' />
        {/* 벌어진 입 */}
        <motion.path d='M118 186 C 132 178 168 178 182 186 C 176 206 124 206 118 186 Z' fill='#010201' animate={{ scaleY: [1, 1.5, 1] }} transition={{ duration: 9, repeat: Infinity, ease: 'easeInOut' }} style={{ transformOrigin: '150px 188px' }} />
        {/* 수염 결 */}
        {[96, 116, 136, 164, 184, 204].map((x) => <path key={x} d={`M${x} 214 C ${x + ((x - 150) * 0.1)} 260 ${x + ((x - 150) * 0.2)} 300 ${x + ((x - 150) * 0.25)} 340`} stroke='#0a0e0c' strokeWidth='3' fill='none' opacity='0.6' />)}
      </svg>
      <BasiliskEyes />
    </div>
    <SerpentHall />
  </motion.div>
);

// 자리 (장면 안 % 좌표)
interface Spot { x: number; y: number; scale: number; tilt: number }

// ── 밤 배경: 불 꺼진 기숙사 — 달빛이 드는 아치 창, 꺼진 벽난로, 어두운 돌벽 ──
const DormRoom: React.FC = () => (
  <motion.div className='cs-dorm' aria-hidden initial={{ opacity: 0 }} animate={{ opacity: 1 }} exit={{ opacity: 0 }} transition={{ duration: 1.4 }}>
    <i className='cs-dorm__window' />
    <i className='cs-dorm__moonlight' />
    <i className='cs-dorm__hearth' />
    <i className='cs-dorm__floor' />
  </motion.div>
);

// 뱀 (방주·석화 표시): 글자 크기·색을 따른다
const SnakeIcon: React.FC = () => (
  <svg className='game-icon cs-snake-icon' viewBox='0 0 512 512' width='1em' height='1em' aria-hidden>
    {SNAKE_TONGUE.map((d) => <path key={d} d={d} fill='currentColor' />)}
  </svg>
);

// 역할 상징 (카드 가운데)
const RoleSigil: React.FC<{ role: string }> = ({ role }) => {
  const icon = { auror: 'scope', healer: 'shield', seer: 'sparkle', student: 'star' }[role] ?? 'star';
  return <span className={`cs-sigil cs-sigil--${role}`}>{role === 'traitor' ? <SnakeIcon /> : <GameIcon name={icon} />}</span>;
};

// 벽에 쓰는 핏빛 글씨: 보이지 않는 붓이 한 글자씩 왼쪽에서 오른쪽으로 써 나가고(끝에 젖은 붓끝 빛), 몇 글자마다 피가 흘러내린다
// tone=dream 은 꿈속 예언 (은빛 안개 글씨, 흘러내림 없음). sound 면 붓 긁는 소리
const WRITE_STEP = 0.13;
const BloodText: React.FC<{ text: string; delay?: number; className?: string; tone?: 'blood' | 'dream'; sound?: boolean }> = ({ text, delay = 0, className, tone = 'blood', sound = false }) => {
  useEffect(() => {
    if (!sound) return;
    text.split('').forEach((char, index) => { if (char !== ' ' && index % 2 === 0) sfx.scrawl(delay + (index * WRITE_STEP)); });
  }, [text, delay, sound]);
  return (
    <p className={['cs-blood', tone === 'dream' && 'cs-blood--dream', className].filter(Boolean).join(' ')}>
      {text.split('').map((char, index) => (
        <motion.span
          // eslint-disable-next-line react/no-array-index-key
          key={index}
          initial={{ clipPath: 'inset(-30% 100% -60% 0)' }}
          animate={{ clipPath: 'inset(-30% 0% -60% 0)' }}
          transition={{ delay: delay + (index * WRITE_STEP), duration: WRITE_STEP * 1.4, ease: 'easeOut' }}
        >
          {char}
          {char !== ' ' && <motion.b className='cs-nib' initial={{ opacity: 0, left: '0%' }} animate={{ opacity: [0, 1, 0], left: ['0%', '100%', '100%'] }} transition={{ delay: delay + (index * WRITE_STEP), duration: WRITE_STEP * 2 }} />}
          {tone === 'blood' && char !== ' ' && index % 3 === 0 && <motion.i className='cs-drip' initial={{ height: 0 }} animate={{ height: 10 + ((index * 7) % 22) }} transition={{ delay: delay + 0.5 + (index * WRITE_STEP), duration: 1.8, ease: 'easeIn' }} />}
        </motion.span>
      ))}
    </p>
  );
};

// 허공에 불꽃으로 쓴 글씨 (볼드모트가 이름을 쓰던 장면처럼): 글자가 타오르며 하나씩 나타나고 불씨가 날린다. tone=gold 는 금빛
const FireWords: React.FC<{ text: string; delay?: number; tone?: 'fire' | 'gold'; className?: string }> = ({ text, delay = 0, tone = 'fire', className }) => (
  <div className={['cs-fire', `cs-fire--${tone}`, className].filter(Boolean).join(' ')}>
    <p>
      {text.split('').map((char, index) => (
        <motion.span
          // eslint-disable-next-line react/no-array-index-key
          key={index}
          initial={{ opacity: 0, scale: 1.6, filter: 'blur(8px) brightness(2.5)' }}
          animate={{ opacity: 1, scale: 1, filter: 'blur(0px) brightness(1)' }}
          transition={{ delay: delay + (index * 0.11), duration: 0.5, ease: 'easeOut' }}
        >
          {char}
        </motion.span>
      ))}
    </p>
    <Particles kind='ember' count={26} delay={delay + 0.3} />
  </div>
);

// ── 오프닝 1: 어두운 돌벽에 핏빛 글씨가 한 글자씩 번지며 흘러내린다 → 2: 뱀이 새겨진 둥근 돌문이 열린다 ──
// 돌문: 문을 가로지른 뱀들이 하나씩 미끄러져 물러나고, 가운데 고리가 돌아간 뒤 문이 좌우로 갈라지며 초록빛이 쏟아진다
// 문테를 따라 감긴 뱀들의 각도 (도) — 하나씩 바깥으로 미끄러져 빠진다
const DOOR_SNAKES = [-90, -30, 30, 90, 150, 210];

const SnakeDoor: React.FC = () => (
  <motion.div className='cs-door' initial={{ opacity: 0, scale: 0.85 }} animate={{ opacity: 1, scale: 1 }} transition={{ duration: 1 }}>
    {/* 문 뒤의 비밀의 방: 초록빛 */}
    <motion.div className='cs-door__light' initial={{ opacity: 0 }} animate={{ opacity: [0, 0, 1] }} transition={{ delay: 3.8, duration: 1.4, times: [0, 0.2, 1] }} />
    {(['left', 'right'] as const).map((side) => (
      <motion.svg
        key={side}
        className={`cs-door__half cs-door__half--${side}`}
        viewBox='0 0 400 400'
        initial={{ x: 0 }}
        animate={{ x: side === 'left' ? '-62%' : '62%' }}
        transition={{ delay: 4, duration: 1.6, ease: [0.6, 0, 0.3, 1] }}
        aria-hidden
      >
        <defs>
          <radialGradient id={`cs-door-stone-${side}`} cx='50%' cy='45%' r='55%'>
            <stop offset='0%' stopColor='#5b6158' />
            <stop offset='70%' stopColor='#363b35' />
            <stop offset='100%' stopColor='#1c201b' />
          </radialGradient>
          <clipPath id={`cs-door-clip-${side}`}>
            <rect x={side === 'left' ? 0 : 200} y='0' width='200' height='400' />
          </clipPath>
        </defs>
        <g clipPath={`url(#cs-door-clip-${side})`}>
          <circle cx='200' cy='200' r='190' fill='#151815' />
          <circle cx='200' cy='200' r='176' fill={`url(#cs-door-stone-${side})`} stroke='#20241f' strokeWidth='6' />
          {/* 문테 둘레 돌못 */}
          {Array.from({ length: 24 }, (_, index) => {
            const angle = (index / 24) * Math.PI * 2;
            return <circle key={index} cx={200 + (Math.cos(angle) * 182)} cy={200 + (Math.sin(angle) * 182)} r='5' fill='#4a5048' stroke='#20241f' />;
          })}
          {/* 안쪽 테두리 홈 */}
          <circle cx='200' cy='200' r='150' fill='none' stroke='#20241f' strokeWidth='3' />
          <circle cx='200' cy='200' r='104' fill='none' stroke='#4c5349' strokeWidth='2' />
          {/* 문테를 따라 감긴 뱀들: 하나씩 바깥으로 미끄러져 빠진다 */}
          {DOOR_SNAKES.map((angle, index) => {
            const rad = (angle * Math.PI) / 180;
            return (
              <motion.g
                key={angle}
                initial={{ x: 0, y: 0, opacity: 1 }}
                animate={{ x: Math.cos(rad) * 90, y: Math.sin(rad) * 90, opacity: 0 }}
                transition={{ delay: 1.2 + (index * 0.32), duration: 0.8, ease: 'easeIn' }}
              >
                <g transform={`translate(${200 + (Math.cos(rad) * 128)} ${200 + (Math.sin(rad) * 128)}) rotate(${angle + 90}) translate(-46 -46) scale(${92 / 512})`}>
                  {SAND_SNAKE.map((d) => <path key={d} d={d} fill='#8f9a8b' stroke='#1b1f1a' strokeWidth='22' paintOrder='stroke' />)}
                </g>
              </motion.g>
            );
          })}
        </g>
      </motion.svg>
    ))}
    {/* 가운데 자물쇠: 똬리 튼 뱀이 풀리듯 돌며 사라진다 */}
    <motion.svg className='cs-door__lock' viewBox='0 0 512 512' initial={{ rotate: 0, opacity: 1, scale: 1 }} animate={{ rotate: [0, 0, -270], opacity: [1, 1, 0], scale: [1, 1.05, 0.6] }} transition={{ delay: 3, duration: 1.2, times: [0, 0.1, 1] }} aria-hidden>
      <defs>
        <linearGradient id='cs-door-coil' x1='0' y1='0' x2='1' y2='1'>
          <stop offset='0' stopColor='#c3cbbf' />
          <stop offset='0.5' stopColor='#7f8a7b' />
          <stop offset='1' stopColor='#3f463d' />
        </linearGradient>
      </defs>
      {SNAKE_SPIRAL.map((d) => <path key={d} d={d} fill='url(#cs-door-coil)' stroke='#1b1f1a' strokeWidth='12' paintOrder='stroke' />)}
    </motion.svg>
  </motion.div>
);

const Opening: React.FC<{ onDone: () => void }> = ({ onDone }) => {
  const done = useRef(onDone);
  done.current = onDone;
  const [stage, setStage] = useState<'words' | 'door'>('words');
  useEffect(() => {
    sfx.hiss(0.4);
    sfx.heartbeat(2.4);
    const toDoor = window.setTimeout(() => {
      setStage('door');
      // 뱀이 물러날 때마다 쉿, 자물쇠가 돌고 문이 갈리며 열린다
      DOOR_SNAKES.forEach((_, index) => { sfx.slither(1.2 + (index * 0.32)); });
      sfx.hiss(1);
      sfx.grind(3, 1.2);
      sfx.grind(4, 1.8);
      sfx.growl(4.6);
    }, 7_000);
    const finish = window.setTimeout(() => { done.current(); }, 13_000);
    return () => { window.clearTimeout(toDoor); window.clearTimeout(finish); };
  }, []);
  return (
    <motion.div className='cs-opening' initial={{ opacity: 0 }} animate={{ opacity: 1 }} exit={{ opacity: 0, transition: { duration: 1.2 } }} transition={{ duration: 1 }}>
      <AnimatePresence mode='wait'>
        {stage === 'words' ? (
          <motion.div key='words' className='cs-opening__wall' exit={{ opacity: 0, transition: { duration: 0.8 } }}>
            <div className='cs-opening__torch cs-opening__torch--left' aria-hidden />
            <div className='cs-opening__torch cs-opening__torch--right' aria-hidden />
            <BloodText text={OPENING} delay={0.8} className='cs-opening__words' sound />
          </motion.div>
        ) : (
          <SnakeDoor key='door' />
        )}
      </AnimatePresence>
      <BasiliskEyes />
    </motion.div>
  );
};

// ── 역할 카드 모달: 뒤집으면 내 역할 (1쪽) → 하는 법 (2쪽) → [확인했습니다] ──
const HOW_TO: Record<string, string[]> = {
  traitor: ['밤에 초상을 누르고 [석화]로 석화할 사람을 고릅니다 (동료와 가장 많이 고른 사람).', '오른쪽 [예언] 칸에서 예언자에게 보낼 예언을 정합니다 (사실인 것만).', '[밀담]으로 동료 방주와 몰래 이야기합니다.'],
  auror: ['밤마다 초상을 누르고 [조사]하면 그 사람의 진영이 쪽지로 옵니다.'],
  healer: ['밤마다 초상을 누르고 [보호]하면 그날 밤 석화를 막습니다 (같은 사람 이틀 연속은 안 됨).'],
  seer: ['밤이 끝날 때마다 방주가 전한 예언이 쪽지로 옵니다. 예언은 언제나 진실입니다.'],
  student: ['특별한 능력은 없지만, 토론과 고발로 방주를 찾아냅니다.'],
};

const RoleModal: React.FC<{ view: CView; onClose: () => void }> = ({ view, onClose }) => {
  const [page, setPage] = useState<'card' | 'how'>('card');
  const [flipped, setFlipped] = useState(false);
  const role = view.my_role;
  useEffect(() => {
    const timer = window.setTimeout(() => { setFlipped(true); sfx.note(); }, 900);
    return () => { window.clearTimeout(timer); };
  }, []);
  if (!role) return null;
  const mates = view.players.filter((player) => role.mates.includes(player.seat));
  return (
    <motion.div className='cs-modal' initial={{ opacity: 0 }} animate={{ opacity: 1 }} exit={{ opacity: 0 }}>
      <motion.div key={page} className='cs-modal__card' initial={{ y: 30, scale: 0.92 }} animate={{ y: 0, scale: 1 }} transition={{ type: 'spring', stiffness: 160, damping: 16 }}>
        <small className='cs-modal__eyebrow'>{page === 'card' ? '1' : '2'} / 2</small>
        {page === 'card' ? (
          <>
            <div className={flipped ? 'cs-rolecard is-flipped' : 'cs-rolecard'}>
              <div className='cs-rolecard__inner'>
                <div className='cs-rolecard__back' aria-hidden><RoleSigil role='traitor' /></div>
                <div className={role.dark ? 'cs-rolecard__front is-dark' : 'cs-rolecard__front'}>
                  <RoleSigil role={role.key} />
                  <b>{role.name}</b>
                  <span>{role.faction} 진영</span>
                </div>
              </div>
            </div>
            <h2>당신은 「{role.name}」입니다.</h2>
            <p className='cs-modal__lead'>
              {role.dark
                ? `학교에 숨어든 ${view.traitor_name}입니다. 정체를 들키지 말고 호그와트를 장악하세요.`
                : `${view.faction_light} 진영입니다. 학생들 사이에 숨은 ${view.traitor_name} ${view.traitor_count}명을 모두 찾아 퇴학시키세요.`}
            </p>
            {mates.length > 0 && (
              <div className='cs-modal__mates'>
                <b>동료 {view.traitor_name}</b>
                {mates.map((mate) => <span key={mate.seat}>{mate.avatar && <img src={mate.avatar} alt='' />}{mate.name}</span>)}
              </div>
            )}
          </>
        ) : (
          <>
            <h2>밤과 낮</h2>
            <div className='cs-modal__phases'>
              <div className='cs-modal__phase is-day'>
                <GameIcon name='sun' />
                <b>낮 · {view.day_minutes}분</b>
                <span>모두 토론하고, 초상을 눌러 수상한 사람을 <em className='cs-chip'>고발</em>합니다. 가장 많이 고발된 사람은 퇴학되고 정체가 공개됩니다.</span>
              </div>
              <div className='cs-modal__phase is-night'>
                <GameIcon name='moon' />
                <b>밤 · {view.night_minutes}분</b>
                <span>역할이 있는 사람만 몰래 움직입니다.</span>
              </div>
            </div>
            <h3 className='cs-modal__subhead'>내 역할로 할 일</h3>
            <ol className='cs-modal__steps'>
              {(HOW_TO[role.key] ?? []).map((line) => <li key={line}>{line}</li>)}
            </ol>
            <p className='cs-modal__note'>탈락하면 모든 정체를 보며 관전만 합니다. {view.faction_light}: {view.traitor_name} 모두 퇴학 / {view.faction_dark}: {view.traitor_name} 수가 남은 사람 이상이면 승리.</p>
          </>
        )}
        <div className='cs-modal__actions'>
          {page === 'card'
            ? <button type='button' className='cs-button' onClick={() => { setPage('how'); }}>다음</button>
            : (
              <>
                <button type='button' className='cs-button cs-button--ghost' onClick={() => { setPage('card'); }}>이전</button>
                <button type='button' className='cs-button' onClick={onClose}>확인했습니다</button>
              </>
            )}
        </div>
      </motion.div>
    </motion.div>
  );
};

// ── 전체 화면 연출: 낮/밤 시작, 퇴학, 석화(바실리스크), 무사한 밤 ──
type Cue =
  | { id: string; kind: 'day' | 'night'; day: number }
  | { id: string; kind: 'expel' | 'petrify'; player: CPlayer; roleName: string; dark: boolean }
  | { id: string; kind: 'safe' }
  | { id: string; kind: 'prophecy' | 'clue'; text: string };

// 연출마다 보여 주는 시간 (ms)
// 아침의 석화는 먼저 비밀의 방 문이 열린다 (DOOR_LEAD 초) → 바실리스크의 눈
const DOOR_LEAD = 5.4;
const CUE_LENGTH: Record<Cue['kind'], number> = { day: 3_600, night: 4_400, safe: 3_600, expel: 7_000, petrify: 9_200 + (DOOR_LEAD * 1000), prophecy: 8_500, clue: 4_600 };

// 연출마다 효과음 (시간표에 맞춰)
const playCue = (kind: Cue['kind']) => {
  if (kind === 'day') { sfx.rooster(0); sfx.bell(0.5); }
  if (kind === 'night') { sfx.wind(0); sfx.night(0.4); sfx.hiss(1.6); }
  if (kind === 'safe') { sfx.safe(0.3); sfx.sparkle(0.9); }
  if (kind === 'expel') { sfx.drum(0); sfx.gavel(1.4); sfx.gavel(1.9); sfx.gavel(2.4); sfx.paper(3.2); sfx.reveal(4.6); }
  if (kind === 'prophecy') { sfx.sparkle(0.2); sfx.wind(0.4); sfx.sparkle(1.4); }
  if (kind === 'clue') { sfx.sparkle(0.2); sfx.reveal(0.8); }
  if (kind === 'petrify') {
    DOOR_SNAKES.forEach((_, index) => { sfx.slither(1.2 + (index * 0.32)); });
    sfx.grind(3, 1.2);
    sfx.grind(4, 1.8);
    const at = DOOR_LEAD;
    sfx.heartbeat(at); sfx.growl(at + 0.5); sfx.hiss(at + 1.0); sfx.flash(at + 2.6); sfx.stone(at + 3.0); sfx.crack(at + 4.2); sfx.crack(at + 4.5); sfx.crack(at + 4.75); sfx.thud(at + 5.4); sfx.reveal(at + 6.6);
  }
};

// 돌가루 (석화) · 종이 조각 (퇴학)
const Particles: React.FC<{ kind: 'dust' | 'paper' | 'spark' | 'ember'; count: number; delay: number }> = ({ kind, count, delay }) => (
  <div className={`cs-particles cs-particles--${kind}`} aria-hidden>
    {Array.from({ length: count }, (_, index) => {
      const x = ((index * 37) % 100) - 50;
      const spin = ((index * 53) % 360) - 180;
      return (
        <motion.i
          // eslint-disable-next-line react/no-array-index-key
          key={index}
          initial={{ opacity: 0, x: 0, y: 0, rotate: 0 }}
          animate={kind === 'ember'
            ? { opacity: [0, 1, 0.8, 0], x: [x * 3, (x * 3) + (((index * 17) % 40) - 20)], y: [0, -120 - ((index * 23) % 160)], scale: [0.6, 1, 0.3] }
            : kind === 'spark'
            ? { opacity: [0, 1, 0], x: x * 6, y: (((index * 29) % 100) - 50) * 4, scale: [0.4, 1.2, 0.2] }
            : { opacity: [0, 1, 1, 0], x: x * 4, y: [0, 60 + ((index * 41) % 200)], rotate: spin }}
          transition={kind === 'ember' ? { delay: delay + ((index % 9) * 0.25), duration: 2.4, repeat: Infinity, repeatDelay: (index % 5) * 0.3, ease: 'easeOut' } : { delay: delay + ((index % 7) * 0.06), duration: kind === 'spark' ? 1.1 : 2.2, ease: 'easeOut' }}
        />
      );
    })}
  </div>
);

// 바실리스크의 석화: 어둠 → 화면을 채우는 노란 눈이 열린다 → 섬광 → 초상의 색이 빠지며 돌이 번진다 → 금이 가고 돌가루 → '석화' 도장 → 정체 공개
const PetrifyScene: React.FC<{ cue: Extract<Cue, { kind: 'petrify' }>; view: CView }> = ({ cue, view }) => {
  const [door, setDoor] = useState(true);
  useEffect(() => {
    const timer = window.setTimeout(() => { setDoor(false); }, DOOR_LEAD * 1000);
    return () => { window.clearTimeout(timer); };
  }, []);
  if (door) {
    return (
      <motion.div className='cs-cue cs-cue--door' initial={{ opacity: 0 }} animate={{ opacity: 1 }} exit={{ opacity: 0 }}>
        <motion.p className='cs-cue__lead' initial={{ opacity: 0 }} animate={{ opacity: 1 }} transition={{ delay: 0.3 }}>밤사이, 비밀의 방이 다시 열렸다…</motion.p>
        <SnakeDoor />
      </motion.div>
    );
  }
  return <PetrifyGaze cue={cue} view={view} />;
};

const PetrifyGaze: React.FC<{ cue: Extract<Cue, { kind: 'petrify' }>; view: CView }> = ({ cue, view }) => (
  <motion.div className='cs-cue cs-cue--petrify' initial={{ opacity: 0 }} animate={{ opacity: 1 }} exit={{ opacity: 0, transition: { duration: 0.8 } }}>
    {/* 1. 큰 눈: 세로로 갈라진 노란 눈이 천천히 뜨고 동공이 좁아진다 */}
    <motion.div className='cs-gaze' initial={{ opacity: 0 }} animate={{ opacity: [0, 1, 1, 0] }} transition={{ duration: 3.2, times: [0, 0.18, 0.8, 1], delay: 0.3 }}>
      {[0, 1].map((side) => (
        <motion.svg key={side} className='cs-gaze__eye' viewBox='0 0 512 512' initial={{ scaleY: 0 }} animate={{ scaleY: [0, 0.15, 1], scale: [1, 1, 1.08] }} transition={{ delay: 0.6 + (side * 0.08), duration: 1.6, times: [0, 0.4, 1], ease: 'easeOut' }} aria-hidden>
          <defs>
            <radialGradient id={`cs-gaze-${side}`} cx='50%' cy='50%' r='60%'>
              <stop offset='0' stopColor='#fff7b0' />
              <stop offset='0.35' stopColor='#ffd21a' />
              <stop offset='0.75' stopColor='#c98a00' />
              <stop offset='1' stopColor='#5a3400' />
            </radialGradient>
          </defs>
          <g transform={side === 1 ? 'translate(512 0) scale(-1 1)' : undefined}>
            {BEAST_EYE.map((d) => <path key={d} d={d} fill={`url(#cs-gaze-${side})`} />)}
          </g>
        </motion.svg>
      ))}
    </motion.div>
    {/* 2. 섬광 */}
    <motion.div className='cs-flash' initial={{ opacity: 0 }} animate={{ opacity: [0, 1, 0] }} transition={{ delay: 2.6, duration: 0.6, times: [0, 0.15, 1] }} />
    {/* 3. 초상: 색이 빠지며 돌이 아래에서 위로 번진다 */}
    <motion.div className='cs-cue__victim' initial={{ scale: 0.7, opacity: 0 }} animate={{ scale: 1, opacity: 1, x: [0, -3, 3, -2, 2, 0] }} transition={{ opacity: { delay: 2.7, duration: 0.3 }, scale: { delay: 2.7, duration: 0.5 }, x: { delay: 4.2, duration: 0.6 } }}>
      <span className='cs-cue__portrait'>
        {cue.player.avatar ? <motion.img src={cue.player.avatar} alt='' initial={{ filter: 'grayscale(0) brightness(1.3)' }} animate={{ filter: ['grayscale(0) brightness(1.3)', 'grayscale(0.4) brightness(1)', 'grayscale(1) contrast(1.35) brightness(0.8)'] }} transition={{ delay: 3, duration: 1.6 }} /> : null}
        <motion.span className='cs-stone' initial={{ clipPath: 'inset(100% 0 0 0)' }} animate={{ clipPath: 'inset(0% 0 0 0)' }} transition={{ delay: 3, duration: 1.6, ease: 'easeInOut' }} />
        <svg className='cs-cracks cs-cracks--big' viewBox='0 0 100 100' aria-hidden>
          <motion.path d='M50 2 L46 28 L58 42 L40 60 L52 76 L44 98' initial={{ pathLength: 0 }} animate={{ pathLength: 1 }} transition={{ delay: 4.2, duration: 0.25 }} />
          <motion.path d='M46 28 L20 36 L8 30' initial={{ pathLength: 0 }} animate={{ pathLength: 1 }} transition={{ delay: 4.5, duration: 0.2 }} />
          <motion.path d='M58 42 L84 50 L96 64' initial={{ pathLength: 0 }} animate={{ pathLength: 1 }} transition={{ delay: 4.75, duration: 0.2 }} />
          <motion.path d='M40 60 L16 72 L6 88' initial={{ pathLength: 0 }} animate={{ pathLength: 1 }} transition={{ delay: 4.9, duration: 0.2 }} />
        </svg>
      </span>
      <Particles kind='dust' count={22} delay={4.3} />
      <motion.em className='cs-stamp' initial={{ scale: 3.2, opacity: 0, rotate: -26 }} animate={{ scale: 1, opacity: 1, rotate: -12 }} transition={{ delay: 5.4, type: 'spring', stiffness: 240, damping: 14 }}>석화</motion.em>
    </motion.div>
    <motion.h2 initial={{ opacity: 0, y: 10 }} animate={{ opacity: 1, y: 0 }} transition={{ delay: 5.8 }}>{cue.player.name}, 석화된 채 발견되다</motion.h2>
    <motion.div className={cue.dark ? 'cs-reveal is-dark' : 'cs-reveal'} initial={{ rotateY: 90, opacity: 0 }} animate={{ rotateY: 0, opacity: 1 }} transition={{ delay: 6.6, duration: 0.7 }}>
      정체는 <b>「{cue.roleName}」</b> · {cue.dark ? view.faction_dark : view.faction_light} 진영
    </motion.div>
  </motion.div>
);

// 퇴학: 북소리 → 의사봉 세 번 → 초상이 흔들리다 잿빛으로 → '퇴학' 도장과 찢긴 종이 → 정체 카드
const ExpelScene: React.FC<{ cue: Extract<Cue, { kind: 'expel' }>; view: CView }> = ({ cue, view }) => (
  <motion.div className='cs-cue cs-cue--expel' initial={{ opacity: 0 }} animate={{ opacity: 1 }} exit={{ opacity: 0, transition: { duration: 0.8 } }}>
    <motion.p className='cs-cue__lead' initial={{ opacity: 0, y: -10 }} animate={{ opacity: 1, y: 0 }} transition={{ delay: 0.2 }}>가장 많이 고발된 사람은…</motion.p>
    <motion.div className='cs-cue__victim' initial={{ scale: 0.5, opacity: 0 }} animate={{ scale: [0.5, 1.05, 1], opacity: 1, rotate: [0, 0, -3, 3, -2, 0] }} transition={{ delay: 0.9, duration: 1.8, times: [0, 0.3, 1] }}>
      <span className='cs-cue__portrait'>
        {cue.player.avatar ? <motion.img src={cue.player.avatar} alt='' animate={{ filter: ['grayscale(0)', 'grayscale(0)', 'grayscale(0.85) brightness(0.7)'] }} transition={{ delay: 2.4, duration: 1 }} /> : null}
      </span>
      <Particles kind='paper' count={16} delay={3.2} />
      <motion.em className='cs-stamp' initial={{ scale: 3.2, opacity: 0, rotate: -26 }} animate={{ scale: 1, opacity: 1, rotate: -12 }} transition={{ delay: 3.1, type: 'spring', stiffness: 240, damping: 14 }}>퇴학</motion.em>
    </motion.div>
    <motion.h2 initial={{ opacity: 0, y: 10 }} animate={{ opacity: 1, y: 0 }} transition={{ delay: 1.3 }}>{cue.player.name}</motion.h2>
    <motion.div className={cue.dark ? 'cs-reveal is-dark' : 'cs-reveal'} initial={{ rotateY: 90, opacity: 0 }} animate={{ rotateY: 0, opacity: 1 }} transition={{ delay: 4.6, duration: 0.7 }}>
      정체는 <b>「{cue.roleName}」</b> · {cue.dark ? view.faction_dark : view.faction_light} 진영
    </motion.div>
    {cue.dark && <FireWords text={`${view.traitor_name}를 찾아냈다!`} delay={5.2} className='cs-fire--reveal' />}
  </motion.div>
);

// 예언 (예언자만): 잠든 사이 꿈속에서 수정구슬 너머 목소리가 예언을 속삭인다
const ProphecyScene: React.FC<{ cue: Extract<Cue, { kind: 'prophecy' }> }> = ({ cue }) => (
  <motion.div className='cs-cue cs-cue--prophecy cs-cue--dream' initial={{ opacity: 0, filter: 'blur(12px)' }} animate={{ opacity: 1, filter: 'blur(0px)' }} exit={{ opacity: 0, filter: 'blur(12px)', transition: { duration: 1 } }} transition={{ duration: 1.4 }}>
    <motion.span className='cs-dream__swirl' animate={{ rotate: 360 }} transition={{ duration: 30, repeat: Infinity, ease: 'linear' }} aria-hidden />
    <motion.span className='cs-dream__ball' initial={{ scale: 0.4, opacity: 0 }} animate={{ scale: 1, opacity: 1, y: [0, -6, 0] }} transition={{ scale: { duration: 1.2 }, opacity: { duration: 1.2 }, y: { duration: 3, repeat: Infinity } }}>
      <svg viewBox='0 0 512 512' aria-hidden>{CRYSTAL_BALL.map((d) => <path key={d} d={d} fill='currentColor' />)}</svg>
    </motion.span>
    <motion.small className='cs-cue__eyebrow' initial={{ opacity: 0 }} animate={{ opacity: 1 }} transition={{ delay: 0.6 }}>꿈속에서 누군가 속삭였다…</motion.small>
    <BloodText text={cue.text} delay={1.2} tone='dream' className='cs-prophecy__text' />
  </motion.div>
);

// 조사 결과 (오러만): 돋보기 빛 속에 진영이 드러난다
const ClueScene: React.FC<{ cue: Extract<Cue, { kind: 'clue' }> }> = ({ cue }) => (
  <motion.div className='cs-cue cs-cue--clue' initial={{ opacity: 0 }} animate={{ opacity: 1 }} exit={{ opacity: 0, transition: { duration: 0.6 } }}>
    <motion.span className='cs-cue__orb' initial={{ scale: 0.2, rotate: -90 }} animate={{ scale: 1, rotate: 0 }} transition={{ type: 'spring', stiffness: 120, damping: 11 }}><GameIcon name='scope' /></motion.span>
    <motion.p className='cs-clue__text' initial={{ opacity: 0, y: 12 }} animate={{ opacity: 1, y: 0 }} transition={{ delay: 0.7 }}>{cue.text}</motion.p>
    <Particles kind='spark' count={14} delay={0.6} />
  </motion.div>
);

const CueOverlay: React.FC<{ cue: Cue; view: CView }> = ({ cue, view }) => {
  if (cue.kind === 'prophecy') return <ProphecyScene cue={cue} />;
  if (cue.kind === 'clue') return <ClueScene cue={cue} />;
  if (cue.kind === 'petrify') return <PetrifyScene cue={cue} view={view} />;
  if (cue.kind === 'expel') return <ExpelScene cue={cue} view={view} />;
  if (cue.kind === 'day' || cue.kind === 'night') {
    const night = cue.kind === 'night';
    return (
      <motion.div className={night ? 'cs-cue cs-cue--night' : 'cs-cue cs-cue--day'} initial={{ opacity: 0 }} animate={{ opacity: 1 }} exit={{ opacity: 0, transition: { duration: 0.7 } }}>
        {/* 낮: 해가 떠오르며 빛줄기가 돈다 / 밤: 달이 뜨고 안개가 밀려오며 눈이 깜빡인다 */}
        {!night && <motion.span className='cs-rays' initial={{ opacity: 0, rotate: 0, scale: 0.6 }} animate={{ opacity: 0.9, rotate: 40, scale: 1 }} transition={{ duration: 3.2, ease: 'easeOut' }} />}
        {night && <motion.span className='cs-cue__mist' initial={{ opacity: 0, x: '-20%' }} animate={{ opacity: 1, x: '0%' }} transition={{ duration: 2.4 }} />}
        <motion.span className='cs-cue__orb' initial={{ y: 120, scale: 0.4, opacity: 0 }} animate={{ y: 0, scale: 1, opacity: 1 }} transition={{ type: 'spring', stiffness: 70, damping: 12 }}>
          <GameIcon name={night ? 'moon' : 'sun'} />
        </motion.span>
        <motion.h2 initial={{ letterSpacing: '0.6em', opacity: 0 }} animate={{ letterSpacing: '0.06em', opacity: 1 }} transition={{ duration: 1.1, delay: 0.3 }}>
          {cue.day}일째 {night ? '밤' : '아침'}
        </motion.h2>
        <motion.p initial={{ opacity: 0 }} animate={{ opacity: 1 }} transition={{ delay: 1 }}>
          {night ? '촛불이 꺼지고 모두 기숙사 침대에 눕습니다… 어둠 속에서 누군가 몰래 일어납니다.' : '모두 대연회장에 모였습니다. 토론을 시작하세요.'}
        </motion.p>
        {night && <BasiliskEyes open />}
      </motion.div>
    );
  }
  return (
    <motion.div className='cs-cue cs-cue--safe' initial={{ opacity: 0 }} animate={{ opacity: 1 }} exit={{ opacity: 0, transition: { duration: 0.7 } }}>
      <motion.span className='cs-cue__orb' initial={{ scale: 0.3, rotate: -40 }} animate={{ scale: [0.3, 1.15, 1], rotate: 0 }} transition={{ duration: 0.9 }}><GameIcon name='shield' /></motion.span>
      <motion.span className='cs-shield-ring' initial={{ scale: 0.4, opacity: 0.9 }} animate={{ scale: 2.6, opacity: 0 }} transition={{ delay: 0.5, duration: 1.4 }} />
      <Particles kind='spark' count={18} delay={0.9} />
      <h2>무사한 밤</h2>
      <p>지난밤에는 아무도 석화되지 않았습니다.</p>
    </motion.div>
  );
};

// ── 낮: 대연회장 긴 식탁에 앉은 사람들 ──
// 말풍선: 대화가 오면 그 사람 위에 잠깐 뜬다
interface Bubble { id: string; text: string }

const Seat: React.FC<{
  player: CPlayer;
  view: CView;
  at: Spot;
  size: number;
  selected: boolean;
  selectable: boolean;
  bubble?: Bubble;
  onPick: (player: CPlayer) => void;
}> = ({ player, view, at, size: baseSize, selected, selectable, bubble, onPick }) => {
  const size = Math.round(baseSize * at.scale);
  const me = player.seat === view.me;
  const mate = view.my_role?.mates.includes(player.seat);
  const out = player.out;
  const petrified = out?.by === 'petrify';
  const myVote = view.phase === 'day' && view.my_vote === player.seat;
  const classes = [
    'cs-seat',
    me && 'is-me',
    mate && 'is-mate',
    player.dark && !me && 'is-dark',
    !player.alive && 'is-out',
    petrified && 'is-stone',
    out && !petrified && 'is-expelled',
    selected && 'is-selected',
    selectable && 'is-selectable',
  ].filter(Boolean).join(' ');
  return (
    <motion.button
      type='button'
      className={classes}
      style={{ '--seat-size': `${size}px`, zIndex: 3 + Math.round(at.y / 10) } as React.CSSProperties}
      initial={{ opacity: 0, y: 30, left: `${at.x}%`, top: `${at.y}%` }}
      animate={{ opacity: 1, y: 0, left: `${at.x}%`, top: `${at.y}%` }}
      transition={{ type: 'spring', stiffness: 90, damping: 14, delay: 0.05 * player.seat }}
      whileHover={selectable ? { scale: 1.08 } : undefined}
      disabled={!selectable}
      onClick={() => { onPick(player); }}
      title={player.voted_by.length > 0 ? `고발: ${player.voted_by.join(', ')}` : player.name}
    >
      <AnimatePresence>
        {bubble && (
          <motion.span key={bubble.id} className='cs-bubble' initial={{ opacity: 0, y: 8, scale: 0.7 }} animate={{ opacity: 1, y: 0, scale: 1 }} exit={{ opacity: 0, y: -6, transition: { duration: 0.3 } }} transition={{ type: 'spring', stiffness: 260, damping: 18 }}>
            {bubble.text}
          </motion.span>
        )}
      </AnimatePresence>
      <span className='cs-seat__frame'>
        <TokenAvatar accountId={player.account_id} avatar={player.avatar} size={size} />
        {petrified && <svg className='cs-cracks' viewBox='0 0 100 100' aria-hidden><path d='M50 4 L46 30 L58 44 L40 62 L52 78 L44 98 M46 30 L22 38 M58 44 L84 52' /></svg>}
        {out && <em className='cs-seat__stamp'>{petrified ? '석화' : out.by === 'forfeit' ? '기권' : '퇴학'}</em>}
        {player.votes > 0 && view.phase === 'day' && <motion.b key={player.votes} className='cs-seat__votes' initial={{ scale: 1.8 }} animate={{ scale: 1 }}>{player.votes}</motion.b>}
        {myVote && <span className='cs-seat__mine cs-seat__mine--vote'><GameIcon name='check' /></span>}
      </span>
      <span className='cs-seat__name'>{player.name}{me && <small> (나)</small>}</span>
      {player.role_name && <span className={player.dark ? 'cs-seat__role is-dark' : 'cs-seat__role'}>{player.role_name}</span>}
    </motion.button>
  );
};

// 긴 식탁: 사람 수에 따라 한두 줄, 식탁 판은 앉은 사람 앞(아래)에 놓인다
const hallLayout = (total: number): { spots: Spot[]; tables: number[] } => {
  const rows = total > 8 ? 2 : 1;
  const perRow = Math.ceil(total / rows);
  const seatY = rows === 1 ? [50] : [32, 66];
  const spots = Array.from({ length: total }, (_, index) => {
    const row = Math.floor(index / perRow);
    const count = row === rows - 1 ? total - (perRow * (rows - 1)) : perRow;
    const at = index - (row * perRow);
    return { x: 10 + ((80 / count) * (at + 0.5)), y: seatY[row] ?? 50, scale: 1, tilt: 0 };
  });
  return { spots, tables: seatY.map((y) => y + 9) };
};

const GreatHall: React.FC<{
  view: CView;
  size: number;
  selected: number | null;
  selectable: (player: CPlayer) => boolean;
  bubbles: Record<string, Bubble>;
  onPick: (player: CPlayer) => void;
}> = ({ view, size, selected, selectable, bubbles, onPick }) => {
  const { spots, tables } = hallLayout(view.players.length);
  return (
    <motion.div className='cs-hall-scene' initial={{ opacity: 0 }} animate={{ opacity: 1 }} exit={{ opacity: 0, transition: { duration: 0.8 } }} transition={{ duration: 1 }}>
      {tables.map((y, index) => (
        <motion.i key={y} className='cs-longtable' style={{ top: `${y}%` }} initial={{ scaleX: 0.4, opacity: 0 }} animate={{ scaleX: 1, opacity: 1 }} transition={{ delay: 0.2 + (index * 0.2), duration: 0.8 }}>
          {Array.from({ length: 7 }, (_, plate) => <b key={plate} style={{ left: `${8 + (plate * 14)}%` }} />)}
        </motion.i>
      ))}
      {view.players.map((player, index) => (
        <Seat
          key={player.seat}
          player={player}
          view={view}
          at={spots[index] ?? { x: 50, y: 50, scale: 1, tilt: 0 }}
          size={size}
          selected={selected === player.seat}
          selectable={selectable(player)}
          bubble={player.acct ? bubbles[player.acct] : undefined}
          onPick={onPick}
        />
      ))}
    </motion.div>
  );
};

// ── 밤: 불 꺼진 기숙사. 모두 잠들고, 역할이 있는 나만 몰래 일어나 문으로 나간다 ──
type Away = 'bed' | 'leaving' | 'out' | 'returning';

const dormLayout = (total: number): Spot[] => {
  const rows = total > 5 ? 2 : 1;
  const perRow = Math.ceil(total / rows);
  const rowY = rows === 1 ? [56] : [36, 72];
  return Array.from({ length: total }, (_, index) => {
    const row = Math.floor(index / perRow);
    const count = row === rows - 1 ? total - (perRow * (rows - 1)) : perRow;
    const at = index - (row * perRow);
    return { x: 8 + ((78 / count) * (at + 0.5)), y: rowY[row] ?? 56, scale: 1, tilt: 0 };
  });
};

const DORM_DOOR = { x: 95, y: 52 };

const Icon512: React.FC<{ paths: string[]; className?: string }> = ({ paths, className }) => (
  <svg className={className} viewBox='0 0 512 512' aria-hidden>
    {paths.map((d) => <path key={d} d={d} fill='currentColor' />)}
  </svg>
);

// 침대에서 문까지 걸어가는 발자국
const Footsteps: React.FC<{ from: Spot; to: { x: number; y: number }; back?: boolean }> = ({ from, to, back }) => {
  const steps = 7;
  const angle = (Math.atan2(to.y - from.y, to.x - from.x) * 180) / Math.PI + 90 + (back ? 180 : 0);
  return (
    <>
      {Array.from({ length: steps }, (_, index) => {
        const t = (index + 1) / (steps + 1);
        const order = back ? steps - index : index;
        return (
          <motion.span
            // eslint-disable-next-line react/no-array-index-key
            key={index}
            className='cs-step'
            style={{ left: `${from.x + ((to.x - from.x) * t)}%`, top: `${from.y + ((to.y - from.y) * t) + (index % 2 ? 1.6 : -1.6)}%`, rotate: `${angle}deg` }}
            initial={{ opacity: 0, scale: 0.6 }}
            animate={{ opacity: [0, 1, 1, 0], scale: 1 }}
            transition={{ delay: order * 0.28, duration: 2.6, times: [0, 0.1, 0.7, 1] }}
          >
            <Icon512 paths={FOOTPRINT} />
          </motion.span>
        );
      })}
    </>
  );
};

const Bed: React.FC<{ player: CPlayer; view: CView; at: Spot; size: number; empty: boolean; dream: boolean; bubble?: Bubble }> = ({ player, view, at, size, empty, dream, bubble }) => {
  const out = player.out;
  const petrified = out?.by === 'petrify';
  const gone = Boolean(out) && !petrified;
  const me = player.seat === view.me;
  return (
    <motion.div
      className={['cs-bed', me && 'is-me', petrified && 'is-stone', gone && 'is-gone', empty && 'is-empty'].filter(Boolean).join(' ')}
      style={{ left: `${at.x}%`, top: `${at.y}%`, '--seat-size': `${size}px` } as React.CSSProperties}
      initial={{ opacity: 0, y: 20 }}
      animate={{ opacity: 1, y: 0 }}
      transition={{ delay: 0.04 * player.seat, duration: 0.8 }}
    >
      <AnimatePresence>
        {bubble && <motion.span key={bubble.id} className='cs-bubble cs-bubble--whisper' initial={{ opacity: 0, y: 6 }} animate={{ opacity: 1, y: 0 }} exit={{ opacity: 0 }}>{bubble.text}</motion.span>}
      </AnimatePresence>
      {/* 기둥 달린 침대 + 커튼 */}
      <span className='cs-bed__frame'>
        <Icon512 paths={BED} className='cs-bed__icon' />
      </span>
      {!empty && !gone && (
        <motion.span className='cs-bed__sleeper' animate={petrified ? undefined : { y: [0, -2, 0] }} transition={{ duration: 3.6, repeat: Infinity, ease: 'easeInOut' }}>
          <TokenAvatar accountId={player.account_id} avatar={player.avatar} size={Math.round(size * 0.52)} />
        </motion.span>
      )}
      {!empty && !gone && !petrified && (
        <span className='cs-bed__zzz' aria-hidden>
          {['z', 'z', 'Z'].map((letter, index) => (
            // eslint-disable-next-line react/no-array-index-key
            <motion.i key={index} animate={{ opacity: [0, 1, 0], y: [0, -14 - (index * 6)], x: [0, 6 + (index * 4)] }} transition={{ duration: 3, repeat: Infinity, delay: (index * 0.7) + ((player.seat % 4) * 0.4) }}>{letter}</motion.i>
          ))}
        </span>
      )}
      {dream && (
        <motion.span className='cs-bed__dream' initial={{ opacity: 0, scale: 0.4 }} animate={{ opacity: 1, scale: [1, 1.06, 1] }} transition={{ opacity: { duration: 1 }, scale: { duration: 3, repeat: Infinity } }}>
          <Icon512 paths={CRYSTAL_BALL} />
        </motion.span>
      )}
      <span className='cs-bed__name'>{player.name}{me && <small> (나)</small>}</span>
      {out && <em className='cs-bed__tag'>{petrified ? '석화' : out.by === 'forfeit' ? '기권' : '퇴학'}</em>}
      {player.role_name && <span className={player.dark ? 'cs-seat__role is-dark' : 'cs-seat__role'}>{player.role_name}</span>}
    </motion.div>
  );
};

const Dormitory: React.FC<{ view: CView; size: number; away: Away; dreaming: boolean; bubbles: Record<string, Bubble> }> = ({ view, size, away, dreaming, bubbles }) => {
  const spots = dormLayout(view.players.length);
  const myIndex = view.players.findIndex((player) => player.seat === view.me);
  const mySpot = spots[myIndex];
  const me = view.players[myIndex];
  const traitorOut = view.my_role?.key === 'traitor' && away !== 'bed';
  return (
    <motion.div className='cs-dorm-scene' initial={{ opacity: 0 }} animate={{ opacity: 1 }} exit={{ opacity: 0, transition: { duration: 0.8 } }} transition={{ duration: 1.2 }}>
      <span className='cs-dorm-door' style={{ left: `${DORM_DOOR.x}%`, top: `${DORM_DOOR.y}%` }}>
        <Icon512 paths={DOOR} />
        {/* 문틈으로 새는 복도 불빛: 내가 드나들 때만 */}
        <AnimatePresence>{(away === 'leaving' || away === 'returning') && <motion.i className='cs-dorm-door__light' initial={{ opacity: 0 }} animate={{ opacity: [0, 1, 1, 0] }} exit={{ opacity: 0 }} transition={{ duration: 2.6, times: [0, 0.6, 0.85, 1] }} />}</AnimatePresence>
      </span>
      {view.players.map((player, index) => (
        <Bed
          key={player.seat}
          player={player}
          view={view}
          at={spots[index] ?? { x: 50, y: 50, scale: 1, tilt: 0 }}
          size={size}
          // 나는 나가 있는 동안, 동료 방주도 비밀의 방에 함께 있는 동안 침대가 빈다
          empty={(player.seat === view.me && away !== 'bed') || (traitorOut && Boolean(view.my_role?.mates.includes(player.seat)))}
          dream={dreaming && player.seat === view.me}
          bubble={player.acct ? bubbles[player.acct] : undefined}
        />
      ))}
      {/* 몰래 일어나 문으로 (또는 문에서 침대로) 걸어간다 */}
      {me && mySpot && (away === 'leaving' || away === 'returning') && (
        <>
          <Footsteps key={`steps-${away}`} from={mySpot} to={DORM_DOOR} back={away === 'returning'} />
          <motion.span
            key={`walker-${away}`}
            className='cs-walker'
            initial={away === 'leaving' ? { left: `${mySpot.x}%`, top: `${mySpot.y}%`, opacity: 1 } : { left: `${DORM_DOOR.x}%`, top: `${DORM_DOOR.y}%`, opacity: 0 }}
            animate={away === 'leaving'
              ? { left: [`${mySpot.x}%`, `${mySpot.x}%`, `${DORM_DOOR.x}%`], top: [`${mySpot.y}%`, `${mySpot.y - 8}%`, `${DORM_DOOR.y}%`], opacity: [1, 1, 0] }
              : { left: `${mySpot.x}%`, top: `${mySpot.y}%`, opacity: [0, 1, 1] }}
            transition={{ duration: 2.4, times: away === 'leaving' ? [0, 0.2, 1] : undefined, ease: 'easeInOut' }}
          >
            <motion.span animate={{ y: [0, -4, 0] }} transition={{ duration: 0.4, repeat: Infinity }}>
              <TokenAvatar accountId={me.account_id} avatar={me.avatar} size={Math.round(size * 0.6)} />
            </motion.span>
          </motion.span>
        </>
      )}
    </motion.div>
  );
};

// ── 밤 나들이: 방주는 비밀의 방에서 표적을, 오러는 복도를 돌며 단서를, 치유사는 잠든 학생을 지킨다 ──
const NightJourney: React.FC<{ view: CView; busy: boolean; onSend: (command: string, target: string | null) => void; onReturn: () => void }> = ({ view, busy, onSend, onReturn }) => {
  const kind = view.night?.kind ?? 'protect';
  const traitor = kind === 'petrify';
  const [stage, setStage] = useState<'enter' | 'inside'>(traitor ? 'enter' : 'inside');
  const [pick, setPick] = useState<number | null>(view.night?.picked ?? null);
  useEffect(() => {
    if (stage !== 'enter') return undefined;
    // 비밀의 방 문 앞: 뱀의 말로 문을 연다
    DOOR_SNAKES.forEach((_, index) => { sfx.slither(1.2 + (index * 0.32)); });
    sfx.hiss(0.6);
    sfx.grind(3, 1.2);
    sfx.grind(4, 1.8);
    const timer = window.setTimeout(() => { setStage('inside'); sfx.growl(0.2); }, 5_600);
    return () => { window.clearTimeout(timer); };
  }, [stage]);
  const mates = view.my_role?.mates ?? [];
  const candidates = view.players.filter((player) => player.alive && (kind === 'protect' || player.seat !== view.me) && !(traitor && mates.includes(player.seat)));
  const crew = view.players.filter((player) => player.seat === view.me || mates.includes(player.seat));
  const chosen = view.players.find((player) => player.seat === pick);
  const done = view.night?.kind === 'investigate' && view.night.used;
  const command = traitor ? view.commands.petrify ?? '석화' : kind === 'investigate' ? view.commands.investigate ?? '조사' : view.commands.protect ?? '보호';
  const picksFor = (seat: number) => Object.values(view.petrify_picks).filter((target) => target === seat).length;
  return (
    <motion.div className={traitor ? 'cs-journey cs-journey--chamber' : 'cs-journey cs-journey--corridor'} initial={{ opacity: 0 }} animate={{ opacity: 1 }} exit={{ opacity: 0, transition: { duration: 0.6 } }} transition={{ duration: 0.8 }}>
      {traitor ? <ChamberHall /> : <div className='cs-corridor' aria-hidden>{Array.from({ length: 4 }, (_, index) => <i key={index} className='cs-corridor__torch' style={{ left: `${12 + (index * 25)}%` }} />)}</div>}
      <AnimatePresence mode='wait'>
        {stage === 'enter' ? (
          <motion.div key='enter' className='cs-journey__door' exit={{ opacity: 0, scale: 1.4, transition: { duration: 0.8 } }}>
            <motion.p className='cs-journey__whisper' initial={{ opacity: 0 }} animate={{ opacity: 1 }} transition={{ delay: 0.4 }}>“열려라…” 뱀의 말로 속삭이자 문의 뱀들이 움직인다</motion.p>
            <SnakeDoor />
          </motion.div>
        ) : (
          <motion.div key='inside' className='cs-journey__body' initial={{ opacity: 0, y: 20 }} animate={{ opacity: 1, y: 0 }} transition={{ duration: 0.7 }}>
            <h3 className='cs-journey__title'>
              {traitor ? <><SnakeIcon /> 오늘 밤의 표적</> : kind === 'investigate' ? <><Icon512 paths={LANTERN} className='cs-journey__icon' /> 기숙사를 돌며 단서 찾기</> : <><GameIcon name='shield' /> 잠든 학생 지키기</>}
            </h3>
            <p className='cs-journey__lead'>
              {traitor ? '동료와 의논해 바실리스크에게 보낼 표적을 고르세요. 가장 많이 고른 사람이 아침에 석화됩니다.'
                : kind === 'investigate' ? '등불을 들고 잠든 기숙사 방문을 하나 엽니다. 그 사람의 진영이 드러납니다. (밤마다 한 명)'
                  : '오늘 밤 지켜 줄 방문 앞에 섭니다. 그 방은 바실리스크가 들어오지 못합니다.'}
            </p>
            {traitor && (
              <div className='cs-journey__crew'>
                {crew.map((member) => <span key={member.seat}>{member.avatar && <img src={member.avatar} alt='' />}{member.name}</span>)}
              </div>
            )}
            {done ? (
              <p className='cs-journey__done'>단서를 찾았습니다. 우편함의 쪽지를 확인하세요.</p>
            ) : (
              <div className={traitor ? 'cs-targets' : 'cs-targets cs-targets--doors'}>
                {candidates.map((player, index) => {
                  const blocked = kind === 'protect' && view.night?.blocked === player.seat;
                  const picks = traitor ? picksFor(player.seat) : 0;
                  return (
                    <motion.button
                      key={player.seat}
                      type='button'
                      className={['cs-target', pick === player.seat && 'is-on', view.night?.picked === player.seat && 'is-sent'].filter(Boolean).join(' ')}
                      disabled={blocked || busy}
                      initial={{ opacity: 0, y: 14 }}
                      animate={{ opacity: 1, y: 0 }}
                      transition={{ delay: 0.15 + (index * 0.05) }}
                      whileHover={{ y: -4 }}
                      onClick={() => { setPick(player.seat); sfx.pick(); }}
                    >
                      {!traitor && <Icon512 paths={DOOR} className='cs-target__door' />}
                      <span className='cs-target__face'>{player.avatar ? <img src={player.avatar} alt='' /> : null}</span>
                      <b>{player.name}{player.seat === view.me ? ' (나)' : ''}</b>
                      {picks > 0 && <em className='cs-target__picks'><SnakeIcon />{picks}</em>}
                      {blocked && <small>어젯밤 지킴</small>}
                    </motion.button>
                  );
                })}
              </div>
            )}
            <div className='cs-journey__actions'>
              {!done && chosen && (
                <button type='button' className='cs-button cs-button--night' disabled={busy} onClick={() => { onSend(command, chosen.acct); }}>
                  {traitor ? `${chosen.name}에게 바실리스크를` : kind === 'investigate' ? `${chosen.name}의 방 살피기` : `${chosen.name} 지키기`}
                </button>
              )}
              {view.night?.picked !== null && view.night?.picked !== undefined && !done && <span className='cs-journey__sent'>정한 사람: {view.players.find((player) => player.seat === view.night?.picked)?.name}</span>}
              <button type='button' className='cs-button cs-button--ghost' onClick={onReturn}>기숙사로 돌아가기</button>
            </div>
          </motion.div>
        )}
      </AnimatePresence>
    </motion.div>
  );
};

// ── 부엉이 우편: 새 소식·쪽지는 부엉이가 물어 와 우편함에 떨어뜨린다. 눌러서 펼쳐 읽는다 ──
interface Letter { id: string; kind: 'notice' | 'note' | 'secret'; seal: 'notice' | 'prophecy' | 'clue' | 'secret'; title: string; text: string; tone: LogTone }

const LETTER_TITLE: Record<LogTone, string> = { day: '아침 공지', night: '밤 공지', petrify: '석화 소식', expel: '퇴학 소식', vote: '고발 결과', safe: '무사한 밤', end: '결과 발표', info: '알림' };

const letterTitle = (text: string) => {
  const first = text.split('\n')[0]?.trim() ?? '';
  return /^\d+일째/.test(first) && first.length <= 14 ? first : LETTER_TITLE[logTone(text)];
};

const OwlFlight: React.FC<{ onDone: () => void }> = ({ onDone }) => {
  const done = useRef(onDone);
  done.current = onDone;
  useEffect(() => {
    sfx.flutter(0);
    sfx.flutter(0.7);
    sfx.note();
    const timer = window.setTimeout(() => { done.current(); }, 2_600);
    return () => { window.clearTimeout(timer); };
  }, []);
  return (
    <motion.span
      className='cs-owl'
      initial={{ left: '-8%', top: '18%', rotate: 8 }}
      animate={{ left: ['-8%', '40%', '84%'], top: ['18%', '6%', '34%'], rotate: [8, -4, 6] }}
      transition={{ duration: 2.4, ease: 'easeInOut' }}
      aria-hidden
    >
      <motion.span className='cs-owl__body' animate={{ scaleY: [1, 0.82, 1] }} transition={{ duration: 0.32, repeat: Infinity }}>
        <Icon512 paths={OWL} />
      </motion.span>
      <motion.span className='cs-owl__letter' animate={{ rotate: [-12, 12, -12] }} transition={{ duration: 0.8, repeat: Infinity }}>
        <Icon512 paths={SCROLL_TIED} />
      </motion.span>
    </motion.span>
  );
};

const LetterIcon: React.FC<{ letter: Letter }> = ({ letter }) => (
  <Icon512 paths={letter.kind === 'notice' ? SCROLL_TIED : ENVELOPE} className={`cs-letter-icon cs-letter-icon--${letter.seal}`} />
);

// 우편함: 받은 양피지·쪽지 더미 (새것이 위)
const Mailbox: React.FC<{ letters: Letter[]; read: Set<string>; onOpen: (letter: Letter) => void }> = ({ letters, read, onOpen }) => (
  <ul className='cs-mail'>
    <AnimatePresence initial={false}>
      {letters.map((letter) => (
        <motion.li key={letter.id} layout initial={{ opacity: 0, y: -40, rotate: -8 }} animate={{ opacity: 1, y: 0, rotate: 0 }} transition={{ type: 'spring', stiffness: 180, damping: 16 }}>
          <button type='button' className={[`cs-mail__item cs-mail__item--${letter.seal}`, !read.has(letter.id) && 'is-new'].filter(Boolean).join(' ')} onClick={() => { onOpen(letter); }}>
            <LetterIcon letter={letter} />
            <span className='cs-mail__title'>{letter.title}</span>
            <span className='cs-mail__preview'>{letter.text.replace(/^\d+일째[^\n]*\n/, '').split('\n').find((line) => line.trim()) ?? ''}</span>
          </button>
        </motion.li>
      ))}
    </AnimatePresence>
    {letters.length === 0 && <li className='cs-mail__empty'>아직 도착한 부엉이가 없습니다.</li>}
  </ul>
);

// 펼친 양피지: 말린 종이가 위아래로 풀리고 봉랍이 깨진다
const LetterModal: React.FC<{ letter: Letter; onClose: () => void }> = ({ letter, onClose }) => {
  useEffect(() => { sfx.paper(0); if (letter.kind !== 'notice') sfx.crack(0.1); }, [letter]);
  const prophecy = letter.seal === 'prophecy';
  // 첫 줄이 제목과 같으면 본문에서 뺀다
  const lines = letter.text.split('\n');
  const body = lines[0]?.trim() === letter.title ? lines.slice(1).join('\n').trim() : letter.text;
  return (
    <motion.div className='cs-letter-modal' initial={{ opacity: 0 }} animate={{ opacity: 1 }} exit={{ opacity: 0 }} onClick={onClose}>
      <motion.div
        className={`cs-scroll cs-scroll--${letter.seal}`}
        initial={{ scaleY: 0.08, opacity: 0.6 }}
        animate={{ scaleY: 1, opacity: 1 }}
        exit={{ scaleY: 0.08, opacity: 0, transition: { duration: 0.3 } }}
        transition={{ type: 'spring', stiffness: 120, damping: 15 }}
        onClick={(event) => { event.stopPropagation(); }}
      >
        <i className='cs-scroll__roll cs-scroll__roll--top' />
        <div className='cs-scroll__paper'>
          {letter.kind !== 'notice' && <motion.span className='cs-scroll__seal' initial={{ scale: 1.6, opacity: 0 }} animate={{ scale: 1, opacity: 1 }} transition={{ delay: 0.3 }}><SnakeIcon /></motion.span>}
          <small className='cs-scroll__eyebrow'>{letter.kind === 'notice' ? '호그와트 공지' : letter.kind === 'secret' ? '비밀 쪽지' : prophecy ? '꿈속의 예언' : '단서'}</small>
          <h3>{letter.title}</h3>
          {prophecy ? <BloodText text={letter.text} delay={0.3} className='cs-scroll__blood' /> : <p>{body}</p>}
        </div>
        <i className='cs-scroll__roll cs-scroll__roll--bottom' />
        <button type='button' className='cs-button cs-button--small cs-scroll__close' onClick={onClose}>접기</button>
      </motion.div>
    </motion.div>
  );
};

// 작은 바실리스크 눈 (진행 기록의 석화 표시)
const EyeIcon: React.FC = () => (
  <svg className='game-icon' viewBox='0 0 512 512' width='1em' height='1em' aria-hidden>
    {BEAST_EYE.map((d) => <path key={d} d={d} fill='currentColor' />)}
  </svg>
);

// 예언 고르기: 기본 select 대신 펼쳐지는 목록 (사람은 초상과 함께)
interface PickOption { value: string; label: string; avatar?: string | null }

const CsPick: React.FC<{ value: string; options: PickOption[]; placeholder: string; icon: React.ReactNode; onChange: (value: string) => void }> = ({ value, options, placeholder, icon, onChange }) => {
  const [open, setOpen] = useState(false);
  const ref = useRef<HTMLDivElement>(null);
  const current = options.find((option) => option.value === value);
  useEffect(() => {
    if (!open) return undefined;
    const close = (event: MouseEvent) => { if (!ref.current?.contains(event.target as Node)) setOpen(false); };
    document.addEventListener('mousedown', close);
    return () => { document.removeEventListener('mousedown', close); };
  }, [open]);
  return (
    <div ref={ref} className={open ? 'cs-pick is-open' : 'cs-pick'}>
      <button type='button' className={current ? 'cs-pick__face' : 'cs-pick__face is-empty'} onClick={() => { setOpen((now) => !now); }}>
        {current?.avatar ? <img src={current.avatar} alt='' /> : <span className='cs-pick__icon'>{icon}</span>}
        <span className='cs-pick__label'>{current?.label ?? placeholder}</span>
        <motion.i className='cs-pick__caret' animate={{ rotate: open ? 180 : 0 }} aria-hidden>▾</motion.i>
      </button>
      <AnimatePresence>
        {open && (
          <motion.ul
            className='cs-pick__list'
            initial={{ opacity: 0, y: -6, scaleY: 0.85 }}
            animate={{ opacity: 1, y: 0, scaleY: 1 }}
            exit={{ opacity: 0, y: -6, scaleY: 0.85, transition: { duration: 0.12 } }}
            transition={{ duration: 0.18 }}
          >
            {options.map((option, index) => (
              <motion.li key={option.value} initial={{ opacity: 0, x: -8 }} animate={{ opacity: 1, x: 0 }} transition={{ delay: index * 0.025 }}>
                <button type='button' className={option.value === value ? 'is-on' : undefined} onClick={() => { onChange(option.value); setOpen(false); sfx.pick(); }}>
                  {option.avatar !== undefined && (option.avatar ? <img src={option.avatar} alt='' /> : <span className='cs-pick__dot' />)}
                  <span>{option.label}</span>
                </button>
              </motion.li>
            ))}
          </motion.ul>
        )}
      </AnimatePresence>
    </div>
  );
};

// 진행 기록 한 줄의 종류 (문구의 낱말로 고른다)
type LogTone = 'day' | 'night' | 'petrify' | 'expel' | 'vote' | 'safe' | 'end' | 'info';

const logTone = (text: string): LogTone => {
  if (/^\d+일째 밤/.test(text)) return 'night';
  if (/^\d+일째 낮/.test(text)) return 'day';
  if (/승리|종료|무승부/.test(text)) return 'end';
  if (/석화/.test(text)) return 'petrify';
  if (/퇴학되지 않|고발/.test(text) && !/퇴학되었|퇴학입니다|퇴학당/.test(text)) return 'vote';
  if (/퇴학/.test(text)) return 'expel';
  if (/아무 일도/.test(text)) return 'safe';
  if (/일째 밤/.test(text)) return 'night';
  if (/아침|일째 낮/.test(text)) return 'day';
  return 'info';
};

const LOG_ICON: Record<LogTone, React.ReactNode> = {
  day: <GameIcon name='sun' />,
  night: <GameIcon name='moon' />,
  petrify: <EyeIcon />,
  expel: <GameIcon name='x' />,
  vote: <GameIcon name='hands' />,
  safe: <GameIcon name='shield' />,
  end: <GameIcon name='crown' />,
  info: <GameIcon name='sparkle' />,
};

// 진행 기록: 왼쪽 세로줄에 종류별 표식이 달린 연대기
const LogList: React.FC<{ log: CsMessage[] }> = ({ log }) => (
  <>
    {log.map((message) => {
      const tone = logTone(message.text);
      const banner = tone === 'day' || tone === 'night';
      return (
        <motion.li key={message.id} className={`cs-log cs-log--${tone}${banner ? ' is-banner' : ''}`} initial={{ opacity: 0, x: -10 }} animate={{ opacity: 1, x: 0 }} transition={{ duration: 0.35 }}>
          <span className='cs-log__mark'>{LOG_ICON[tone]}</span>
          <p className='cs-log__text'>{message.text}</p>
        </motion.li>
      );
    })}
    {log.length === 0 && <li className='cs-log cs-log--info is-empty'><span className='cs-log__mark'>{LOG_ICON.info}</span><p className='cs-log__text'>아직 기록이 없습니다.</p></li>}
  </>
);

// ── 오른쪽: 우편함(부엉이가 가져온 양피지·쪽지) · 예언 (방주끼리 이야기는 아래 채팅의 방주방) ──
const SidePanel: React.FC<{ view: CView; letters: Letter[]; read: Set<string>; onOpen: (letter: Letter) => void; onSend: (command: string, args: string) => void; busy: boolean }> = ({ view, letters, read, onOpen, onSend, busy }) => {
  const traitor = view.my_role?.key === 'traitor';
  const [tab, setTab] = useState<'notes' | 'prophecy'>('notes');
  const [kind, setKind] = useState('');
  const [targets, setTargets] = useState<string[]>(['', '']);
  const alive = view.players.filter((player) => player.alive);
  const chosen = view.prophecy_kinds.find((item) => item.key === kind) ?? view.prophecy_kinds[0];
  const unread = letters.filter((letter) => !read.has(letter.id)).length;
  return (
    <aside className='cs-side'>
      <div className='cs-side__tabs'>
        <button type='button' className={tab === 'notes' ? 'is-on' : undefined} onClick={() => { setTab('notes'); }}>우편함{unread > 0 && <em>{unread}</em>}</button>
        {traitor && <button type='button' className={tab === 'prophecy' ? 'is-on is-dark' : 'is-dark'} onClick={() => { setTab('prophecy'); }}>예언</button>}
      </div>
      {tab === 'notes' && <Mailbox letters={letters} read={read} onOpen={onOpen} />}
      {tab === 'prophecy' && chosen && (
        <div className='cs-side__prophecy'>
          <p>밤마다 예언자에게 진실 하나를 전합니다. 사실이 아닌 예언은 전해지지 않습니다.</p>
          {view.prophecy && <p className='cs-side__current'>정한 예언: <b>{view.prophecy}</b></p>}
          <span className='cs-side__label'>무엇을 알릴까</span>
          <CsPick value={chosen.key} placeholder='예언 종류' icon={<GameIcon name='sparkle' />} options={view.prophecy_kinds.map((item) => ({ value: item.key, label: item.label }))} onChange={setKind} />
          <span className='cs-side__label'>{chosen.count > 1 ? '누구 둘' : '누구'}</span>
          {Array.from({ length: chosen.count }, (_, index) => (
            <CsPick
              // eslint-disable-next-line react/no-array-index-key
              key={index}
              value={targets[index] ?? ''}
              placeholder={chosen.count > 1 ? `${index + 1}번째 사람` : '사람 고르기'}
              icon={<GameIcon name='scope' />}
              options={alive.map((player) => ({ value: player.acct ?? '', label: player.name, avatar: player.avatar }))}
              onChange={(value) => { const next = [...targets]; next[index] = value; setTargets(next); }}
            />
          ))}
          <button
            type='button'
            className='cs-button cs-button--small'
            disabled={busy || view.phase !== 'night' || targets.slice(0, chosen.count).some((each) => !each)}
            onClick={() => { onSend(view.commands.prophecy ?? '예언', [chosen.key, ...targets.slice(0, chosen.count)].join('/')); }}
          >
            예언 정하기
          </button>
          {view.phase !== 'night' && <small className='cs-side__hint'>예언은 밤에만 정할 수 있습니다.</small>}
        </div>
      )}
    </aside>
  );
};

// ── 아래: 채팅 (도둑 지도처럼 탭으로 보는 곳, 입력칸 앞 고르기로 쓰는 곳) ──
//   탭: 대화(전체) · 방주방(방주·관전) · 진행 기록. 쓰는 곳: 낮에는 전체/방주방, 밤에는 모두 잠들어 방주방만 (방주가 아니면 밤엔 채팅창이 없다)
type ChatTab = 'all' | 'dark' | 'log';
type WriteTo = 'all' | 'dark';

const ChatDock: React.FC<{
  sessionId: string;
  view: CView;
  chat: CsMessage[];
  log: CsMessage[];
  canChat: boolean;
  busy: boolean;
  onDark: (text: string) => void;
  onSent: () => void;
}> = ({ sessionId, view, chat, log, canChat, busy, onDark, onSent }) => {
  const traitor = view.my_role?.key === 'traitor';
  const night = view.phase === 'night' && view.status === 'active';
  const showDark = traitor || (view.spectator && view.dark_chat.length > 0);
  const tabs: ChatTab[] = showDark ? ['all', 'dark', 'log'] : ['all', 'log'];
  const [tab, setTab] = useState<ChatTab>(traitor && night ? 'dark' : 'all');
  // 쓰는 곳: 방주는 전체/방주방 (밤엔 방주방만), 나머지는 전체만
  const writeOptions: WriteTo[] = traitor && view.alive_me && view.status === 'active' ? (night ? ['dark'] : ['all', 'dark']) : canChat && !night ? ['all'] : [];
  const [writeTo, setWriteTo] = useState<WriteTo>(traitor && night ? 'dark' : 'all');
  const target: WriteTo | null = writeOptions.includes(writeTo) ? writeTo : (writeOptions[0] ?? null);
  const [pickOpen, setPickOpen] = useState(false);
  const [text, setText] = useState('');
  const listRef = useRef<HTMLUListElement>(null);

  // 밤이 되면 방주는 방주방으로
  useEffect(() => {
    if (traitor && night) { setTab('dark'); setWriteTo('dark'); }
  }, [traitor, night]);

  // 안 본 수 (보고 있는 탭은 0)
  const counts: Record<ChatTab, number> = { all: chat.length, dark: view.dark_chat.length, log: log.length };
  const seen = useRef<Record<ChatTab, number>>({ ...counts });
  seen.current[tab] = counts[tab];
  const unread = (each: ChatTab) => Math.max(0, counts[each] - seen.current[each]);
  const label = (each: ChatTab) => (each === 'all' ? '전체' : each === 'dark' ? `${view.traitor_name}방` : '진행 기록');

  useEffect(() => {
    if (listRef.current) listRef.current.scrollTop = listRef.current.scrollHeight;
  }, [chat.length, view.dark_chat.length, log.length, tab]);

  const submit = (event: React.FormEvent) => {
    event.preventDefault();
    const value = text.trim();
    if (!value || !target) return;
    setText('');
    if (target === 'dark') {
      onDark(value);
      return;
    }
    apiRequestPost(`v1/system/sessions/${sessionId}/chat`, { text: value })
      .then(() => { onSent(); return true; })
      .catch(() => { onSent(); });
  };

  const me = view.players.find((player) => player.seat === view.me);
  return (
    <section className={tab === 'dark' ? 'cs-chat cs-chat--dark' : 'cs-chat'}>
      <div className='cs-chat__tabs'>
        {tabs.map((each) => (
          <button key={each} type='button' className={[`is-${each}`, tab === each && 'is-on'].filter(Boolean).join(' ')} onClick={() => { setTab(each); }}>
            {each === 'dark' && <SnakeIcon />} {label(each)}
            {tab !== each && unread(each) > 0 && <b className='cs-chat__badge'>{unread(each) > 99 ? '99+' : unread(each)}</b>}
          </button>
        ))}
      </div>
      <ul ref={listRef} className={tab === 'log' ? 'cs-chat__list is-log' : 'cs-chat__list'}>
        {tab === 'log' && <LogList log={log} />}
        {tab === 'all' && chat.map((message) => (
          <li key={message.id} className={message.mine ? 'is-mine' : undefined}>
            {message.avatar && <img src={message.avatar} alt='' />}
            <strong>{message.name}</strong>
            <span>: {message.text}</span>
          </li>
        ))}
        {tab === 'all' && night && <li className='is-system'>밤에는 모두 잠들어 대화할 수 없습니다.</li>}
        {tab === 'dark' && view.dark_chat.map((line, index) => {
          const speaker = view.players.find((player) => player.name === line.name);
          return (
            // eslint-disable-next-line react/no-array-index-key
            <li key={index} className={speaker && speaker.seat === me?.seat ? 'is-mine' : undefined}>
              {speaker?.avatar && <img src={speaker.avatar} alt='' />}
              <strong>{line.name}</strong>
              <span>: {line.text}</span>
            </li>
          );
        })}
        {tab === 'dark' && view.dark_chat.length === 0 && <li className='is-system'>동료 {view.traitor_name}와 몰래 의논하세요. 다른 사람에게는 보이지 않습니다.</li>}
      </ul>
      {target ? (
        <form onSubmit={submit}>
          {writeOptions.length > 1 ? (
            // 보낼 곳 고르기: 누르면 위로 목록이 펼쳐진다
            <span className='cs-chat__pick'>
              <button type='button' className={`cs-chat__to is-${target}`} aria-haspopup='listbox' aria-expanded={pickOpen} aria-label='채팅 보낼 곳' onClick={() => { setPickOpen((value) => !value); }}>
                {target === 'dark' && <SnakeIcon />} {label(target)} <span aria-hidden>{pickOpen ? '▾' : '▴'}</span>
              </button>
              <AnimatePresence>
                {pickOpen && (
                  <motion.ul className='cs-chat__menu' role='listbox' initial={{ opacity: 0, y: 6 }} animate={{ opacity: 1, y: 0 }} exit={{ opacity: 0, y: 6 }} transition={{ duration: 0.15 }}>
                    {writeOptions.map((option) => (
                      <li key={option}>
                        <button type='button' role='option' aria-selected={option === target} className={['cs-chat__option', `is-${option}`, option === target && 'is-on'].filter(Boolean).join(' ')} onClick={() => { setWriteTo(option); setPickOpen(false); setTab(option); }}>
                          <b>{option === 'dark' && <SnakeIcon />} {label(option)}</b>
                          <small>{option === 'dark' ? `동료 ${view.traitor_name}에게만` : '모두에게'}</small>
                        </button>
                      </li>
                    ))}
                  </motion.ul>
                )}
              </AnimatePresence>
            </span>
          ) : (
            <span className={`cs-chat__to is-${target}`}>{target === 'dark' && <SnakeIcon />} {label(target)}</span>
          )}
          <input type='text' value={text} maxLength={200} placeholder={target === 'dark' ? '동료에게 속삭이기…' : '토론하기…'} onChange={(event) => { setText(event.target.value); }} />
          <button type='submit' className={target === 'dark' ? 'cs-button cs-button--small cs-button--night' : 'cs-button cs-button--small'} disabled={!text.trim() || (target === 'dark' && busy)}>보내기</button>
        </form>
      ) : (
        <p className='cs-chat__muted'>{view.my_role && !view.alive_me ? '탈락한 사람은 말할 수 없습니다. 조용히 지켜보세요.' : night ? '밤에는 모두 잠들어 대화할 수 없습니다.' : '관전 중에는 말할 수 없습니다.'}</p>
      )}
    </section>
  );
};

// ── 끝: 승리 진영 → 모든 정체 공개 ──
const EndScreen: React.FC<{ view: CView; onLeave: () => void }> = ({ view, onLeave }) => {
  const light = view.winner === 'light';
  const title = view.winner === 'draw' ? '무승부' : `${light ? view.faction_light : view.faction_dark} 진영 승리!`;
  useEffect(() => { sfx.win(0.3); }, []);
  return (
    <motion.div className={`cs-end cs-end--${view.winner ?? 'draw'}`} initial={{ opacity: 0 }} animate={{ opacity: 1 }}>
      <motion.span className='cs-end__crest' initial={{ scale: 0, rotate: -180 }} animate={{ scale: 1, rotate: 0 }} transition={{ type: 'spring', stiffness: 90, damping: 11 }}>
        {light ? <GameIcon name='crown' /> : <SnakeIcon />}
      </motion.span>
      <FireWords text={title} delay={0.5} tone={light ? 'gold' : 'fire'} className='cs-end__title' />
      <p>{view.winner === 'draw' ? '시간이 다 되었습니다.' : light ? `숨어 있던 ${view.traitor_name}가 모두 퇴학되었습니다.` : `${view.traitor_name}가 학교를 장악했습니다.`}</p>
      <ul className='cs-end__roles'>
        {view.players.map((player, index) => (
          <motion.li key={player.seat} className={player.dark ? 'is-dark' : undefined} initial={{ rotateY: 90, opacity: 0 }} animate={{ rotateY: 0, opacity: 1 }} transition={{ delay: 1 + (index * 0.12), duration: 0.5 }}>
            {player.avatar && <img src={player.avatar} alt='' className={player.alive ? undefined : 'is-out'} />}
            <b>{player.name}</b>
            <span>{player.role_name}</span>
          </motion.li>
        ))}
      </ul>
      <button type='button' className='cs-button' onClick={onLeave}>나가기</button>
    </motion.div>
  );
};

// ── 무대 ──
export const ChamberStage: React.FC<{
  sessionId: string;
  name: string;
  messages: CsMessage[];
  staff: boolean;
  isPlayer: boolean;
  onChanged: () => void;
}> = ({ sessionId, name, messages, isPlayer, onChanged }) => {
  const history = useHistory();
  const [view, setView] = useState<CView | null>(null);
  const [selected, setSelected] = useState<number | null>(null);
  const [busy, setBusy] = useState(false);
  const [intro, setIntro] = useState<'pending' | 'opening' | 'role' | 'done'>('pending');
  const [cues, setCues] = useState<Cue[]>([]);
  const [sound, setSound] = useState(soundOn);
  const [ended, setEnded] = useState(false);
  const now = useClock();
  useStageLayout(true);

  const load = useCallback(() => {
    apiRequestGet<{ view: CView | null }>(`v1/system/sessions/${sessionId}/view`)
      .then((response) => { if (response.view) setView(response.view); return response; })
      .catch(() => undefined);
  }, [sessionId]);

  useEffect(() => {
    load();
    const timer = window.setInterval(load, REFRESH_MS);
    return () => { window.clearInterval(timer); };
  }, [load]);

  // 처음: 첫날 낮이면 오프닝 → 역할 카드, 아니면 역할 카드만 (한 번만, 구경꾼은 없음)
  const introChecked = useRef(false);
  useEffect(() => {
    if (!view || introChecked.current) return;
    introChecked.current = true;
    let seen = false;
    try { seen = window.sessionStorage.getItem(`ssm:cs-intro:${sessionId}`) === '1'; } catch { seen = false; }
    if (seen || view.status === 'finished' || !view.my_role) setIntro('done');
    else setIntro(view.day <= 1 && view.phase === 'day' ? 'opening' : 'role');
  }, [view, sessionId]);
  const finishIntro = useCallback(() => {
    setIntro('done');
    try { window.sessionStorage.setItem(`ssm:cs-intro:${sessionId}`, '1'); } catch { /* 계속 */ }
  }, [sessionId]);

  // 바뀐 것 → 연출 차례. 밤→아침이면 (예언자의 꿈 →) 비밀의 방 문이 열리고 석화 → 아침, 처음 받은 화면은 기준만 잡는다
  const seen = useRef<{ phase: string | null; day: number; outs: number; notes: number } | null>(null);
  useEffect(() => {
    if (!view) return;
    const before = seen.current;
    seen.current = { phase: view.phase, day: view.day, outs: view.out_log.length, notes: view.notes.length };
    if (!before) return;
    const next: Cue[] = [];
    view.out_log.slice(before.outs).forEach((entry) => {
      const player = view.players.find((each) => each.seat === entry.seat);
      if (!player || entry.by === 'forfeit') return;
      next.push({ id: `out-${entry.seat}`, kind: entry.by === 'petrify' ? 'petrify' : 'expel', player, roleName: entry.role_name, dark: entry.dark });
    });
    const morning = before.phase === 'night' && view.phase === 'day';
    if (morning && !next.some((cue) => cue.kind === 'petrify')) next.push({ id: `safe-${view.day}`, kind: 'safe' });
    if (before.phase !== view.phase && (view.phase === 'day' || view.phase === 'night')) next.push({ id: `${view.phase}-${view.day}`, kind: view.phase, day: view.day });
    // 내 쪽지: 예언자는 꿈속 예언(깨기 전에 먼저), 오러는 단서 장면
    const notes: Cue[] = [];
    view.notes.slice(before.notes).forEach((note, index) => {
      const id = `note-${before.notes + index}`;
      if (view.my_role?.key === 'seer') notes.push({ id, kind: 'prophecy', text: note.text.replace(/^\d+일째 밤의 예언:\s*/, '') });
      else if (view.my_role?.key === 'auror') notes.push({ id, kind: 'clue', text: note.text });
    });
    const all = morning ? [...notes, ...next] : [...next, ...notes];
    if (all.length > 0) setCues((current) => [...current, ...all]);
    if (before.phase !== view.phase) setSelected(null);
  }, [view]);

  // 연출을 하나씩: 효과음 + 일정 시간 뒤 다음
  const cue = cues[0];
  useEffect(() => {
    // 오프닝·역할 카드를 보는 동안에는 기다린다
    if (!cue || intro !== 'done') return undefined;
    playCue(cue.kind);
    const length = CUE_LENGTH[cue.kind];
    const timer = window.setTimeout(() => { setCues((current) => current.slice(1)); }, length);
    return () => { window.clearTimeout(timer); };
  }, [cue, intro]);

  // 우편: 공지(시스템 안내)·내 쪽지·비밀 쪽지를 양피지로. 역할 안내 DM 은 역할 카드가 대신한다
  const seer = view?.my_role?.key === 'seer';
  const arrival = useRef(new Map<string, number>());
  const letters = useMemo<Letter[]>(() => {
    if (!view) return [];
    const list: Letter[] = [];
    messages.forEach((message) => {
      if (message.kind === 'system') list.push({ id: message.id, kind: 'notice', seal: 'notice', title: letterTitle(message.text), text: message.text, tone: logTone(message.text) });
    });
    view.notes.forEach((note, index) => {
      list.push({ id: `note-${index}`, kind: 'note', seal: seer ? 'prophecy' : 'clue', title: `${note.day}일째 밤의 ${seer ? '예언' : '단서'}`, text: seer ? note.text.replace(/^\d+일째 밤의 예언:\s*/, '') : note.text, tone: 'info' });
    });
    messages.forEach((message) => {
      // 방주끼리 밀담 전달은 밀담 창에서 보니 우편으로 넣지 않는다
      if (message.kind !== 'secret' || message.text.startsWith('당신의 역할은') || message.text.startsWith('[밀담]')) return;
      // 쪽지(notes)로 이미 보이는 비밀 안내는 다시 넣지 않는다
      if (view.notes.some((note) => note.text === message.text || message.text.endsWith(note.text))) return;
      list.push({ id: message.id, kind: 'secret', seal: 'secret', title: '비밀 쪽지', text: message.text, tone: 'info' });
    });
    list.forEach((letter) => { if (!arrival.current.has(letter.id)) arrival.current.set(letter.id, arrival.current.size); });
    return list.sort((a, b) => (arrival.current.get(b.id) ?? 0) - (arrival.current.get(a.id) ?? 0));
  }, [messages, view, seer]);

  // 읽은 양피지 (이 창에서만 기억)
  const readKey = `ssm:cs-read:${sessionId}`;
  const [read, setRead] = useState<Set<string>>(() => {
    try { return new Set<string>(JSON.parse(window.sessionStorage.getItem(readKey) ?? '[]') as string[]); } catch { return new Set<string>(); }
  });
  const [openLetter, setOpenLetter] = useState<Letter | null>(null);
  const openOne = useCallback((letter: Letter) => {
    setOpenLetter(letter);
    setRead((current) => {
      const next = new Set(current);
      next.add(letter.id);
      try { window.sessionStorage.setItem(readKey, JSON.stringify([...next])); } catch { /* 이번만 */ }
      return next;
    });
  }, [readKey]);

  // 새 양피지가 오면 부엉이가 날아온다 (처음 받은 것들은 이미 와 있던 것)
  const knownLetters = useRef<Set<string> | null>(null);
  const [owls, setOwls] = useState<string[]>([]);
  useEffect(() => {
    if (!view) return;
    if (!knownLetters.current) { knownLetters.current = new Set(letters.map((letter) => letter.id)); return; }
    const known = knownLetters.current;
    const fresh = letters.filter((letter) => !known.has(letter.id));
    fresh.forEach((letter) => { known.add(letter.id); });
    if (fresh.length > 0) setOwls((current) => [...current, fresh[0]?.id ?? ''].slice(-2));
  }, [letters, view]);

  // 말풍선: 새 대화는 말한 사람 위에 6초 동안
  const [bubbles, setBubbles] = useState<Record<string, Bubble>>({});
  const chatSeen = useRef<Set<string> | null>(null);
  useEffect(() => {
    const chats = messages.filter((message) => message.kind === 'chat');
    if (!chatSeen.current) { chatSeen.current = new Set(chats.map((message) => message.id)); return; }
    const known = chatSeen.current;
    const fresh = chats.filter((message) => !known.has(message.id));
    if (fresh.length === 0) return;
    fresh.forEach((message) => { known.add(message.id); });
    setBubbles((current) => {
      const next = { ...current };
      fresh.forEach((message) => { next[message.acct] = { id: message.id, text: message.text }; });
      return next;
    });
    fresh.forEach((message) => {
      window.setTimeout(() => {
        setBubbles((current) => {
          if (current[message.acct]?.id !== message.id) return current;
          const next = { ...current };
          delete next[message.acct];
          return next;
        });
      }, 6_000);
    });
  }, [messages]);

  // 끝: 연출이 다 끝난 뒤 결과 화면
  useEffect(() => {
    if (view?.status === 'finished' && cues.length === 0) {
      const timer = window.setTimeout(() => { setEnded(true); }, 800);
      return () => { window.clearTimeout(timer); };
    }
    return undefined;
  }, [view?.status, cues.length]);

  const send = useCallback((command: string, options: { target?: string | null; args?: string } = {}) => {
    setBusy(true);
    sfx.pick();
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

  // 밤 나들이: 밤에 할 일이 있는 사람(방주·오러·치유사)은 연출이 끝나면 몰래 일어나 문으로 나간다 → 할 일 → 돌아온다
  const night = view?.phase === 'night';
  const nightActor = Boolean(view && isPlayer && view.alive_me && view.status === 'active' && night && view.night);
  const [away, setAway] = useState<Away>('bed');
  const leftOn = useRef<number | null>(null);
  useEffect(() => {
    if (!nightActor) { if (away !== 'bed') setAway('bed'); return; }
    if (intro !== 'done' || cue || away !== 'bed' || leftOn.current === view?.day) return;
    leftOn.current = view?.day ?? null;
    setAway('leaving');
  }, [nightActor, intro, cue, away, view?.day]);
  useEffect(() => {
    if (away !== 'leaving' && away !== 'returning') return undefined;
    [0.3, 0.6, 0.9, 1.2, 1.5, 1.8].forEach((at) => { sfx.step(at); });
    if (away === 'leaving') sfx.creak(2);
    const timer = window.setTimeout(() => { setAway(away === 'leaving' ? 'out' : 'bed'); }, 2_600);
    return () => { window.clearTimeout(timer); };
  }, [away]);

  const total = view?.players.length ?? 0;
  const seatSize = total > 16 ? 56 : total > 11 ? 64 : 76;

  if (!view) return createPortal(<div className='game-stage cs-stage' role='region' aria-label={name} />, document.body);

  const alive = view.alive_me;
  const target = view.players.find((player) => player.seat === selected) ?? null;
  const playing = view.status === 'active' && (view.phase === 'day' || view.phase === 'night');
  // 낮에 할 일: 고발 (밤 행동은 밤 나들이 화면에서)
  const action = playing && alive && isPlayer && view.phase === 'day'
    ? { command: view.commands.accuse ?? '고발', verb: '고발하기', ask: '토론하고, 수상한 사람을 눌러 고발하세요.', done: view.my_vote !== null ? `고발한 사람: ${view.players.find((each) => each.seat === view.my_vote)?.name ?? ''} (바꿀 수 있어요)` : null }
    : null;
  const selectable = (player: CPlayer) => Boolean(action) && player.alive && player.seat !== view.me;
  const phaseEnds = view.deadline_at ? Date.parse(view.deadline_at) - now : 0;
  const allEnds = view.ends_at ? Date.parse(view.ends_at) - now : 0;
  const dreaming = night && seer && alive && view.status === 'active';
  const idleText = !isPlayer || view.spectator ? '관전 중입니다. 모든 정체가 보입니다.'
    : !alive ? '탈락했습니다. 모든 정체를 보며 지켜보세요.'
      : night && dreaming ? '깊은 잠에 빠졌습니다… 꿈속에서 누군가 속삭이려 합니다.'
        : night && !view.night ? '모두 잠들었습니다… 아침이 밝기를 기다립니다.'
          : night && away === 'bed' && nightActor ? '침대로 돌아왔습니다. 아직 밤입니다.'
            : '';

  return createPortal(
    <div className={night ? 'game-stage cs-stage cs-stage--night' : 'game-stage cs-stage cs-stage--day'} role='region' aria-label={name}>
      {/* 배경: 낮은 대연회장(창·깃발·떠 있는 촛불), 밤은 불 꺼진 기숙사 */}
      <div className='cs-backdrop' aria-hidden>
        <AnimatePresence>
          {night ? <DormRoom key='dorm' /> : <HogwartsHall key='hogwarts' />}
        </AnimatePresence>
        {night && <i className='cs-fog cs-fog--a' />}
      </div>

      {/* 맨 위: 며칠째 · 낮/밤 · 남은 시간 · 내 역할 · 소리 · 나가기 */}
      <header className='cs-top'>
        <span className={night ? 'cs-chip cs-chip--night' : 'cs-chip cs-chip--day'}><GameIcon name={night ? 'moon' : 'sun'} /> {view.day}일째 {night ? '밤' : '낮'}</span>
        {playing && view.deadline_at && <span className={phaseEnds < 30_000 ? 'cs-timer is-low' : 'cs-timer'}><GameIcon name='hourglass' /> {mmss(phaseEnds)}</span>}
        {playing && view.ends_at && <span className='cs-chip cs-chip--dim'>전체 {mmss(allEnds)} · {view.phase_no}/{view.max_phases}</span>}
        <span className='cs-chip cs-chip--dim'>{view.traitor_name} {view.traitor_count}명 · 남은 사람 {view.players.filter((player) => player.alive).length}명</span>
        {view.my_role && (
          <button type='button' className={view.my_role.dark ? 'cs-chip cs-chip--role is-dark' : 'cs-chip cs-chip--role'} onClick={() => { setIntro('role'); }} title='내 역할 다시 보기'>
            <RoleSigil role={view.my_role.key} /> {view.my_role.name}
          </button>
        )}
        <button type='button' className={sound ? 'cs-sound' : 'cs-sound is-off'} onClick={toggleSound} aria-pressed={sound} title={sound ? '소리 끄기' : '소리 켜기'}>{sound ? '♪' : '×'}</button>
        <button type='button' className='cs-exit' onClick={() => { history.push('/system/group'); }}>나가기</button>
      </header>

      <div className='cs-main'>
        {/* 가운데 장면: 낮은 대연회장 긴 식탁, 밤은 기숙사 침대 (+ 내 밤 나들이) */}
        <div className='cs-scene'>
          <AnimatePresence mode='wait'>
            {night
              ? <Dormitory key={`dorm-${view.day}`} view={view} size={seatSize} away={away} dreaming={dreaming} bubbles={bubbles} />
              : (
                <GreatHall
                  key={`hall-${view.day}`}
                  view={view}
                  size={seatSize}
                  selected={selected}
                  selectable={selectable}
                  bubbles={bubbles}
                  onPick={(picked) => { setSelected((current) => (current === picked.seat ? null : picked.seat)); }}
                />
              )}
          </AnimatePresence>
          <AnimatePresence>
            {night && nightActor && away === 'out' && (
              <NightJourney
                key={`journey-${view.day}`}
                view={view}
                busy={busy}
                onSend={(command, picked) => { send(command, { target: picked }); }}
                onReturn={() => { setAway('returning'); }}
              />
            )}
          </AnimatePresence>
        </div>

        <SidePanel view={view} letters={letters} read={read} onOpen={openOne} busy={busy} onSend={(command, args) => { send(command, { args }); }} />
      </div>

      {/* 할 일 띠: 낮은 고발, 밤은 지금 내 처지 */}
      <div className={action || (night && nightActor && away === 'bed') ? 'cs-action is-on' : 'cs-action'}>
        {action ? (
          <>
            <span className='cs-action__ask'>{action.done ?? action.ask}</span>
            <AnimatePresence>
              {target && selectable(target) && (
                <motion.button key={target.seat} type='button' className='cs-button' initial={{ opacity: 0, y: 8 }} animate={{ opacity: 1, y: 0 }} exit={{ opacity: 0 }} disabled={busy} onClick={() => { send(action.command, { target: target.acct }); setSelected(null); }}>
                  {target.name} {action.verb}
                </motion.button>
              )}
            </AnimatePresence>
          </>
        ) : (
          <>
            {idleText && <span className='cs-action__ask'>{idleText}</span>}
            {night && nightActor && away === 'bed' && intro === 'done' && !cue && <button type='button' className='cs-button cs-button--night' onClick={() => { setAway('leaving'); }}>다시 몰래 나가기</button>}
          </>
        )}
      </div>

      {/* 채팅: 밤에는 모두 잠들어 방주만 (방주방), 나머지는 채팅창이 없다 */}
      {!(night && playing && !(view.my_role?.key === 'traitor' && alive && isPlayer)) && (
        <ChatDock
          sessionId={sessionId}
          view={view}
          chat={messages.filter((message) => message.kind === 'chat')}
          log={messages.filter((message) => message.kind === 'system')}
          canChat={isPlayer && (alive || view.status !== 'active')}
          busy={busy}
          onDark={(text) => { send(view.commands.chat ?? '밀담', { args: text }); }}
          onSent={onChanged}
        />
      )}

      {/* 부엉이 · 펼친 양피지 */}
      {owls.map((id) => <OwlFlight key={id} onDone={() => { setOwls((current) => current.filter((each) => each !== id)); }} />)}
      <AnimatePresence>
        {openLetter && <LetterModal key={openLetter.id} letter={openLetter} onClose={() => { setOpenLetter(null); }} />}
      </AnimatePresence>

      {/* 오프닝 · 역할 카드 · 연출 · 결과 */}
      {createPortal(
        <AnimatePresence>
          {intro === 'opening' && <Opening key='opening' onDone={() => { setIntro('role'); }} />}
        </AnimatePresence>,
        document.body,
      )}
      <AnimatePresence>
        {intro === 'role' && view.my_role && <RoleModal key='role' view={view} onClose={finishIntro} />}
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
