// 그린고츠 게임방 (웹 전용 이벤트, 로우볼 숫자 게임): 그린고츠 마법 은행의 금고실. 고블린이 "혼자 부른 가장 작은 숫자"에게만 금화를 준다.
//   오프닝: 금고 문이 열리고 → 고블린의 규칙 안내
//   숫자 고르기: 숫자 금고를 눌러 하나를 몰래 고른다 (모두 내거나 시간이 끝나면 공개)
//   금고 공개: 1번 금고부터 차례로 문이 열린다. 여럿이 고른 숫자는 고블린이 고개를 젓고 문을 쾅 닫는다 (가장 많이 몰렸으면 세금).
//             처음으로 혼자 고른 숫자가 나오면 금화가 쏟아진다 (2·3위도 작게). 세 번째 혼자 숫자까지만 열고, 남은 세금 숫자를 연다.
// 서버는 단계가 바뀔 때만 계산하고, 이 화면은 2.5초마다 읽는다 (REFRESH_MS). 연출은 모두 이 화면 안에서 (framer-motion + Web Audio 효과음).
import { useCallback, useEffect, useMemo, useRef, useState } from 'react';

import { useHistory } from 'react-router-dom';

import { AnimatePresence, motion } from 'framer-motion';
import { createPortal } from 'react-dom';

import { apiRequestGet, apiRequestPost } from 'mastodon/api';
import { GameIcon } from 'mastodon/components/game_icons';

import { sendCommand } from './board';
import { useStageLayout } from './lobby';
import { createStageAudio } from './stage_audio';

// ── 화면 데이터 ──
interface GPlayer {
  seat: number;
  name: string;
  account_id: string;
  avatar?: string | null;
  acct?: string | null;
  score: number;
  submitted: boolean;
}

interface GResult {
  round: number;
  picks: Record<string, number>;
  counts: Record<string, number>;
  ranks: { seat: number; number: number; points: number }[];
  tax: { seat: number; number: number }[];
  taxed_numbers: number[];
  absent: number[];
}

interface GView {
  phase: 'pick' | 'reveal' | 'finished' | string;
  status: string;
  round: number;
  rounds: number;
  max_number: number;
  deadline_at: string | null;
  now: string;
  me: number | null;
  spectator: boolean;
  spectator_staff: boolean;
  goblin_name: string;
  reveal_seconds: number;
  points: number[];
  tax_points: number;
  players: GPlayer[];
  my_pick: number | null;
  submitted_count: number;
  reveal: GResult | null;
  winner_seats: number[] | null;
  commands: Record<string, string>;
}

export interface GoldChat { id: string; mine: boolean; name: string; acct: string; avatar: string; text: string; team: string | null }

const REFRESH_MS = 2_500;
const SOUND_KEY = 'ssm:gg-sound';
// 배경 음악: 파일을 `public/sounds/greengotts_bgm.mp3` 로 넣으면 자동으로 재생된다 (없으면 조용히 건너뜀). 음량은 BGM_VOLUME
const BGM_URL = '/sounds/greengotts_bgm.mp3';
const BGM_VOLUME = 0.3;
let bgmMissing = false;

// ── 효과음 (Web Audio, 소리 끄기 버튼을 따른다) ──
const { soundOn, tone, noise } = createStageAudio(SOUND_KEY);
const sfx = {
  // 금고 문이 삐걱 열린다
  door: (at = 0) => { noise(at, 0.5, 0.12, 700, 'bandpass'); tone(90, at, 0.5, { type: 'triangle', volume: 0.08, to: 150 }); },
  tick: (at = 0) => { tone(900, at, 0.04, { type: 'square', volume: 0.03 }); },
  // 문을 쾅 닫는다
  slam: (at = 0) => { tone(70, at, 0.35, { type: 'triangle', volume: 0.5, to: 35 }); noise(at, 0.14, 0.5, 500); },
  // 고블린의 "흥"
  hmph: (at = 0) => { tone(170, at, 0.35, { type: 'sawtooth', volume: 0.06, to: 105 }); },
  // 세금
  tax: (at = 0) => { tone(220, at, 0.4, { type: 'square', volume: 0.06, to: 90 }); tone(165, at + 0.12, 0.4, { type: 'square', volume: 0.05, to: 70 }); },
  // 금화 쨍그랑
  clink: (at = 0) => { tone(2300 + (Math.random() * 900), at, 0.14, { type: 'triangle', volume: 0.05 }); tone(3300 + (Math.random() * 700), at + 0.03, 0.1, { type: 'sine', volume: 0.03 }); },
  coins: (at = 0, count = 14) => { for (let index = 0; index < count; index += 1) sfx.clink(at + (index * 0.06) + (Math.random() * 0.03)); },
  pick: (at = 0) => { tone(660, at, 0.1, { volume: 0.1 }); tone(990, at + 0.07, 0.14, { volume: 0.08 }); },
  stamp: (at = 0) => { tone(110, at, 0.3, { type: 'triangle', volume: 0.4, to: 45 }); noise(at, 0.1, 0.35, 700); },
  fanfare: (at = 0) => { [523, 659, 784, 1047, 1319].forEach((freq, index) => { tone(freq, at + (index * 0.13), 0.9, { type: 'triangle', volume: 0.14 }); }); },
  sad: (at = 0) => { [392, 330, 262].forEach((freq, index) => { tone(freq, at + (index * 0.22), 0.6, { type: 'triangle', volume: 0.1 }); }); },
  next: (at = 0) => { tone(520, at, 0.1, { type: 'triangle', volume: 0.08 }); tone(780, at + 0.09, 0.16, { type: 'triangle', volume: 0.08 }); },
};

