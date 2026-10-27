// 덤블도어의 군대 게임방 (웹 전용 이벤트, 아발론형): 필요의 방에 모인 DA 대원들 사이에 엄브리지의 첩자가 숨어 있다.
//   오프닝: 필요의 방 문이 열리고 → 내 역할 카드(뒤집히며 공개)
//   대원 고르기: 리더가 대원 카드를 테이블 위로 끌어다 놓는다 (눌러서 고를 수도 있다) → 제안
//   투표: 전원 찬성/반대 → 모두가 동시에 뒤집히며 공개 → 통과/부결 도장
//   임무: 대원이 성공(은빛)/방해(분홍색 고양이 접시, 첩자만) 카드를 몰래 낸다 → 카드가 한 장씩 뒤집히며 공개 (누가 냈는지는 비밀)
//   마지막 반전: 임무 3개를 성공하면 첩자들이 해리를 지목한다. 첩자가 이기면 엄브리지의 "에헴, 에헴"
// 서버는 단계가 바뀔 때만 계산하고, 이 화면은 2.5초마다 읽는다 (REFRESH_MS). 연출은 모두 이 화면 안에서 (framer-motion + Web Audio 효과음).
import { useCallback, useEffect, useMemo, useRef, useState } from 'react';

import { useHistory } from 'react-router-dom';

import { AnimatePresence, motion } from 'framer-motion';
import { createPortal } from 'react-dom';

import { apiRequestGet, apiRequestPost } from 'mastodon/api';
import { GameIcon } from 'mastodon/components/game_icons';

import { sendCommand } from './board';
import { useStageLayout } from './lobby';

// ── 화면 데이터 ──
interface APlayer {
  seat: number;
  name: string;
  account_id: string;
  avatar?: string | null;
  acct?: string | null;
  role: string | null;
  leader: boolean;
  on_team: boolean;
  voted: boolean;
  vote: 'yes' | 'no' | null;
  card_in: boolean | null;
}

interface AResult {
  no: number;
  team: number[];
  leader: number;
  size: number;
  need: number;
  sabotage: number;
  success: boolean;
  cards: ('success' | 'sabotage')[];
  rejects: number;
}

interface AView {
  phase: 'team' | 'vote' | 'vote_result' | 'mission' | 'result' | 'assassin' | 'finished' | string;
  status: string;
  mission: number;
  missions: number;
  rejects: number;
  reject_limit: number;
  deadline_at: string | null;
  now: string;
  winner: 'da' | 'spy' | null;
  reason: string | null;
  me: number | null;
  spectator: boolean;
  spectator_staff: boolean;
  leader: number | null;
  size_needed: number;
  sabotage_needed: number;
  team: number[];
  da_name: string;
  spy_name: string;
  spy_count: number;
  role_names: Record<string, string>;
  players: APlayer[];
  my_role: { key: string; name: string; spy: boolean; how: string } | null;
  my_vote: 'yes' | 'no' | null;
  my_card: 'success' | 'sabotage' | null;
  can_sabotage: boolean;
  on_team: boolean;
  cards_in: number;
  voted_count: number;
  vote_result: { yes: number[]; no: number[]; passed: boolean; mission: number; leader: number; team: number[] } | null;
  results: AResult[];
  assassin: { target: number | null; hit: boolean | null; guesses: Record<string, number>; harry: number | null; guessed: number; spies: number } | null;
  commands: Record<string, string>;
  roles_final: Record<string, string> | null;
}

export interface ArmyChat { id: string; mine: boolean; name: string; acct: string; avatar: string; text: string; team: string | null }

const REFRESH_MS = 2_500;
const SOUND_KEY = 'ssm:da-sound';
// 배경 음악: 파일을 `public/sounds/dumbledores_army_bgm.mp3` 로 넣으면 자동으로 재생된다 (없으면 조용히 건너뜀). 음량은 BGM_VOLUME
const BGM_URL = '/sounds/dumbledores_army_bgm.mp3';
const BGM_VOLUME = 0.35;
let bgmMissing = false;

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
  gain.gain.exponentialRampToValueAtTime(options.volume ?? 0.2, start + 0.02);
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
  // 문이 스르륵 열린다 (필요의 방)
  door: (at = 0) => { noise(at, 1.6, 0.16, 500, 'bandpass'); tone(70, at, 1.6, { type: 'triangle', volume: 0.09, to: 110 }); },
  // 카드가 뒤집힌다
  flip: (at = 0) => { noise(at, 0.12, 0.35, 3000); tone(520, at + 0.02, 0.08, { type: 'triangle', volume: 0.08, to: 300 }); },
  // 카드를 놓는다 / 고른다
  place: (at = 0) => { tone(300, at, 0.09, { type: 'triangle', volume: 0.12, to: 180 }); },
  pick: (at = 0) => { tone(660, at, 0.1, { volume: 0.1 }); tone(990, at + 0.07, 0.14, { volume: 0.08 }); },
  // 투표 도장
  stamp: (at = 0) => { tone(110, at, 0.3, { type: 'triangle', volume: 0.45, to: 45 }); noise(at, 0.1, 0.4, 700); },
  // 성공: 은빛 종소리
  chime: (at = 0) => { [784, 988, 1175, 1568].forEach((freq, index) => { tone(freq, at + (index * 0.09), 0.55, { type: 'triangle', volume: 0.1 }); }); },
  // 실패: 낮은 부저 + 가르랑
  buzz: (at = 0) => { tone(140, at, 0.55, { type: 'sawtooth', volume: 0.1, to: 70 }); tone(150, at + 0.05, 0.5, { type: 'square', volume: 0.05, to: 80 }); },
  yes: (at = 0) => { tone(880, at, 0.12, { volume: 0.08 }); },
  no: (at = 0) => { tone(220, at, 0.16, { type: 'triangle', volume: 0.1, to: 160 }); },
  fanfare: (at = 0) => { [523, 659, 784, 1047, 1319].forEach((freq, index) => { tone(freq, at + (index * 0.13), 0.9, { type: 'triangle', volume: 0.14 }); }); },
  // 엄브리지의 "에헴, 에헴"
  hem: (at = 0) => { [0, 0.45].forEach((offset) => { noise(at + offset, 0.28, 0.5, 900, 'bandpass'); tone(330, at + offset, 0.26, { type: 'sawtooth', volume: 0.07, to: 260 }); }); },
  wand: (at = 0) => { tone(1500, at, 0.5, { type: 'sine', volume: 0.07, to: 300 }); noise(at, 0.35, 0.18, 4000); },
  tick: (at = 0) => { tone(1000, at, 0.04, { type: 'square', volume: 0.04 }); },
};

const pad = (value: number) => String(value).padStart(2, '0');
const mmss = (ms: number) => {
  const seconds = Math.max(0, Math.floor(ms / 1000));
  return `${pad(Math.floor(seconds / 60))}:${pad(seconds % 60)}`;
};

// 서버 시계 기준으로 남은 시간 (내 컴퓨터 시계가 달라도 같게 센다)
const useRemaining = (view: AView | null) => {
  const offset = useMemo(() => (view ? Date.parse(view.now) - Date.now() : 0), [view]);
  const [now, setNow] = useState(() => Date.now());
  useEffect(() => {
    const timer = window.setInterval(() => { setNow(Date.now()); }, 500);
    return () => { window.clearInterval(timer); };
  }, []);
  return view?.deadline_at ? Date.parse(view.deadline_at) - (now + offset) : 0;
};

const ROLE_ICON: Record<string, string> = { harry: '⚡', ron: '🦁', da: '✦', spy: '🐱' };

// 반짝이 입자
const Sparks: React.FC<{ count: number; delay?: number; color?: string }> = ({ count, delay = 0, color = '#ffe08a' }) => (
  <span className='da-sparks' aria-hidden>
    {Array.from({ length: count }, (_, index) => {
      const angle = (index / count) * Math.PI * 2;
      const distance = 40 + ((index * 37) % 70);
      return (
        <motion.i
          // eslint-disable-next-line react/no-array-index-key
          key={index}
          style={{ background: color, boxShadow: `0 0 8px ${color}` }}
          initial={{ opacity: 0, x: 0, y: 0, scale: 0.4 }}
          animate={{ opacity: [0, 1, 0], x: Math.cos(angle) * distance, y: Math.sin(angle) * distance, scale: [0.4, 1.2, 0.3] }}
          transition={{ delay: delay + ((index % 6) * 0.04), duration: 1.1, ease: 'easeOut' }}
        />
      );
    })}
  </span>
);

// 아바타 한 칸 (고르기·끌기·표시 공용)
const Face: React.FC<{ player: APlayer; me: boolean; size?: number }> = ({ player, me, size = 44 }) => (
  <span className={['da-face', me && 'is-me'].filter(Boolean).join(' ')} style={{ width: size, height: size }}>
    {player.avatar ? <img src={player.avatar} alt='' /> : <b>{player.name.slice(0, 1)}</b>}
  </span>
);