const pad = (value: number) => String(value).padStart(2, '0');
const mmss = (ms: number) => {
  const seconds = Math.max(0, Math.floor(ms / 1000));
  return `${pad(Math.floor(seconds / 60))}:${pad(seconds % 60)}`;
};

// 서버 시계 기준으로 남은 시간 (내 컴퓨터 시계가 달라도 같게 센다)
const useRemaining = (view: GView | null) => {
  const offset = useMemo(() => (view ? Date.parse(view.now) - Date.now() : 0), [view]);
  const [now, setNow] = useState(() => Date.now());
  useEffect(() => {
    const timer = window.setInterval(() => { setNow(Date.now()); }, 500);
    return () => { window.clearInterval(timer); };
  }, []);
  return view?.deadline_at ? Date.parse(view.deadline_at) - (now + offset) : 0;
};

// 아바타 한 칸
const Face: React.FC<{ player: GPlayer; me?: boolean; size?: number }> = ({ player, me = false, size = 30 }) => (
  <span className={['gg-face', me && 'is-me'].filter(Boolean).join(' ')} style={{ width: size, height: size }}>
    {player.avatar ? <img src={player.avatar} alt='' /> : <b>{player.name.slice(0, 1)}</b>}
  </span>
);

// ── 고블린 (SVG): 기분에 따라 표정과 몸짓이 바뀐다 ──
type Mood = 'idle' | 'shake' | 'happy';
const Goblin: React.FC<{ mood: Mood; size?: number }> = ({ mood, size = 96 }) => (
  <motion.span
    className={`gg-goblin gg-goblin--${mood}`}
    style={{ width: size, height: size }}
    animate={mood === 'shake' ? { rotate: [0, -16, 16, -12, 12, -6, 0] } : mood === 'happy' ? { y: [0, -10, 0, -6, 0], scale: [1, 1.08, 1] } : { rotate: 0, y: 0 }}
    transition={{ duration: mood === 'idle' ? 0.2 : 0.9 }}
  >
    <svg viewBox='0 0 120 120' aria-hidden>
      <path d='M30 54 L3 32 L8 70 L33 78 Z' fill='#78a35a' />
      <path d='M90 54 L117 32 L112 70 L87 78 Z' fill='#78a35a' />
      <path d='M28 56 L10 42 L13 66 L30 72 Z' fill='#e9a7a0' />
      <path d='M92 56 L110 42 L107 66 L90 72 Z' fill='#e9a7a0' />
      <ellipse cx='60' cy='64' rx='33' ry='35' fill='#8cb868' />
      <path d='M30 98 Q60 128 90 98 L96 120 L24 120 Z' fill='#1c1a22' />
      <path d='M48 98 L60 108 L72 98 L66 118 L54 118 Z' fill='#d9a93a' />
      <ellipse cx='46' cy='56' rx='9' ry='8' fill='#fffbe8' />
      <ellipse cx='74' cy='56' rx='9' ry='8' fill='#fffbe8' />
      <circle cx={mood === 'shake' ? 44 : 47} cy='57' r='3.6' fill='#2a1b05' />
      <circle cx={mood === 'shake' ? 72 : 73} cy='57' r='3.6' fill='#2a1b05' />
      <circle cx='74' cy='56' r='13' fill='none' stroke='#d9a93a' strokeWidth='2' />
      <path d={mood === 'happy' ? 'M36 44 Q46 38 55 44 M65 44 Q74 38 84 44' : 'M36 40 L55 46 M84 40 L65 46'} stroke='#3a5a22' strokeWidth='3.5' strokeLinecap='round' fill='none' />
      <path d='M60 58 Q50 78 60 84 Q70 78 60 58 Z' fill='#76a255' />
      <circle cx='56' cy='80' r='1.8' fill='#3a5a22' />
      <circle cx='64' cy='80' r='1.8' fill='#3a5a22' />
      {mood === 'happy' ? (
        <>
          <path d='M40 90 Q60 112 80 90 Z' fill='#33150f' />
          <path d='M46 91 L50 98 L54 91 M58 92 L62 100 L66 92 M70 91 L74 97 L78 90' stroke='#fffbe8' strokeWidth='3' fill='none' strokeLinejoin='round' />
        </>
      ) : mood === 'shake' ? (
        <path d='M42 96 Q60 88 78 96' stroke='#33150f' strokeWidth='4' strokeLinecap='round' fill='none' />
      ) : (
        <path d='M44 92 Q60 100 76 92' stroke='#33150f' strokeWidth='4' strokeLinecap='round' fill='none' />
      )}
    </svg>
  </motion.span>
);

// 금화 쏟아지기
const CoinShower: React.FC<{ count: number; big?: boolean }> = ({ count, big = false }) => (
  <span className={big ? 'gg-coins is-big' : 'gg-coins'} aria-hidden>
    {Array.from({ length: count }, (_, index) => {
      const spread = (((index * 53) % 100) / 100) - 0.5;
      return (
        <motion.i
          // eslint-disable-next-line react/no-array-index-key
          key={index}
          initial={{ opacity: 0, x: 0, y: -30, scale: 0.6, rotate: 0 }}
          animate={{ opacity: [0, 1, 1, 0], x: spread * (big ? 220 : 90), y: [-30, (big ? 120 : 70) + ((index * 29) % 50)], scale: [0.6, 1, 1], rotate: (index % 2 ? 1 : -1) * 360 }}
          transition={{ delay: (index % 12) * 0.05, duration: big ? 1.6 : 1.1, ease: 'easeIn' }}
        >
          🪙
        </motion.i>
      );
    })}
  </span>
);

// ── 금고 문 ──
type DoorState = 'closed' | 'open' | 'slammed';
const Door: React.FC<{
  n: number;
  state: DoorState;
  people?: GPlayer[];
  kind?: 'empty' | 'unique' | 'crowd';
  points?: number | null;
  taxed?: boolean;
  taxPoints?: number;
  me?: number | null;
  selected?: boolean;
  mine?: boolean;
  disabled?: boolean;
  onClick?: () => void;
}> = ({ n, state, people = [], kind, points, taxed, taxPoints = 1, me, selected, mine, disabled, onClick }) => {
  const open = state === 'open';
  const classes = ['gg-door', state !== 'closed' && `is-${state}`, kind && `is-${kind}`, selected && 'is-selected', mine && 'is-mine', onClick && !disabled && 'is-clickable'].filter(Boolean).join(' ');
  return (
    <motion.button
      type='button'
      className={classes}
      disabled={!onClick || disabled}
      onClick={onClick}
      animate={state === 'slammed' && kind === 'crowd' ? { x: [0, -5, 5, -3, 3, 0], scale: [1, 1.07, 1] } : { x: 0, scale: selected ? 1.06 : 1 }}
      transition={{ duration: 0.35 }}
      whileHover={onClick && !disabled ? { y: -3 } : undefined}
    >
      <span className='gg-door__inside'>
        {kind === 'unique' && <em className='gg-door__pile'>🪙</em>}
        {people.length > 0 && (
          <span className='gg-door__people'>
            {people.slice(0, 3).map((person) => <Face key={person.seat} player={person} me={person.seat === me} size={24} />)}
            {people.length > 3 && <small>+{people.length - 3}</small>}
          </span>
        )}
      </span>
      <motion.span className='gg-door__panel' initial={false} animate={{ rotateY: open ? -112 : 0 }} transition={open ? { type: 'spring', stiffness: 70, damping: 13 } : { duration: 0.16, ease: 'easeIn' }}>
        <b>{n}</b>
        {state === 'slammed' && kind === 'crowd' ? <i className='gg-door__x'>×{people.length}</i> : <i className='gg-door__lock' />}
      </motion.span>
      {points != null && <motion.span className='gg-door__points' initial={{ opacity: 0, y: 6, scale: 0.4 }} animate={{ opacity: 1, y: -8, scale: 1 }} transition={{ delay: 0.5, type: 'spring' }}>+{points}</motion.span>}
      {taxed && state === 'slammed' && <motion.span className='gg-door__tax' initial={{ opacity: 0, scale: 2.4, rotate: -20 }} animate={{ opacity: 1, scale: 1, rotate: -8 }} transition={{ type: 'spring', stiffness: 220, damping: 12 }}>세금 −{taxPoints}</motion.span>}
      {mine && <span className='gg-door__mine'>내 입찰</span>}
    </motion.button>
  );
};

// ── 금고 공개: 숫자 순서대로 문이 열린다 ──
interface RevealEvent { n: number; kind: 'empty' | 'unique' | 'crowd' | 'tax'; seats: number[]; ms: number }