// 카드 뒷/앞 (뒤집힘): 성공 = 은빛, 방해 = 분홍색 고양이 접시
const MissionCard: React.FC<{ kind: 'success' | 'sabotage'; faceUp: boolean; index?: number; delay?: number; onFlip?: (index: number) => void }> = ({ kind, faceUp, index = 0, delay = 0, onFlip }) => {
  // 다시 그려져도 타이머가 처음부터 다시 시작하지 않게 콜백은 ref 로 들고 있는다
  const flip = useRef(onFlip);
  flip.current = onFlip;
  useEffect(() => {
    if (!faceUp) return undefined;
    const timer = window.setTimeout(() => { flip.current?.(index); }, (delay + 0.25) * 1000);
    return () => { window.clearTimeout(timer); };
  }, [faceUp, delay, index]);
  return (
    <motion.span className='da-card' initial={{ rotateY: 0, y: 30, opacity: 0 }} animate={{ rotateY: faceUp ? 180 : 0, y: 0, opacity: 1 }} transition={{ delay, duration: 0.6, type: 'spring', stiffness: 90, damping: 14 }}>
      <span className='da-card__back'><GameIcon name='sparkle' /></span>
      <span className={`da-card__front da-card__front--${kind}`}>
        {kind === 'success' ? <><em>✨</em><small>성공</small></> : <><em>🐱</em><small>방해</small></>}
      </span>
    </motion.span>
  );
};

// ── 오프닝: 필요의 방 + 내 역할 카드 ──
const Opening: React.FC<{ view: AView; onDone: () => void }> = ({ view, onDone }) => {
  const [step, setStep] = useState<'door' | 'role'>(view.my_role ? 'door' : 'role');
  const [flipped, setFlipped] = useState(false);
  useEffect(() => {
    if (step !== 'door') return undefined;
    sfx.door(0.2);
    const timer = window.setTimeout(() => { setStep('role'); }, 3600);
    return () => { window.clearTimeout(timer); };
  }, [step]);
  const role = view.my_role;
  const spyNames = view.players.filter((player) => player.role === 'spy' && player.seat !== view.me).map((player) => player.name);
  const harryName = view.players.find((player) => player.role === 'harry')?.name;
  return (
    <motion.div className='da-opening' initial={{ opacity: 0 }} animate={{ opacity: 1 }} exit={{ opacity: 0, transition: { duration: 0.8 } }}>
      <AnimatePresence mode='wait'>
        {step === 'door' ? (
          <motion.div key='door' className='da-door' exit={{ opacity: 0 }}>
            <motion.span className='da-door__half da-door__half--l' initial={{ x: 0 }} animate={{ x: '-102%' }} transition={{ delay: 1.2, duration: 1.8, ease: 'easeInOut' }} />
            <motion.span className='da-door__half da-door__half--r' initial={{ x: 0 }} animate={{ x: '102%' }} transition={{ delay: 1.2, duration: 1.8, ease: 'easeInOut' }} />
            <motion.span className='da-door__light' initial={{ opacity: 0, scale: 0.4 }} animate={{ opacity: [0, 1, 0.8], scale: [0.4, 1.3, 1.6] }} transition={{ delay: 1.2, duration: 2.2 }} />
            <motion.h1 className='da-door__title' initial={{ opacity: 0, y: 14 }} animate={{ opacity: 1, y: 0 }} transition={{ delay: 0.3, duration: 1 }}>필요의 방</motion.h1>
            <motion.p className='da-door__sub' initial={{ opacity: 0 }} animate={{ opacity: 1 }} transition={{ delay: 2.4 }}>{view.da_name}</motion.p>
          </motion.div>
        ) : (
          <motion.div key='role' className='da-role' initial={{ opacity: 0, scale: 0.9 }} animate={{ opacity: 1, scale: 1 }}>
            {role ? (
              <>
                <p className='da-role__lead'>당신의 역할은</p>
                <motion.button
                  type='button'
                  className={['da-role__card', flipped && 'is-open', role.spy && 'is-spy'].filter(Boolean).join(' ')}
                  onClick={() => { if (!flipped) { setFlipped(true); sfx.flip(); (role.spy ? sfx.hem : sfx.wand)(0.3); } }}
                  animate={{ rotateY: flipped ? 180 : 0 }}
                  transition={{ duration: 0.7, type: 'spring', stiffness: 80, damping: 12 }}
                >
                  <span className='da-role__back'>카드를 눌러 확인하세요</span>
                  <span className='da-role__front'>
                    <em>{ROLE_ICON[role.key] ?? '✦'}</em>
                    <b>{role.name}</b>
                    <small>{role.spy ? view.spy_name : view.da_name}</small>
                  </span>
                </motion.button>
                {flipped && (
                  <motion.div className='da-role__info' initial={{ opacity: 0, y: 10 }} animate={{ opacity: 1, y: 0 }} transition={{ delay: 0.5 }}>
                    <p>{role.how}</p>
                    {spyNames.length > 0 && <p className='da-role__known'>{role.spy ? `${view.spy_name} 동료` : `${view.spy_name}`}: <b>{spyNames.join(', ')}</b></p>}
                    {role.key === 'ron' && harryName && <p className='da-role__known'>{view.role_names.harry}: <b>{harryName}</b></p>}
                    <button type='button' className='da-button' onClick={onDone}>시작하기</button>
                  </motion.div>
                )}
              </>
            ) : (
              <>
                <h2>관전 중입니다</h2>
                <p className='da-role__lead'>{view.spectator_staff ? '운영진은 모든 역할이 보입니다.' : '임무 진행과 투표 결과를 함께 지켜보세요.'}</p>
                <button type='button' className='da-button' onClick={onDone}>들어가기</button>
              </>
            )}
          </motion.div>
        )}
      </AnimatePresence>
    </motion.div>
  );
};

// ── 임무 기록 줄 (맨 위) ──
const Tracker: React.FC<{ view: AView }> = ({ view }) => (
  <div className='da-tracker'>
    <ol className='da-tracker__missions'>
      {Array.from({ length: view.missions }, (_, index) => {
        const result = view.results.find((each) => each.no === index + 1);
        const current = !result && view.mission === index + 1 && view.status === 'active';
        return (
          // eslint-disable-next-line react/no-array-index-key
          <motion.li key={index} className={['da-token', result && (result.success ? 'is-success' : 'is-fail'), current && 'is-current'].filter(Boolean).join(' ')} initial={false} animate={{ scale: result ? [1, 1.3, 1] : 1 }} title={result ? `임무 ${index + 1}: 방해 ${result.sabotage}장` : `임무 ${index + 1}`}>
            {result ? (result.success ? '✦' : '🐱') : index + 1}
          </motion.li>
        );
      })}
    </ol>
    <span className='da-tracker__rejects' title={`연속 부결 ${view.rejects} / ${view.reject_limit}`}>
      부결
      {Array.from({ length: view.reject_limit }, (_, index) => (
        // eslint-disable-next-line react/no-array-index-key
        <i key={index} className={index < view.rejects ? 'is-on' : undefined} />
      ))}
    </span>
  </div>
);

// ── 임무 결과 공개: 카드가 한 장씩 뒤집힌다 ──
const ResultReveal: React.FC<{ result: AResult; view: AView }> = ({ result, view }) => {
  const [shown, setShown] = useState(0);
  const total = result.cards.length;
  useEffect(() => {
    if (shown < total) return undefined;
    const timer = window.setTimeout(() => { (result.success ? sfx.chime : sfx.buzz)(); }, 500);
    return () => { window.clearTimeout(timer); };
  }, [shown, total, result.success]);
  const onFlip = useCallback((index: number) => {
    (result.cards[index] === 'sabotage' ? sfx.buzz : sfx.flip)();
    setShown((current) => Math.max(current, index + 1));
  }, [result]);
  const leader = view.players.find((player) => player.seat === result.leader);
  return (
    <motion.div className='da-reveal' initial={{ opacity: 0 }} animate={{ opacity: 1 }}>
      <h3>임무 {result.no} 결과</h3>
      <p className='da-reveal__lead'>{leader?.name} 리더 · 대원 {result.size}명{result.need > 1 ? ` · 방해 ${result.need}장 이상이면 실패` : ''}</p>
      <div className='da-reveal__cards'>
        {result.cards.map((card, index) => (
          // eslint-disable-next-line react/no-array-index-key
          <MissionCard key={index} kind={card} faceUp index={index} delay={0.8 + (index * 1.0)} onFlip={onFlip} />
        ))}
      </div>
      <AnimatePresence>
        {shown >= total && (
          <motion.div className={result.success ? 'da-stamp da-stamp--success' : 'da-stamp da-stamp--fail'} initial={{ scale: 3, opacity: 0, rotate: -12 }} animate={{ scale: 1, opacity: 1, rotate: -6 }} transition={{ type: 'spring', stiffness: 220, damping: 14 }}>
            <b>{result.success ? '임무 성공!' : '임무 실패…'}</b>
            <small>방해 {result.sabotage}장</small>
            {result.success && <Sparks count={18} color='#cfe9ff' />}
          </motion.div>
        )}
      </AnimatePresence>
    </motion.div>
  );
};

// ── 투표 결과 공개 ──
const VoteReveal: React.FC<{ view: AView }> = ({ view }) => {
  const result = view.vote_result;
  useEffect(() => {
    if (!result) return undefined;
    const timer = window.setTimeout(() => { sfx.stamp(); (result.passed ? sfx.chime : sfx.buzz)(0.2); }, 400 + (view.players.length * 120));
    return () => { window.clearTimeout(timer); };
  }, [result, view.players.length]);
  if (!result) return null;
  return (
    <motion.div className='da-reveal' initial={{ opacity: 0 }} animate={{ opacity: 1 }}>
      <h3>투표 결과</h3>
      <ul className='da-votes'>
        {view.players.map((player, index) => (
          <motion.li key={player.seat} className={player.vote === 'yes' ? 'is-yes' : 'is-no'} initial={{ rotateY: 90, opacity: 0 }} animate={{ rotateY: 0, opacity: 1 }} transition={{ delay: 0.25 + (index * 0.12), duration: 0.45 }} onAnimationStart={() => { (player.vote === 'yes' ? sfx.yes : sfx.no)(); }}>
            <Face player={player} me={player.seat === view.me} size={36} />
            <span>{player.name}</span>
            <em>{player.vote === 'yes' ? '👍 찬성' : '👎 반대'}</em>
          </motion.li>
        ))}
      </ul>
      <motion.div className={result.passed ? 'da-stamp da-stamp--success' : 'da-stamp da-stamp--fail'} initial={{ scale: 3, opacity: 0, rotate: -12 }} animate={{ scale: 1, opacity: 1, rotate: -6 }} transition={{ delay: 0.5 + (view.players.length * 0.12), type: 'spring', stiffness: 220, damping: 14 }}>
        <b>{result.passed ? '통과' : '부결'}</b>
        <small>찬성 {result.yes.length} · 반대 {result.no.length}</small>
      </motion.div>
    </motion.div>
  );
};