const buildEvents = (result: GResult, max: number): RevealEvent[] => {
  const events: RevealEvent[] = [];
  let uniques = 0;
  let last = 0;
  for (let n = 1; n <= max; n += 1) {
    const count = result.counts[String(n)] ?? 0;
    const seats = Object.entries(result.picks).filter(([, value]) => value === n).map(([seat]) => Number(seat));
    const kind = count === 0 ? 'empty' : count === 1 ? 'unique' : 'crowd';
    events.push({ n, kind, seats, ms: kind === 'empty' ? 180 : kind === 'crowd' ? 1500 : 1900 });
    last = n;
    if (kind === 'unique') {
      uniques += 1;
      if (uniques >= 3) break;
    }
  }
  // 세 번째 혼자 숫자 뒤에 있는 세금 숫자도 연다
  result.taxed_numbers.filter((n) => n > last).forEach((n) => {
    events.push({ n, kind: 'tax', seats: Object.entries(result.picks).filter(([, value]) => value === n).map(([seat]) => Number(seat)), ms: 1500 });
  });
  return events;
};

const VaultReveal: React.FC<{ view: GView; result: GResult; budgetMs: number; onDone: () => void }> = ({ view, result, budgetMs, onDone }) => {
  // 2.5초마다 새로 읽어도 연출이 처음부터 다시 시작하지 않게, 라운드가 같으면 같은 연출을 쓰고 최신 값은 ref 로 들고 있는다
  const latest = useRef({ result, players: view.players });
  latest.current = { result, players: view.players };
  const events = useMemo(() => buildEvents(latest.current.result, view.max_number), [result.round, view.max_number]); // eslint-disable-line react-hooks/exhaustive-deps
  const [doors, setDoors] = useState<Record<number, DoorState>>({});
  const [mood, setMood] = useState<Mood>('idle');
  const [caption, setCaption] = useState('');
  const [shower, setShower] = useState<{ key: number; big: boolean } | null>(null);
  const [done, setDone] = useState(false);
  const byseat = useMemo(() => new Map(view.players.map((player) => [player.seat, player])), [view.players]);
  const doneRef = useRef(onDone);
  doneRef.current = onDone;

  useEffect(() => {
    const { result: current, players: roster } = latest.current;
    const names = new Map(roster.map((player) => [player.seat, player.name]));
    const total = events.reduce((sum, event) => sum + event.ms, 0);
    const scale = total > 0 ? Math.min(1, Math.max(0.35, budgetMs / total)) : 1;
    const timers: number[] = [];
    let at = 500;
    const later = (ms: number, fn: () => void) => { timers.push(window.setTimeout(fn, ms)); };
    events.forEach((event, index) => {
      const length = event.ms * scale;
      const people = event.seats.map((seat) => names.get(seat) ?? '').join(', ');
      later(at, () => {
        setDoors((current) => ({ ...current, [event.n]: 'open' }));
        if (event.kind === 'empty') {
          sfx.tick();
          setMood('idle');
          setCaption(`${event.n}번 금고 — 아무도 고르지 않았습니다`);
        } else if (event.kind === 'unique') {
          const rank = current.ranks.findIndex((each) => each.number === event.n);
          sfx.door();
          timers.push(window.setTimeout(() => {
            setMood('happy');
            setShower({ key: index, big: rank === 0 });
            sfx.coins(0, rank === 0 ? 22 : 10);
            setCaption(`${event.n}번 금고 — 혼자 골랐습니다! ${people}${rank >= 0 ? ` +${current.ranks[rank]?.points ?? 0}` : ''}`);
          }, 350 * scale));
        } else {
          sfx.door();
          setMood('shake');
          setCaption(`${event.n}번 금고 — ${event.seats.length}명이 몰렸습니다 (${people})`);
          timers.push(window.setTimeout(() => { sfx.hmph(); }, 200));
          timers.push(window.setTimeout(() => {
            setDoors((current) => ({ ...current, [event.n]: 'slammed' }));
            sfx.slam();
            if (current.taxed_numbers.includes(event.n)) timers.push(window.setTimeout(() => { sfx.tax(); }, 220));
          }, length * 0.62));
        }
      });
      at += length;
    });
    later(at + 300, () => {
      setMood('idle');
      setCaption(current.ranks.length > 0 ? '' : '혼자 고른 숫자가 없어 아무도 금화를 받지 못했습니다');
      setDone(true);
      doneRef.current();
    });
    return () => { timers.forEach((timer) => { window.clearTimeout(timer); }); };
  }, [events, budgetMs]);

  return (
    <div className='gg-reveal'>
      <div className='gg-reveal__goblin'>
        <Goblin mood={mood} size={88} />
        <AnimatePresence>{shower && <CoinShower key={shower.key} count={shower.big ? 34 : 14} big={shower.big} />}</AnimatePresence>
      </div>
      <p className='gg-reveal__caption'>{caption || ' '}</p>
      <div className='gg-vault'>
        {Array.from({ length: view.max_number }, (_, index) => {
          const n = index + 1;
          const event = events.find((each) => each.n === n);
          const kind = event ? (event.kind === 'tax' ? 'crowd' : event.kind) : undefined;
          const rank = result.ranks.find((each) => each.number === n);
          return (
            <Door
              key={n}
              n={n}
              state={doors[n] ?? 'closed'}
              kind={doors[n] ? kind : undefined}
              people={event && doors[n] ? event.seats.map((seat) => byseat.get(seat)).filter((person): person is GPlayer => Boolean(person)) : []}
              points={doors[n] && rank ? rank.points : null}
              taxed={result.taxed_numbers.includes(n)}
              taxPoints={view.tax_points}
              me={view.me}
              disabled
            />
          );
        })}
      </div>
      {done && (
        <motion.ul className='gg-summary' initial={{ opacity: 0, y: 10 }} animate={{ opacity: 1, y: 0 }}>
          {result.ranks.map((rank, index) => <li key={`r${rank.seat}`} className='is-gain'>{index + 1}위 <b>{byseat.get(rank.seat)?.name}</b> ({rank.number}번) +{rank.points}</li>)}
          {result.tax.length > 0 && <li className='is-tax'>고블린의 세금: {result.tax.map((entry) => byseat.get(entry.seat)?.name).join(', ')} −{view.tax_points}</li>}
          {result.absent.length > 0 && <li className='is-muted'>못 낸 사람: {result.absent.map((seat) => byseat.get(seat)?.name).join(', ')}</li>}
        </motion.ul>
      )}
    </div>
  );
};