// ── 끝 ──
const EndScreen: React.FC<{ view: AView; onLeave: () => void }> = ({ view, onLeave }) => {
  const spyWon = view.winner === 'spy';
  const mineWon = view.my_role ? view.my_role.spy === spyWon : null;
  useEffect(() => {
    if (spyWon) { sfx.hem(0.3); sfx.buzz(1.2); } else { sfx.fanfare(0.3); }
  }, [spyWon]);
  const reasonText = { missions: '임무 결과', rejects: `${view.reject_limit}번 연속 부결`, guess: `${view.role_names.harry}를 들켰다`, guess_miss: `${view.role_names.harry}를 지켰다` }[view.reason ?? ''] ?? '';
  const target = view.assassin?.target != null ? view.players.find((player) => player.seat === view.assassin?.target) : null;
  return (
    <motion.div className={spyWon ? 'da-end da-end--spy' : 'da-end da-end--da'} initial={{ opacity: 0 }} animate={{ opacity: 1 }}>
      {spyWon ? (
        <>
          <motion.span className='da-end__hem' initial={{ scale: 0, y: 40 }} animate={{ scale: 1, y: 0 }} transition={{ type: 'spring', stiffness: 120, damping: 10, delay: 0.2 }}>
            <b>에헴, 에헴</b>
            <small>~ 엄브리지 ~</small>
          </motion.span>
          <div className='da-end__cats'>
            {[0, 1, 2, 3, 4].map((index) => (
              <motion.i key={index} className='da-end__cat' initial={{ y: -80, opacity: 0, rotate: -20 }} animate={{ y: 0, opacity: 1, rotate: (index % 2 === 0 ? 8 : -8) }} transition={{ delay: 0.6 + (index * 0.15), type: 'spring', stiffness: 120 }}>🐱</motion.i>
            ))}
          </div>
        </>
      ) : (
        <>
          <motion.span className='da-end__wand' initial={{ scale: 0, rotate: -40 }} animate={{ scale: 1, rotate: 0 }} transition={{ type: 'spring', stiffness: 90, damping: 9 }}>⚡</motion.span>
          <Sparks count={28} delay={0.5} />
        </>
      )}
      <motion.h1 className='da-end__title' initial={{ opacity: 0, y: 20 }} animate={{ opacity: 1, y: 0 }} transition={{ delay: 0.5 }}>{spyWon ? `${view.spy_name} 승리!` : `${view.da_name} 승리!`}</motion.h1>
      <p className='da-end__reason'>{reasonText}{target ? ` · 지목: ${target.name}` : ''}</p>
      {mineWon !== null && <p className={mineWon ? 'da-end__me is-win' : 'da-end__me is-lose'}>{mineWon ? '당신이 속한 편이 이겼습니다!' : '아쉽게도 졌습니다…'}</p>}
      <ul className='da-end__roles'>
        {view.players.map((player, index) => (
          <motion.li key={player.seat} className={player.role === 'spy' ? 'is-spy' : undefined} initial={{ opacity: 0, x: -16 }} animate={{ opacity: 1, x: 0 }} transition={{ delay: 1 + (index * 0.06) }}>
            <Face player={player} me={player.seat === view.me} size={30} />
            <b>{player.name}</b>
            <em>{ROLE_ICON[player.role ?? 'da']} {view.roles_final?.[String(player.seat)] ?? player.role}</em>
          </motion.li>
        ))}
      </ul>
      <button type='button' className='da-button' onClick={onLeave}>나가기</button>
    </motion.div>
  );
};