// ── 오프닝: 금고 문 + 고블린의 규칙 안내 ──
const Opening: React.FC<{ view: GView; onDone: () => void }> = ({ view, onDone }) => {
  const [step, setStep] = useState<'door' | 'rules'>('door');
  useEffect(() => {
    if (step !== 'door') return undefined;
    sfx.door(0.4);
    sfx.coins(1.6, 10);
    const timer = window.setTimeout(() => { setStep('rules'); }, 3300);
    return () => { window.clearTimeout(timer); };
  }, [step]);
  return (
    <motion.div className='gg-opening' initial={{ opacity: 0 }} animate={{ opacity: 1 }} exit={{ opacity: 0, transition: { duration: 0.8 } }}>
      <AnimatePresence mode='wait'>
        {step === 'door' ? (
          <motion.div key='door' className='gg-bigdoor' exit={{ opacity: 0 }}>
            <motion.span className='gg-bigdoor__light' initial={{ opacity: 0, scale: 0.3 }} animate={{ opacity: [0, 1, 0.85], scale: [0.3, 1.2, 1.5] }} transition={{ delay: 0.9, duration: 2.2 }} />
            <motion.span className='gg-bigdoor__wheel' initial={{ rotate: 0, x: 0 }} animate={{ rotate: [0, 0, 540], x: [0, 0, '-70%'] }} transition={{ duration: 2.4, times: [0, 0.2, 1], ease: 'easeInOut' }}>
              <i /><i /><i /><i />
            </motion.span>
            <motion.h1 initial={{ opacity: 0, y: 14 }} animate={{ opacity: 1, y: 0 }} transition={{ delay: 0.3, duration: 1 }}>그린고츠 마법 은행</motion.h1>
          </motion.div>
        ) : (
          <motion.div key='rules' className='gg-intro' initial={{ opacity: 0, scale: 0.92 }} animate={{ opacity: 1, scale: 1 }}>
            <Goblin mood='happy' size={120} />
            <h2>{view.goblin_name}</h2>
            <p>혼자 부른 <b>가장 작은 숫자</b>에게만 금화를 드립니다.<br />남들과 겹치지 않는 작은 숫자를 골라 보세요!</p>
            <ul>
              <li>1위 <b>+{view.points[0]}</b> · 2위 <b>+{view.points[1]}</b> · 3위 <b>+{view.points[2]}</b> (혼자 고른 숫자 중 작은 순서)</li>
              <li>가장 많은 사람이 고른 숫자는 <b>세금 −{view.tax_points}</b></li>
              <li>1 ~ {view.max_number} 중 하나, 총 {view.rounds}라운드</li>
            </ul>
            <button type='button' className='gg-button' onClick={onDone}>시작하기</button>
          </motion.div>
        )}
      </AnimatePresence>
    </motion.div>
  );
};