// ── 채팅 (전체 · 첩자) ──
const ChatDock: React.FC<{ sessionId: string; chat: ArmyChat[]; spy: boolean; canChat: boolean; onSent: () => void }> = ({ sessionId, chat, spy, canChat, onSent }) => {
  const [tab, setTab] = useState<'all' | 'spy'>('all');
  const [text, setText] = useState('');
  const listRef = useRef<HTMLUListElement>(null);
  const shown = tab === 'spy' ? chat.filter((message) => message.team) : chat;
  useEffect(() => { if (listRef.current) listRef.current.scrollTop = listRef.current.scrollHeight; }, [shown.length, tab]);
  return (
    <section className='da-chat'>
      <div className='da-chat__tabs'>
        <button type='button' className={tab === 'all' ? 'is-on' : undefined} onClick={() => { setTab('all'); }}>전체</button>
        {spy && <button type='button' className={tab === 'spy' ? 'is-on is-spy' : 'is-spy'} onClick={() => { setTab('spy'); }}>🐱 첩자끼리</button>}
      </div>
      <ul ref={listRef} className='da-chat__list'>
        {shown.map((message) => (
          <li key={message.id} className={[message.mine && 'is-mine', message.team && 'is-spy'].filter(Boolean).join(' ')}>
            {message.team && tab === 'all' && <em>[첩자]</em>}
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
          apiRequestPost(`v1/system/sessions/${sessionId}/chat`, { text: value, channel: tab === 'spy' ? 'team' : 'all' })
            .then(() => { onSent(); return true; })
            .catch(() => { onSent(); });
        }}
        >
          <input type='text' value={text} maxLength={200} placeholder={tab === 'spy' ? '첩자끼리만 보입니다…' : '토론하기…'} onChange={(event) => { setText(event.target.value); }} />
          <button type='submit' className='da-button da-button--small' disabled={!text.trim()}>보내기</button>
        </form>
      )}
    </section>
  );
};