// ── 끝: 순위 ──
const EndScreen: React.FC<{ view: GView; onLeave: () => void }> = ({ view, onLeave }) => {
  const ordered = [...view.players].sort((a, b) => b.score - a.score || a.seat - b.seat);
  const winners = view.winner_seats ?? [];
  const iWon = view.me !== null && winners.includes(view.me);
  const myRank = view.me === null ? null : ordered.findIndex((player) => player.seat === view.me) + 1;
  useEffect(() => {
    if (iWon) { sfx.fanfare(0.3); sfx.coins(0.6, 24); } else { sfx.sad(0.3); }
  }, [iWon]);
  return (
    <motion.div className='gg-end' initial={{ opacity: 0 }} animate={{ opacity: 1 }}>
      <div className='gg-end__goblin'>
        <Goblin mood={iWon ? 'happy' : 'idle'} size={104} />
        <CoinShower count={40} big />
      </div>
      <motion.h1 initial={{ opacity: 0, y: 20 }} animate={{ opacity: 1, y: 0 }} transition={{ delay: 0.4 }}>
        {winners.length > 1 ? '공동 우승!' : '우승!'} {ordered.filter((player) => winners.includes(player.seat)).map((player) => player.name).join(', ')}
      </motion.h1>
      {myRank !== null && <p className={iWon ? 'gg-end__me is-win' : 'gg-end__me'}>{iWon ? '금고를 털었습니다! 우승입니다' : `${myRank}위로 끝났습니다`}</p>}
      <ol className='gg-end__rank'>
        {ordered.map((player, index) => (
          <motion.li key={player.seat} className={winners.includes(player.seat) ? 'is-winner' : undefined} initial={{ opacity: 0, x: -18 }} animate={{ opacity: 1, x: 0 }} transition={{ delay: 0.9 + (index * 0.07) }}>
            <i>{index + 1}</i>
            <Face player={player} me={player.seat === view.me} size={30} />
            <b>{player.name}</b>
            <em>{player.score}점</em>
          </motion.li>
        ))}
      </ol>
      <button type='button' className='gg-button' onClick={onLeave}>나가기</button>
    </motion.div>
  );
};

// ── 채팅 ──
const ChatDock: React.FC<{ sessionId: string; chat: GoldChat[]; canChat: boolean; onSent: () => void }> = ({ sessionId, chat, canChat, onSent }) => {
  const [text, setText] = useState('');
  const listRef = useRef<HTMLUListElement>(null);
  useEffect(() => { if (listRef.current) listRef.current.scrollTop = listRef.current.scrollHeight; }, [chat.length]);
  return (
    <section className='gg-chat'>
      <ul ref={listRef} className='gg-chat__list'>
        {chat.map((message) => (
          <li key={message.id} className={message.mine ? 'is-mine' : undefined}>
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
          apiRequestPost(`v1/system/sessions/${sessionId}/chat`, { text: value, channel: 'all' })
            .then(() => { onSent(); return true; })
            .catch(() => { onSent(); });
        }}
        >
          <input type='text' value={text} maxLength={200} placeholder='고블린 몰래 속삭이기…' onChange={(event) => { setText(event.target.value); }} />
          <button type='submit' className='gg-button gg-button--small' disabled={!text.trim()}>보내기</button>
        </form>
      )}
    </section>
  );
};

// ── 무대 ──
export const GreengottsStage: React.FC<{ sessionId: string; name: string; chat: GoldChat[]; staff: boolean; isPlayer: boolean; onChanged: () => void }> = ({ sessionId, name, chat, isPlayer, onChanged }) => {
  const history = useHistory();
  const [view, setView] = useState<GView | null>(null);
  const [busy, setBusy] = useState(false);
  const [intro, setIntro] = useState<'pending' | 'open' | 'done'>('pending');
  const [sel, setSel] = useState<number | null>(null);
  const [sound, setSound] = useState(soundOn);
  const [ended, setEnded] = useState(false);
  const [revealDone, setRevealDone] = useState(false);
  const left = useRemaining(view);
  const leftRef = useRef(0);
  leftRef.current = left;
  useStageLayout(true);

  // 배경 음악: 오프닝이 시작되면 반복 재생, 소리를 끄면 멈추고, 방을 나가면 끝 (파일이 없으면 아무 일도 없다)
  const bgm = useRef<HTMLAudioElement | null>(null);
  const bgmOn = sound && intro !== 'pending' && !bgmMissing;
  useEffect(() => {
    if (!bgmOn) {
      bgm.current?.pause();
      return;
    }
    if (!bgm.current) {
      bgm.current = new Audio(BGM_URL);
      bgm.current.loop = true;
      bgm.current.volume = BGM_VOLUME;
      bgm.current.onerror = () => { bgmMissing = true; bgm.current = null; };
    }
    bgm.current.play().catch(() => {
      // 자동 재생이 막히면 화면을 한 번 누를 때 시작
      const resume = () => { void bgm.current?.play().catch(() => undefined); window.removeEventListener('pointerdown', resume); };
      window.addEventListener('pointerdown', resume);
    });
  }, [bgmOn]);
  useEffect(() => () => {
    bgm.current?.pause();
    bgm.current = null;
  }, []);

  const load = useCallback(() => {
    apiRequestGet<{ view: GView | null }>(`v1/system/sessions/${sessionId}/view`)
      .then((response) => { if (response.view) setView(response.view); return response; })
      .catch(() => undefined);
  }, [sessionId]);
  useEffect(() => {
    load();
    const timer = window.setInterval(load, REFRESH_MS);
    return () => { window.clearInterval(timer); };
  }, [load]);

  // 처음 한 번: 오프닝 (금고 문 + 규칙). 끝난 판은 건너뛴다
  const introChecked = useRef(false);
  useEffect(() => {
    if (!view || introChecked.current) return;
    introChecked.current = true;
    let seen = false;
    try { seen = window.sessionStorage.getItem(`ssm:gg-intro:${sessionId}`) === '1'; } catch { seen = false; }
    setIntro(seen || view.status === 'finished' ? 'done' : 'open');
  }, [view, sessionId]);
  const finishIntro = useCallback(() => {
    setIntro('done');
    try { window.sessionStorage.setItem(`ssm:gg-intro:${sessionId}`, '1'); } catch { /* 이번만 */ }
  }, [sessionId]);

  // 라운드·단계가 바뀌면 고른 것을 비우고 효과음
  const phaseKey = view ? `${view.phase}-${view.round}` : '';
  const lastPhase = useRef('');
  useEffect(() => {
    if (!phaseKey || lastPhase.current === phaseKey) return;
    if (lastPhase.current) {
      setSel(null);
      setRevealDone(false);
      if (view?.phase === 'pick') sfx.next();
    }
    lastPhase.current = phaseKey;
  }, [phaseKey, view?.phase]);

  // 끝나면 잠깐 뒤 순위 화면. 이미 끝난 판을 열면 바로
  const wasActive = useRef(false);
  useEffect(() => {
    if (view?.status === 'active') wasActive.current = true;
    if (view?.status === 'finished') {
      const timer = window.setTimeout(() => { setEnded(true); }, wasActive.current ? 3_000 : 300);
      return () => { window.clearTimeout(timer); };
    }
    return undefined;
  }, [view?.status]);

  const send = useCallback((command: string, args?: string) => {
    setBusy(true);
    sendCommand({ session_id: sessionId, command, ...(args ? { args } : {}) })
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
  const onRevealDone = useCallback(() => { setRevealDone(true); }, []);

  // 공개 연출은 남은 시간 안에 끝나게 맞춘다 (처음 그릴 때의 남은 시간 기준)
  const revealBudget = useRef(10_000);
  const revealKey = view?.reveal ? `${view.round}-${view.phase}` : '';
  const budgetKey = useRef('');
  if (revealKey && budgetKey.current !== revealKey) {
    budgetKey.current = revealKey;
    revealBudget.current = Math.max(4_000, (leftRef.current > 0 ? leftRef.current : (view?.reveal_seconds ?? 16) * 1000) - 2_500);
  }

  if (!view) return createPortal(<div className='game-stage gg-stage' role='region' aria-label={name} />, document.body);

  const me = view.me;
  const playing = view.status === 'active' && isPlayer && me !== null;
  const reveal = view.phase === 'reveal' ? view.reveal : null;
  // 공개 연출이 끝나기 전에는 이번 라운드의 점수 변화를 아직 반영하지 않은 점수로 보여 준다 (결과를 미리 알려 주지 않게)
  const gain = (seat: number) => {
    if (!reveal) return 0;
    const plus = reveal.ranks.filter((rank) => rank.seat === seat).reduce((sum, rank) => sum + rank.points, 0);
    const minus = reveal.tax.some((entry) => entry.seat === seat) ? view.tax_points : 0;
    return plus - minus;
  };
  const shownScore = (player: GPlayer) => (reveal && !revealDone ? player.score - gain(player.seat) : player.score);
  const board = [...view.players].sort((a, b) => shownScore(b) - shownScore(a) || a.seat - b.seat);
  const myPick = view.my_pick;
  const goblinLine = {
    pick: playing ? (myPick ? `${myPick}번 금고에 입찰했습니다. 마음이 바뀌면 다시 고르세요.` : '혼자 부를 가장 작은 숫자는 무엇일까요?') : '입찰이 진행 중입니다…',
    reveal: '금고를 엽니다…',
    finished: '거래가 끝났습니다.',
  }[view.phase] ?? '';

  return createPortal(
    <div className={['game-stage gg-stage', intro === 'open' && 'is-intro'].filter(Boolean).join(' ')} role='region' aria-label={name}>
      <div className='gg-backdrop' aria-hidden><i className='gg-glow gg-glow--a' /><i className='gg-glow gg-glow--b' /></div>

      <header className='gg-top'>
        <div className='gg-rounds' title={`라운드 ${Math.min(view.round, view.rounds)} / ${view.rounds}`}>
          <span>라운드 <b>{Math.min(view.round, view.rounds)}</b> / {view.rounds}</span>
          {view.rounds <= 15 && (
            <ol>
              {Array.from({ length: view.rounds }, (_, index) => (
                // eslint-disable-next-line react/no-array-index-key
                <li key={index} className={index + 1 < view.round || view.status === 'finished' ? 'is-past' : index + 1 === view.round ? 'is-now' : undefined} />
              ))}
            </ol>
          )}
        </div>
        {view.status === 'active' && view.deadline_at && view.phase === 'pick' && <span className={left < 7_000 ? 'gg-timer is-low' : 'gg-timer'}><GameIcon name='hourglass' /> {mmss(left)}</span>}
        <button type='button' className={sound ? 'gg-sound' : 'gg-sound is-off'} onClick={toggleSound} aria-pressed={sound}>{sound ? '♪' : '×'}</button>
        <button type='button' className='gg-exit' onClick={() => { history.push('/system/group'); }}>나가기</button>
      </header>

      <div className='gg-main'>
        <section className='gg-board'>
          {!reveal && (
            <>
              <div className='gg-talk'>
                <Goblin mood='idle' size={84} />
                <p>{goblinLine}</p>
              </div>
              <div className='gg-vault'>
                {Array.from({ length: view.max_number }, (_, index) => {
                  const n = index + 1;
                  return (
                    <Door
                      key={n}
                      n={n}
                      state='closed'
                      selected={sel === n}
                      mine={myPick === n}
                      disabled={!playing || busy || view.phase !== 'pick'}
                      onClick={() => { sfx.pick(); setSel(n); }}
                    />
                  );
                })}
              </div>
              <div className='gg-actions'>
                {playing && view.phase === 'pick' && (
                  <button type='button' className='gg-button' disabled={busy || sel === null || sel === myPick} onClick={() => { if (sel !== null) { sfx.stamp(); send(view.commands.pick ?? '입찰', String(sel)); } }}>
                    {sel === null ? '금고를 고르세요' : myPick ? `${sel}번 금고로 바꾸기` : `${sel}번 금고에 입찰하기`}
                  </button>
                )}
                {view.phase === 'pick' && <small>{view.submitted_count} / {view.players.length}명 입찰 · 모두 내면 바로 공개됩니다</small>}
              </div>
            </>
          )}
          {reveal && <VaultReveal key={`reveal-${view.round}`} view={view} result={reveal} budgetMs={revealBudget.current} onDone={onRevealDone} />}
        </section>

        <aside className='gg-side'>
          <h3 className='gg-side__title'>금화 순위 ({view.players.length}명)</h3>
          <ul className='gg-people'>
            {board.map((player) => {
              const delta = reveal && revealDone ? gain(player.seat) : 0;
              return (
                <motion.li key={player.seat} layout transition={{ type: 'spring', stiffness: 280, damping: 28 }} className={['gg-person', player.seat === me && 'is-me', view.phase === 'pick' && player.submitted && 'is-in'].filter(Boolean).join(' ')}>
                  <Face player={player} me={player.seat === me} size={32} />
                  <span className='gg-person__name'>
                    <b>{player.name}</b>
                    {view.phase === 'pick' && <small>{player.submitted ? '입찰 완료' : '고민 중…'}</small>}
                  </span>
                  <motion.span key={shownScore(player)} className='gg-person__score' initial={{ scale: 1.5, color: '#fff' }} animate={{ scale: 1 }}>{shownScore(player)}</motion.span>
                  {delta !== 0 && <motion.i className={delta > 0 ? 'gg-person__delta is-gain' : 'gg-person__delta is-loss'} initial={{ opacity: 0, y: 8 }} animate={{ opacity: 1, y: 0 }}>{delta > 0 ? `+${delta}` : delta}</motion.i>}
                </motion.li>
              );
            })}
          </ul>
        </aside>
      </div>

      <ChatDock sessionId={sessionId} chat={chat} canChat={view.status !== 'active' || isPlayer} onSent={() => { load(); onChanged(); }} />

      <AnimatePresence>
        {intro === 'open' && <Opening key='opening' view={view} onDone={finishIntro} />}
      </AnimatePresence>
      {view.status === 'finished' && intro === 'done' && ended && <EndScreen view={view} onLeave={() => { history.push('/system/group'); }} />}
    </div>,
    document.body,
  );
};