// ── 무대 ──
export const ArmyStage: React.FC<{ sessionId: string; name: string; chat: ArmyChat[]; staff: boolean; isPlayer: boolean; onChanged: () => void }> = ({ sessionId, name, chat, isPlayer, onChanged }) => {
  const history = useHistory();
  const [view, setView] = useState<AView | null>(null);
  const [busy, setBusy] = useState(false);
  const [intro, setIntro] = useState<'pending' | 'open' | 'done'>('pending');
  const [picked, setPicked] = useState<number[]>([]);
  const [guess, setGuess] = useState<number | null>(null);
  const [sound, setSound] = useState(soundOn);
  const [ended, setEnded] = useState(false);
  const tableRef = useRef<HTMLDivElement>(null);
  const left = useRemaining(view);
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
    apiRequestGet<{ view: AView | null }>(`v1/system/sessions/${sessionId}/view`)
      .then((response) => { if (response.view) setView(response.view); return response; })
      .catch(() => undefined);
  }, [sessionId]);
  useEffect(() => {
    load();
    const timer = window.setInterval(load, REFRESH_MS);
    return () => { window.clearInterval(timer); };
  }, [load]);

  // 처음 한 번: 오프닝 (필요의 방 문 + 역할 카드). 끝난 판은 건너뛴다
  const introChecked = useRef(false);
  useEffect(() => {
    if (!view || introChecked.current) return;
    introChecked.current = true;
    let seen = false;
    try { seen = window.sessionStorage.getItem(`ssm:da-intro:${sessionId}`) === '1'; } catch { seen = false; }
    setIntro(seen || view.status === 'finished' ? 'done' : 'open');
  }, [view, sessionId]);
  const finishIntro = useCallback(() => {
    setIntro('done');
    try { window.sessionStorage.setItem(`ssm:da-intro:${sessionId}`, '1'); } catch { /* 이번만 */ }
  }, [sessionId]);

  // 단계가 바뀌면 고른 것을 비우고 효과음
  const phaseKey = view ? `${view.phase}-${view.mission}-${view.rejects}` : '';
  const lastPhase = useRef('');
  useEffect(() => {
    if (!phaseKey || lastPhase.current === phaseKey) return;
    if (lastPhase.current) {
      setPicked([]);
      setGuess(null);
      if (view?.phase === 'team') sfx.wand();
      if (view?.phase === 'vote') sfx.place();
    }
    lastPhase.current = phaseKey;
  }, [phaseKey, view?.phase]);
  // 끝나면 지목 결과를 잠깐 보여 준 뒤 순위(역할 공개) 화면. 이미 끝난 판을 열면 바로
  const wasActive = useRef(false);
  useEffect(() => {
    if (view?.status === 'active') wasActive.current = true;
    if (view?.status === 'finished') {
      const timer = window.setTimeout(() => { setEnded(true); }, wasActive.current ? 4_500 : 300);
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

  if (!view) return createPortal(<div className='game-stage da-stage' role='region' aria-label={name} />, document.body);

  const me = view.me;
  const playing = view.status === 'active' && isPlayer && me !== null;
  const isLeader = me !== null && view.leader === me;
  const leader = view.players.find((player) => player.seat === view.leader);
  const latest = view.results.at(-1);
  const toggle = (seat: number) => {
    if (!(playing && isLeader && view.phase === 'team')) return;
    sfx.pick();
    setPicked((current) => (current.includes(seat) ? current.filter((each) => each !== seat) : current.length >= view.size_needed ? current : [...current, seat]));
  };
  // 카드를 테이블 위로 끌어다 놓으면 대원으로
  const dropOnTable = (seat: number, event: MouseEvent | TouchEvent | PointerEvent) => {
    const rect = tableRef.current?.getBoundingClientRect();
    if (!rect) return;
    const point = 'changedTouches' in event ? event.changedTouches[0] : (event as MouseEvent);
    const inside = point.clientX >= rect.left && point.clientX <= rect.right && point.clientY >= rect.top && point.clientY <= rect.bottom;
    if (inside && !picked.includes(seat) && picked.length < view.size_needed) { sfx.place(); setPicked((current) => [...current, seat]); }
    if (!inside && picked.includes(seat)) setPicked((current) => current.filter((each) => each !== seat));
  };

  const phaseTitle = {
    team: isLeader ? `대원 ${view.size_needed}명을 골라 테이블에 올리세요` : `${leader?.name ?? ''} 리더가 대원 ${view.size_needed}명을 고르는 중`,
    vote: '이 구성에 찬성하나요?',
    vote_result: view.vote_result?.passed ? '통과! 임무를 떠납니다' : '부결… 리더가 바뀝니다',
    mission: view.on_team ? '카드를 한 장 내세요' : '대원들이 카드를 내는 중…',
    result: '카드가 공개됩니다',
    assassin: view.my_role?.spy ? `${view.role_names.harry}를 지목하세요` : `${view.spy_name}들이 ${view.role_names.harry}를 지목하는 중…`,
    finished: '끝났습니다',
  }[view.phase] ?? '';
  const onTable = view.phase === 'team' ? picked : view.team;

  return createPortal(
    <div className={['game-stage da-stage', intro === 'open' && 'is-intro'].filter(Boolean).join(' ')} role='region' aria-label={name}>
      <div className='da-backdrop' aria-hidden><i className='da-glow da-glow--a' /><i className='da-glow da-glow--b' /></div>

      <header className='da-top'>
        <Tracker view={view} />
        {view.status === 'active' && view.deadline_at && <span className={left < 15_000 ? 'da-timer is-low' : 'da-timer'}><GameIcon name='hourglass' /> {mmss(left)}</span>}
        <button type='button' className={sound ? 'da-sound' : 'da-sound is-off'} onClick={toggleSound} aria-pressed={sound}>{sound ? '♪' : '×'}</button>
        <button type='button' className='da-exit' onClick={() => { history.push('/system/group'); }}>나가기</button>
      </header>

      <div className='da-main'>
        <section className='da-board'>
          <h2 className='da-board__title'>{phaseTitle}</h2>

          {/* 테이블: 대원 카드가 올라온다 */}
          <div ref={tableRef} className={['da-table', view.phase === 'team' && isLeader && 'is-droppable'].filter(Boolean).join(' ')}>
            <span className='da-table__label'>임무 {Math.min(view.mission, view.missions)} · 대원 {view.size_needed}명{view.sabotage_needed > 1 ? ` · 방해 ${view.sabotage_needed}장 이상이면 실패` : ''}</span>
            <ul className='da-table__cards'>
              <AnimatePresence>
                {onTable.map((seat) => {
                  const player = view.players.find((each) => each.seat === seat);
                  if (!player) return null;
                  return (
                    <motion.li key={seat} layout initial={{ scale: 0.4, opacity: 0, y: 40 }} animate={{ scale: 1, opacity: 1, y: 0 }} exit={{ scale: 0.4, opacity: 0 }} transition={{ type: 'spring', stiffness: 260, damping: 18 }}>
                      <Face player={player} me={seat === me} size={52} />
                      <span>{player.name}</span>
                    </motion.li>
                  );
                })}
              </AnimatePresence>
              {Array.from({ length: Math.max(view.size_needed - onTable.length, 0) }, (_, index) => (
                // eslint-disable-next-line react/no-array-index-key
                <li key={`empty-${index}`} className='is-empty'>?</li>
              ))}
            </ul>
          </div>

          {/* 단계별 행동 */}
          <div className='da-actions'>
            {playing && view.phase === 'team' && isLeader && (
              <button type='button' className='da-button' disabled={busy || picked.length !== view.size_needed} onClick={() => { sfx.stamp(); send(view.commands.team ?? '대원', picked.join('/')); }}>
                이 {view.size_needed}명으로 제안하기 ({picked.length}/{view.size_needed})
              </button>
            )}
            {playing && view.phase === 'vote' && (
              <div className='da-vote'>
                <button type='button' className={view.my_vote === 'yes' ? 'da-button da-button--yes is-on' : 'da-button da-button--yes'} disabled={busy} onClick={() => { sfx.yes(); send(view.commands.yes ?? '찬성'); }}>👍 찬성</button>
                <button type='button' className={view.my_vote === 'no' ? 'da-button da-button--no is-on' : 'da-button da-button--no'} disabled={busy} onClick={() => { sfx.no(); send(view.commands.no ?? '반대'); }}>👎 반대</button>
                <small>{view.voted_count} / {view.players.length}명 투표 · 다 모이면 한꺼번에 공개됩니다 (바꿀 수 있어요)</small>
              </div>
            )}
            {playing && view.phase === 'mission' && view.on_team && (
              view.my_card ? <p className='da-wait'>카드를 냈습니다. 다른 대원을 기다립니다… ({view.cards_in}/{view.team.length})</p> : (
                <div className='da-pick'>
                  <button type='button' className='da-pick__card da-pick__card--success' disabled={busy} onClick={() => { sfx.chime(); send(view.commands.success ?? '성공'); }}><em>✨</em><b>성공</b></button>
                  {view.can_sabotage && <button type='button' className='da-pick__card da-pick__card--sabotage' disabled={busy} onClick={() => { sfx.buzz(); send(view.commands.sabotage ?? '방해'); }}><em>🐱</em><b>방해</b></button>}
                </div>
              )
            )}
            {view.phase === 'mission' && !view.on_team && <p className='da-wait'>대원이 카드를 내는 중입니다… ({view.cards_in}/{view.team.length})</p>}
            {view.phase === 'assassin' && playing && view.my_role?.spy && (
              <div className='da-assassin'>
                <p>{view.role_names.harry}라고 생각하는 사람을 고르세요 ({view.assassin?.guessed ?? 0}/{view.assassin?.spies ?? 0}명 선택)</p>
                <button type='button' className='da-button da-button--no' disabled={busy || guess === null} onClick={() => { sfx.wand(); send(view.commands.guess ?? '지목', String(guess)); }}>지목하기</button>
              </div>
            )}
          </div>

          {/* 공개 연출: 투표 결과 / 임무 카드 */}
          <AnimatePresence mode='wait'>
            {view.phase === 'vote_result' && <VoteReveal key={`vote-${view.mission}-${view.rejects}`} view={view} />}
            {view.phase === 'result' && latest && <ResultReveal key={`result-${latest.no}`} result={latest} view={view} />}
          </AnimatePresence>
        </section>

        <aside className='da-side'>
          <h3 className='da-side__title'>대원들 ({view.players.length}명)</h3>
          <ul className='da-people'>
            {view.players.map((player) => {
              const canPick = playing && isLeader && view.phase === 'team';
              const canGuess = view.phase === 'assassin' && playing && Boolean(view.my_role?.spy) && player.role !== 'spy';
              const classes = ['da-person', player.seat === me && 'is-me', player.leader && 'is-leader', onTable.includes(player.seat) && 'is-on', player.role === 'spy' && 'is-spy', guess === player.seat && 'is-guess'].filter(Boolean).join(' ');
              return (
                <motion.li
                  key={player.seat}
                  className={classes}
                  drag={canPick}
                  dragSnapToOrigin
                  dragElastic={0.4}
                  whileDrag={{ scale: 1.1, zIndex: 20 }}
                  onDragEnd={(event) => { dropOnTable(player.seat, event as PointerEvent); }}
                  onClick={() => { if (canPick) toggle(player.seat); if (canGuess) { sfx.pick(); setGuess(player.seat); } }}
                  layout
                >
                  <Face player={player} me={player.seat === me} />
                  <span className='da-person__name'>
                    <b>{player.name}{player.seat === me ? ' (나)' : ''}</b>
                    <small>
                      {player.leader && '👑 리더 '}
                      {player.role && `${ROLE_ICON[player.role] ?? ''} ${view.role_names[player.role] ?? player.role} `}
                      {view.phase === 'vote' && (player.voted ? '✓ 투표함' : '… 고민 중')}
                      {view.phase === 'mission' && player.card_in !== null && player.on_team && (player.card_in ? '✓ 카드 냄' : '… 고르는 중')}
                    </small>
                  </span>
                </motion.li>
              );
            })}
          </ul>
          {view.my_role && (
            <p className={view.my_role.spy ? 'da-me is-spy' : 'da-me'}>
              <b>{ROLE_ICON[view.my_role.key]} {view.my_role.name}</b>
              <span>{view.my_role.how}</span>
            </p>
          )}
        </aside>
      </div>

      <ChatDock sessionId={sessionId} chat={chat} spy={Boolean(view.my_role?.spy)} canChat={isPlayer} onSent={onChanged} />

      <AnimatePresence>
        {intro === 'open' && <Opening key='opening' view={view} onDone={finishIntro} />}
      </AnimatePresence>
      <AnimatePresence>
        {ended && intro === 'done' && <EndScreen key='end' view={view} onLeave={() => { history.push('/system/group'); }} />}
      </AnimatePresence>
    </div>,
    document.body,
  );
};
