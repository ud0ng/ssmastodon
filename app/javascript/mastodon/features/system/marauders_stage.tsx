// 도둑 지도 게임방 (이벤트, 웹 전용): 양피지에 잉크로 그려진 호그와트 지도 위에서 학생 팀과 사감 팀이 숨바꼭질을 한다.
//   처음 들어오면 양피지가 페이드인되며 맹세 문구와 함께 잉크가 번져 지도가 그려지고, 역할 안내 창이 뜬다.
//   턴마다 갈 수 있는 방이 빛나고 클릭하면 선택 완료, 모두 고르면 이름표 달린 발자국이 찍히며 이동한다.
//   체포되면 발자국이 사무실까지 질질 끌려가고, 끝나면 '장난 끝' 문구와 함께 지도가 지워지고 학생들의 실제 이동 경로가 리플레이로 그려진다.
//   서버: Game::Web::MaraudersMap#view_for (GET /api/v1/system/sessions/:id/view), 행동은 POST /api/v1/system/commands, 채팅은 POST /sessions/:id/chat (channel=team)
import React, { useCallback, useEffect, useMemo, useRef, useState } from 'react';

import { defineMessages, FormattedMessage, useIntl } from 'react-intl';

import { useHistory } from 'react-router-dom';

import { AnimatePresence, motion } from 'framer-motion';
import { createPortal } from 'react-dom';

import { apiRequestGet, apiRequestPost } from 'mastodon/api';

import { sendCommand } from './board';
import { useStageLayout } from './lobby';

// ── 서버가 보내는 판 ──
interface MRoom { id: number; name: string; x: number; y: number; kind: 'room' | 'tower' | 'office'; tower?: number }
interface MapData {
  rooms: MRoom[];
  cols: number;
  floors: number;
  tower_cols: number[];
  office: number;
  corridors: { a: number; b: number }[];
  fixed_stairs: { a: number; b: number }[];
  moving_stairs: { a: number; b: number; phase: 'a' | 'b' }[];
  stairs_phase: 'a' | 'b';
  stairs_every: number;
}
interface MToken { seat: number; room: number; team: 'student' | 'prefect'; status: string | null }
interface MZone { kind: 'floor' | 'tower'; y?: number; x?: number; name: string }
interface MClue { turn: number; kind: 'footprint' | 'zone' | 'watch' | 'scout'; seat: number; room?: number; zone?: MZone; count?: number; range?: number; age: number; room_name?: string }
interface MPlayer { seat: number; name: string; account_id: string; acct?: string; avatar?: string | null; team: 'student' | 'prefect'; status: string | null; rescued: number }
interface MLast {
  turn: number;
  moves: Record<string, { from: number; to: number; secret: boolean }>;
  arrests: { seat: number; by: number; room: number; out: boolean }[];
  rescued: number[];
  secret: number[];
  stairs: boolean;
}
interface MHistory { turn: number; positions: Record<string, number>; status_of?: Record<string, string> }
interface MReward { result: 'win' | 'lose' | 'draw'; points: number; money: number; items: string[] }

interface MView {
  map: MapData;
  status: string;
  turn: number;
  max_turns: number;
  deadline_at: string | null;
  now: string;
  student_name: string;
  prefect_name: string;
  commands: { move: string; hide: string; cloak: string; ability: string };
  secret: { a: number; b: number }[];
  targets: { room: number; done: boolean }[];
  targets_done: number;
  targets_total: number;
  cloak_turns: number;
  tokens: MToken[];
  clues: MClue[];
  last: MLast | null;
  players: MPlayer[];
  bubbles: { id: string; seat: number; text: string; room: number; at: string }[];
  log: string[];
  history: MHistory[] | null;
  roles: Record<string, string> | null;
  winner: 'student' | 'prefect' | null;
  finish: { currency: string; test: boolean; rewards: Record<string, MReward | null> } | null;
  me: number | null;
  team: 'student' | 'prefect' | null;
  spectator: boolean;
  full: boolean;
  role: 'watcher' | 'scout' | 'chaser' | null;
  my_status: string | null;
  items: { cloak?: number; cloaked?: boolean; ability?: number };
  planned: { room?: number } | null;
  my_turn: boolean;
  submitted: boolean;
  waiting: string[];
  moves: number[];
  chase: boolean;
}

interface ViewResponse { view: MView | null }

export interface MmChatMessage {
  id: string;
  mine: boolean;
  name: string;
  acct: string;
  avatar: string;
  text: string;
  team?: 'student' | 'prefect' | null;
}

const messages = defineMessages({
  chatAll: { id: 'mm.chat_all', defaultMessage: 'Everyone' },
  chatTeam: { id: 'mm.chat_team', defaultMessage: 'Team' },
  placeholder: { id: 'mm.chat_placeholder', defaultMessage: 'Say something' },
  send: { id: 'mm.chat_send', defaultMessage: 'Send' },
});

const REFRESH_MS = 1_500;
const CELL_W = 138;
const CELL_H = 70;
const GAP_X = 40;
const GAP_Y = 34;
const PAD = 58;
const OATH = '나는 좋은 일을 하지 않을 것을 엄숙히 맹세합니다';

// ── 지도 좌표 ──
interface Geometry { width: number; height: number; center: (room: number) => { x: number; y: number }; rect: (room: number) => { x: number; y: number; w: number; h: number }; rows: number }

const useGeometry = (map: MapData): Geometry => useMemo(() => {
  const rows = Math.max(...map.rooms.map((room) => room.y)) + 1;
  const width = (map.cols * CELL_W) + ((map.cols - 1) * GAP_X) + (PAD * 2);
  const height = (rows * CELL_H) + ((rows - 1) * GAP_Y) + (PAD * 2);
  const byId = new Map(map.rooms.map((room) => [room.id, room]));
  const rect = (id: number) => {
    const room = byId.get(id);
    const x = room ? room.x : 0;
    const y = room ? room.y : 0;
    return { x: PAD + (x * (CELL_W + GAP_X)), y: PAD + ((rows - 1 - y) * (CELL_H + GAP_Y)), w: CELL_W, h: CELL_H };
  };
  const center = (id: number) => {
    const box = rect(id);
    return { x: box.x + (box.w / 2), y: box.y + (box.h / 2) };
  };
  return { width, height, center, rect, rows };
}, [map]);

// ── 지도 (SVG): 방·복도·계단·비밀 통로·목표. 처음에는 잉크가 번지며 그려진다 ──
const MapSvg: React.FC<{
  view: MView;
  geo: Geometry;
  reachable: number[];
  here: number | null;
  planned: number | null;
  pickingWatch: boolean;
  draw: boolean;
  fade: boolean;
  onPick: (room: number) => void;
}> = ({ view, geo, reachable, here, planned, pickingWatch, draw, fade, onPick }) => {
  const { map } = view;
  const targets = new Map(view.targets.map((target) => [target.room, target.done]));

  const line = (a: number, b: number) => {
    const from = geo.center(a);
    const to = geo.center(b);
    return { x1: from.x, y1: from.y, x2: to.x, y2: to.y };
  };

  return (
    <motion.svg
      className='mm-map'
      viewBox={`0 0 ${geo.width} ${geo.height}`}
      role='img'
      initial={draw ? { clipPath: 'circle(0% at 50% 55%)' } : false}
      animate={{ clipPath: 'circle(150% at 50% 55%)', opacity: fade ? 0 : 1 }}
      transition={{ clipPath: { duration: draw ? 3.4 : 0, ease: 'easeOut' }, opacity: { duration: 1.2 } }}
    >
      <defs>
        <filter id='mm-ink' x='-5%' y='-5%' width='110%' height='110%'>
          <feTurbulence type='fractalNoise' baseFrequency='0.9' numOctaves='2' seed='3' result='noise' />
          <feDisplacementMap in='SourceGraphic' in2='noise' scale='2.2' />
        </filter>
        <pattern id='mm-stipple' width='9' height='9' patternUnits='userSpaceOnUse'>
          <rect width='9' height='9' fill='#e9d8a6' />
          <circle cx='2' cy='2' r='0.8' fill='#6b3a22' opacity='0.5' />
          <circle cx='6.5' cy='5.5' r='0.7' fill='#6b3a22' opacity='0.45' />
          <circle cx='4' cy='8' r='0.5' fill='#6b3a22' opacity='0.35' />
        </pattern>
        <pattern id='mm-stipple-tower' width='9' height='9' patternUnits='userSpaceOnUse'>
          <rect width='9' height='9' fill='#dfcca0' />
          <circle cx='2' cy='2' r='0.9' fill='#5a2f3a' opacity='0.55' />
          <circle cx='6.5' cy='5.5' r='0.8' fill='#5a2f3a' opacity='0.5' />
        </pattern>
        <linearGradient id='mm-secret' x1='0' x2='1'>
          <stop offset='0' stopColor='#b48bff' />
          <stop offset='1' stopColor='#6ad4ff' />
        </linearGradient>
      </defs>

      {/* 층 이름 (왼쪽) */}
      <g className='mm-floors'>
        {Array.from({ length: map.floors }, (_, y) => (
          <text key={y} x={PAD - 14} y={geo.center(map.rooms.find((room) => room.y === y && room.kind !== 'tower')?.id ?? 0).y + 5} textAnchor='end'>{y === 0 ? '지하' : `${y}층`}</text>
        ))}
      </g>

      {/* 복도(두 줄)·고정 계단(가로 단 무늬) */}
      <g filter='url(#mm-ink)' className='mm-links'>
        {map.corridors.map((link, index) => (
          <motion.line
            key={`o-${link.a}-${link.b}`}
            className='mm-road-outer'
            {...line(link.a, link.b)}
            initial={draw ? { pathLength: 0 } : false}
            animate={{ pathLength: 1 }}
            transition={{ duration: 1.1, delay: draw ? 0.6 + ((index % 20) * 0.08) : 0 }}
          />
        ))}
        {map.corridors.map((link) => <line key={`i-${link.a}-${link.b}`} className='mm-road-inner' {...line(link.a, link.b)} />)}
        {map.fixed_stairs.map((link, index) => (
          <motion.line
            key={`s-${link.a}-${link.b}`}
            className='mm-stairs'
            {...line(link.a, link.b)}
            initial={draw ? { pathLength: 0 } : false}
            animate={{ pathLength: 1 }}
            transition={{ duration: 1.1, delay: draw ? 0.9 + ((index % 20) * 0.08) : 0 }}
          />
        ))}
      </g>

      {/* 움직이는 계단: 지금 열린 쪽은 실선, 닫힌 쪽은 희미한 점선. 바뀌면 계단이 움직인다 */}
      <g className='mm-moving'>
        {map.moving_stairs.map((link) => {
          const open = link.phase === map.stairs_phase;
          return (
            <motion.line
              key={`${link.a}-${link.b}-${link.phase}`}
              className={open ? 'mm-stairs mm-stairs--open' : 'mm-stairs mm-stairs--closed'}
              {...line(link.a, link.b)}
              initial={false}
              animate={open ? { opacity: 1, pathLength: 1 } : { opacity: 0.28, pathLength: 1 }}
              transition={{ duration: 0.9 }}
            />
          );
        })}
      </g>

      {/* 비밀 통로: 문이 반짝반짝 빛난다 */}
      <g className='mm-secret'>
        {view.secret.map((passage) => {
          const from = geo.center(passage.a);
          const to = geo.center(passage.b);
          const midX = (from.x + to.x) / 2;
          const bend = Math.abs(to.y - from.y) > Math.abs(to.x - from.x) ? 90 : -90;
          return (
            <g key={`${passage.a}-${passage.b}`}>
              <motion.path
                d={`M ${from.x} ${from.y} Q ${midX + bend} ${(from.y + to.y) / 2} ${to.x} ${to.y}`}
                className='mm-passage'
                initial={{ pathLength: 0 }}
                animate={{ pathLength: 1, opacity: [0.5, 1, 0.5] }}
                transition={{ pathLength: { duration: 1.6 }, opacity: { duration: 2.4, repeat: Infinity } }}
              />
              {[from, to].map((point, index) => (
                <motion.text key={index} x={point.x + 36} y={point.y - 22} className='mm-door' animate={{ opacity: [0.3, 1, 0.3], scale: [0.9, 1.25, 0.9] }} transition={{ duration: 1.8, repeat: Infinity, delay: index * 0.5 }}>✦</motion.text>
              ))}
            </g>
          );
        })}
      </g>

      {/* 방 */}
      {map.rooms.map((room, index) => {
        const box = geo.rect(room.id);
        const target = targets.get(room.id);
        const canGo = reachable.includes(room.id);
        const isHere = here === room.id;
        const isPlan = planned === room.id;
        const classes = ['mm-room', room.kind === 'tower' && 'mm-room--tower', room.kind === 'office' && 'mm-room--office', canGo && 'is-go', isHere && 'is-here', isPlan && 'is-plan', pickingWatch && 'is-pick', target !== undefined && 'is-goal', target && 'is-done'].filter(Boolean).join(' ');
        return (
          <motion.g
            key={room.id}
            className={classes}
            initial={draw ? { opacity: 0, scale: 0.85 } : false}
            animate={{ opacity: 1, scale: 1 }}
            transition={{ duration: 0.6, delay: draw ? 1.2 + ((index % 30) * 0.07) : 0 }}
            style={{ transformOrigin: `${box.x + (box.w / 2)}px ${box.y + (box.h / 2)}px` }}
            onClick={() => { if (canGo || pickingWatch) onPick(room.id); }}
          >
            <rect x={box.x} y={box.y} width={box.w} height={box.h} rx={8} className='mm-room__shape' filter='url(#mm-ink)' />
            <rect x={box.x + 5} y={box.y + 5} width={box.w - 10} height={box.h - 10} rx={5} className='mm-room__inner' />
            <text x={box.x + (box.w / 2)} y={box.y + 27} textAnchor='middle' className='mm-room__name' textLength={Math.min(box.w - 24, room.name.length * 16)} lengthAdjust='spacingAndGlyphs'>{room.name}</text>
            {room.kind === 'office' && <text x={box.x + 12} y={box.y + 22} className='mm-room__icon'>🗝</text>}
            {target !== undefined && <text x={box.x + box.w - 24} y={box.y + 24} className='mm-room__icon'>{target ? '✔' : '★'}</text>}
          </motion.g>
        );
      })}
    </motion.svg>
  );
};

// ── 이름표 달린 발자국 토큰 ──
const NameTag: React.FC<{ player: MPlayer | undefined; team: 'student' | 'prefect'; me: boolean; dim?: boolean; label?: string }> = ({ player, team, me, dim, label }) => (
  <motion.span
    className={['mm-tag', `mm-tag--${(player?.seat ?? 0) % 6}`, team === 'prefect' && 'is-prefect', me && 'is-me', dim && 'is-dim'].filter(Boolean).join(' ')}
    animate={{ y: [0, -5, 0] }}
    transition={{ duration: 2.4 + ((player?.seat ?? 0) % 3) * 0.4, repeat: Infinity, ease: 'easeInOut' }}
  >
    {player?.avatar && <img src={player.avatar} alt='' />}
    <b>{player?.name ?? '?'}</b>
    {label && <i>{label}</i>}
  </motion.span>
);

// 검은 신발 자국 한 쌍 (도둑 지도처럼)
const Shoe: React.FC<{ x: number; y: number; rot: number }> = ({ x, y, rot }) => (
  <g transform={`translate(${x} ${y}) rotate(${rot})`}>
    <path d='M0 -9 C5 -9 7 -3 6 2 C5 5 3 6 0 6 C-3 6 -5 5 -6 2 C-7 -3 -5 -9 0 -9 Z' />
    <path d='M-3.5 9 C-3.5 7 3.5 7 3.5 9 C3.5 12 -3.5 12 -3.5 9 Z' />
  </g>
);

const FootGlyph: React.FC<{ team: 'student' | 'prefect' }> = ({ team }) => (
  <svg className={`mm-foot mm-foot--${team}`} viewBox='0 0 38 26' aria-hidden>
    <Shoe x={11} y={12} rot={-8} />
    <Shoe x={27} y={14} rot={8} />
  </svg>
);

interface Stamp { id: string; x: number; y: number; team: 'student' | 'prefect'; delay: number; angle: number }

// ── 범례: 지도에 그려진 것이 무엇인지 ──
const LegendSample: React.FC<{ children: React.ReactNode }> = ({ children }) => (
  <svg className='mm-legend__sample' viewBox='0 0 44 20' aria-hidden>{children}</svg>
);

const MapLegend: React.FC<{ view: MView }> = ({ view }) => {
  const every = view.map.stairs_every;
  const left = every - ((view.turn - 1) % every);
  return (
    <aside className='mm-legend' aria-label='legend'>
      <h4><FormattedMessage id='mm.legend' defaultMessage='Map key' /></h4>
      <ul>
        <li><LegendSample><line x1='3' y1='10' x2='41' y2='10' className='mm-road-outer' /><line x1='3' y1='10' x2='41' y2='10' className='mm-road-inner' /></LegendSample><FormattedMessage id='mm.legend_corridor' defaultMessage='Corridor' /></li>
        <li><LegendSample><line x1='3' y1='10' x2='41' y2='10' className='mm-stairs' /></LegendSample><FormattedMessage id='mm.legend_stairs' defaultMessage='Stairs (between floors)' /></li>
        <li><LegendSample><line x1='3' y1='10' x2='41' y2='10' className='mm-stairs mm-stairs--open' /></LegendSample><span><FormattedMessage id='mm.legend_moving' defaultMessage='Moving stairs (open now)' /> <small><FormattedMessage id='mm.legend_moving_note' defaultMessage='Switch every {every} turns, next in {left}' values={{ every, left }} /></small></span></li>
        <li><LegendSample><line x1='3' y1='10' x2='41' y2='10' className='mm-stairs mm-stairs--closed' /></LegendSample><FormattedMessage id='mm.legend_closed' defaultMessage='Moving stairs (closed now)' /></li>
        {view.secret.length > 0 && <li><LegendSample><path d='M3 14 Q22 -4 41 14' className='mm-passage' /><text x='34' y='9' className='mm-door'>✦</text></LegendSample><FormattedMessage id='mm.legend_secret' defaultMessage='Secret passage (students only)' /></li>}
        {view.targets.length > 0 && <li><LegendSample><rect x='6' y='2' width='32' height='16' rx='3' className='mm-room__shape is-goal-sample' /><text x='30' y='13' className='mm-legend__star'>★</text></LegendSample><FormattedMessage id='mm.legend_goal' defaultMessage='Goal place' /></li>}
        <li><LegendSample><rect x='6' y='2' width='32' height='16' rx='3' className='mm-legend__office' /><text x='9' y='13' className='mm-legend__star'>🗝</text></LegendSample><FormattedMessage id='mm.legend_office' defaultMessage="Filch's office (jail)" /></li>
        <li><LegendSample><rect x='6' y='2' width='32' height='16' rx='3' className='mm-legend__tower' /></LegendSample><FormattedMessage id='mm.legend_tower' defaultMessage='Tower room' /></li>
        <li><span className='mm-legend__feet'><FootGlyph team='student' /></span><FormattedMessage id='mm.legend_foot' defaultMessage='Footprints = where someone is (ribbon = name)' /></li>
      </ul>
    </aside>
  );
};

// ── 서버 시계 기준 남은 초 ──
const useRemaining = (view: MView | null) => {
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

// 체포 때 타격음 (웹 오디오, 브라우저가 막으면 조용히 넘어간다)
const thump = () => {
  try {
    const Context = window.AudioContext ?? (window as unknown as { webkitAudioContext?: typeof AudioContext }).webkitAudioContext;
    if (!Context) return;
    const context = new Context();
    const oscillator = context.createOscillator();
    const gain = context.createGain();
    oscillator.type = 'triangle';
    oscillator.frequency.setValueAtTime(140, context.currentTime);
    oscillator.frequency.exponentialRampToValueAtTime(40, context.currentTime + 0.3);
    gain.gain.setValueAtTime(0.5, context.currentTime);
    gain.gain.exponentialRampToValueAtTime(0.001, context.currentTime + 0.35);
    oscillator.connect(gain);
    gain.connect(context.destination);
    oscillator.start();
    oscillator.stop(context.currentTime + 0.4);
  } catch {
    // 소리가 안 나도 게임은 계속된다
  }
};

// ── 역할 안내 창 ──
const ROLE_LINES: Record<string, { title: string; lines: string[]; items: { name: string; text: string }[] }> = {
  student: {
    title: '당신은 기숙사를 탈출한 학생입니다.',
    lines: ['기숙사 사감에게 잡히지 않고 목적지를 방문했다 돌아오면 승리입니다!'],
    items: [{ name: '투명 망토', text: '팀 공용 아이템. 쓰면 2턴 동안 흔적도 구역 공개도 남지 않습니다.' }],
  },
  watcher: { title: '당신은 감시자입니다.', lines: ['통금 시간을 어긴 학생들을 체포하세요!'], items: [{ name: '감시 (판당 1회)', text: '방 하나를 3턴 동안 감시합니다. 학생이 들어오면 위치가 공개됩니다.' }] },
  scout: { title: '당신은 정찰자입니다.', lines: ['통금 시간을 어긴 학생들을 체포하세요!'], items: [{ name: '정찰 (판당 1회)', text: '주변 2칸 안에 학생이 몇 명 있는지 확인합니다.' }] },
  chaser: { title: '당신은 추격자입니다.', lines: ['통금 시간을 어긴 학생들을 체포하세요!'], items: [{ name: '추격 (판당 1회)', text: '이번 턴에 2칸 이동합니다.' }] },
};

const RoleModal: React.FC<{ view: MView; onClose: () => void }> = ({ view, onClose }) => {
  const key = view.team === 'student' ? 'student' : (view.role ?? 'chaser');
  const info = ROLE_LINES[key] ?? ROLE_LINES.chaser;
  if (!info) return null;
  return (
    <motion.div className='mm-modal' initial={{ opacity: 0 }} animate={{ opacity: 1 }} exit={{ opacity: 0 }}>
      <motion.div className='mm-modal__card' initial={{ y: 30, scale: 0.92, rotate: -1.5 }} animate={{ y: 0, scale: 1, rotate: 0 }} transition={{ type: 'spring', stiffness: 160, damping: 16 }}>
        <small>{view.team === 'student' ? view.student_name : view.prefect_name} 팀</small>
        <h2>{info.title}</h2>
        {info.lines.map((line) => <p key={line}>{line}</p>)}
        <ul>
          {info.items.map((item) => <li key={item.name}><strong>{item.name}</strong> {item.text}</li>)}
        </ul>
        <button type='button' className='mm-button' onClick={onClose}><FormattedMessage id='mm.role_ok' defaultMessage='Got it' /></button>
      </motion.div>
    </motion.div>
  );
};

// ── 맹세: 양피지가 페이드인되며 문구가 쓰이고, 잉크가 번지며 지도가 나타난다 ──
const Oath: React.FC<{ onDone: () => void }> = ({ onDone }) => {
  // 화면이 1.5초마다 다시 그려져도 타이머가 처음부터 다시 시작되지 않게 최신 콜백만 ref 에 둔다
  const done = useRef(onDone);
  done.current = onDone;

  useEffect(() => {
    const timer = window.setTimeout(() => { done.current(); }, 4_600);
    return () => { window.clearTimeout(timer); };
  }, []);

  return (
    <motion.div className='mm-oath' initial={{ opacity: 0 }} animate={{ opacity: 1 }} exit={{ opacity: 0 }} transition={{ duration: 1.1 }}>
      <p>
        {OATH.split('').map((char, index) => (
          <motion.span key={index} initial={{ opacity: 0, y: 6, filter: 'blur(4px)' }} animate={{ opacity: 1, y: 0, filter: 'blur(0px)' }} transition={{ delay: 1.1 + (index * 0.07), duration: 0.5 }}>{char}</motion.span>
        ))}
      </p>
      <motion.i initial={{ scale: 0, opacity: 0 }} animate={{ scale: [0, 1.4, 3.2], opacity: [0, 0.5, 0] }} transition={{ delay: 3.4, duration: 1.2 }} />
    </motion.div>
  );
};

// ── 채팅: 전체 / 팀 ──
const ChatDock: React.FC<{
  sessionId: string;
  chat: MmChatMessage[];
  team: 'student' | 'prefect' | null;
  canChat: boolean;
  jailed: boolean;
  onSent: () => void;
}> = ({ sessionId, chat, team, canChat, jailed, onSent }) => {
  const intl = useIntl();
  const [channel, setChannel] = useState<'all' | 'team'>(jailed ? 'team' : 'all');
  const [text, setText] = useState('');
  const listRef = useRef<HTMLUListElement>(null);
  const shown = chat.filter((message) => (channel === 'team' ? Boolean(message.team) : !message.team));

  useEffect(() => {
    if (listRef.current) listRef.current.scrollTop = listRef.current.scrollHeight;
  }, [shown.length, channel]);

  const submit = useCallback((event: React.FormEvent) => {
    event.preventDefault();
    const value = text.trim();
    if (!value) return;
    setText('');
    apiRequestPost(`v1/system/sessions/${sessionId}/chat`, { text: value, channel })
      .then(() => { onSent(); return true; })
      .catch(() => { onSent(); });
  }, [sessionId, text, channel, onSent]);

  return (
    <section className='mm-chat'>
      <div className='mm-chat__tabs'>
        <button type='button' className={channel === 'all' ? 'is-on' : undefined} onClick={() => { setChannel('all'); }}>{intl.formatMessage(messages.chatAll)}</button>
        {team && <button type='button' className={channel === 'team' ? 'is-on' : undefined} onClick={() => { setChannel('team'); }}>{intl.formatMessage(messages.chatTeam)}</button>}
      </div>
      <ul ref={listRef} className='mm-chat__list'>
        {shown.map((message) => (
          <li key={message.id} className={message.mine ? 'is-mine' : undefined}>
            {message.avatar && <img src={message.avatar} alt='' />}
            <strong>{message.name}</strong>
            <span>: {message.text}</span>
          </li>
        ))}
      </ul>
      {canChat && (
        <form onSubmit={submit}>
          <input type='text' value={text} maxLength={200} placeholder={intl.formatMessage(messages.placeholder)} onChange={(event) => { setText(event.target.value); }} />
          <button type='submit' disabled={!text.trim()}>{intl.formatMessage(messages.send)}</button>
        </form>
      )}
    </section>
  );
};

// ── 끝: 지도가 지워지고 학생들의 실제 이동 경로가 리플레이로 그려진다 ──
const Replay: React.FC<{ view: MView; geo: Geometry }> = ({ view, geo }) => {
  const history = useMemo(() => view.history ?? [], [view.history]);
  const students = view.players.filter((player) => player.team === 'student');
  const [step, setStep] = useState(0);

  useEffect(() => {
    if (history.length === 0) return undefined;
    const timer = window.setInterval(() => { setStep((value) => (value + 1) % (history.length + 3)); }, 900);
    return () => { window.clearInterval(timer); };
  }, [history.length]);

  const upto = Math.min(step, history.length - 1);
  const colors = ['#2b4c8f', '#8b2d2d', '#2d6b3f', '#7a4a1a', '#5a2d8b', '#1d6b73', '#8b6b1d', '#6b2d52'];

  return (
    <svg className='mm-replay' viewBox={`0 0 ${geo.width} ${geo.height}`} aria-hidden>
      {students.map((student, index) => {
        const points = history.slice(0, upto + 1).map((entry) => entry.positions[String(student.seat)]).filter((room): room is number => room !== undefined).map((room) => geo.center(room));
        if (points.length < 2) return null;
        const d = points.map((point, order) => `${order === 0 ? 'M' : 'L'} ${point.x + (index * 3)} ${point.y + (index * 3)}`).join(' ');
        return <motion.path key={student.seat} d={d} fill='none' stroke={colors[index % colors.length]} strokeWidth={5} strokeLinecap='round' strokeDasharray='2 10' initial={{ pathLength: 0 }} animate={{ pathLength: 1 }} transition={{ duration: 0.8 }} />;
      })}
      {view.map.rooms.filter((room) => view.targets.some((target) => target.room === room.id)).map((room) => {
        const point = geo.center(room.id);
        return <text key={room.id} x={point.x} y={point.y} textAnchor='middle' className='mm-replay__goal'>★ {room.name}</text>;
      })}
    </svg>
  );
};

// ── 게임방 ──
export const MaraudersStage: React.FC<{
  sessionId: string;
  name: string;
  chat: MmChatMessage[];
  staff: boolean;
  isPlayer: boolean;
  onChanged: () => void;
}> = ({ sessionId, name, chat, staff, isPlayer, onChanged }) => {
  const history = useHistory();
  const [view, setView] = useState<MView | null>(null);
  const [stamps, setStamps] = useState<Stamp[]>([]);
  const [intro, setIntro] = useState<'oath' | 'role' | 'done'>('done');
  const [pickingWatch, setPickingWatch] = useState(false);
  const [ending, setEnding] = useState<'none' | 'over' | 'replay' | 'result'>('none');
  const [busy, setBusy] = useState(false);
  const seenLast = useRef<number>(-1);
  const introChecked = useRef(false);

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
    const timer = window.setInterval(load, REFRESH_MS);
    return () => { window.clearInterval(timer); };
  }, [load]);

  const geo = useGeometry(view?.map ?? { rooms: [{ id: 0, name: '', x: 0, y: 0, kind: 'room' }], cols: 1, floors: 1, tower_cols: [], office: 0, corridors: [], fixed_stairs: [], moving_stairs: [], stairs_phase: 'a', stairs_every: 3 });

  // 처음 들어왔을 때: 1턴이면 맹세 → 역할 안내, 아니면 역할 안내만 (한 번만)
  useEffect(() => {
    if (!view || introChecked.current) return;
    introChecked.current = true;
    if (view.status !== 'active' || !view.team) return;
    let seen = false;
    try {
      seen = window.sessionStorage.getItem(`ssm:mm-intro:${sessionId}`) === '1';
    } catch {
      seen = false;
    }
    if (!seen) setIntro(view.turn <= 1 ? 'oath' : 'role');
  }, [view, sessionId]);

  const finishIntro = useCallback((next: 'role' | 'done') => {
    setIntro(next);
    if (next === 'done') {
      try { window.sessionStorage.setItem(`ssm:mm-intro:${sessionId}`, '1'); } catch { /* 저장이 막혀도 계속 */ }
    }
  }, [sessionId]);

  // 새 턴 결과: 발자국이 찍히며 이동 / 체포되면 발자국이 사무실까지 끌려간다
  useEffect(() => {
    const last = view?.last;
    if (!view || !last) return;
    if (seenLast.current === -1) {
      seenLast.current = last.turn;
      return;
    }
    if (last.turn === seenLast.current) return;
    seenLast.current = last.turn;

    const next: Stamp[] = [];
    Object.entries(last.moves).forEach(([seat, move]) => {
      if (move.from === move.to || move.secret) return;
      const player = view.players.find((each) => String(each.seat) === seat);
      const from = geo.center(move.from);
      const to = geo.center(move.to);
      for (let index = 1; index <= 5; index += 1) {
        const t = index / 6;
        next.push({ id: `${last.turn}-${seat}-${index}`, x: from.x + ((to.x - from.x) * t), y: from.y + ((to.y - from.y) * t), team: player?.team ?? 'student', delay: index * 0.16, angle: (Math.atan2(to.y - from.y, to.x - from.x) * 180) / Math.PI + 90 });
      }
    });
    last.arrests.forEach((arrest) => {
      const from = geo.center(arrest.room);
      const to = geo.center(view.map.office);
      for (let index = 1; index <= 8; index += 1) {
        const t = index / 9;
        next.push({ id: `${last.turn}-a${arrest.seat}-${index}`, x: from.x + ((to.x - from.x) * t), y: from.y + ((to.y - from.y) * t), team: 'student', delay: 0.9 + (index * 0.22), angle: (Math.atan2(to.y - from.y, to.x - from.x) * 180) / Math.PI + 90 });
      }
    });
    setStamps(next);
    if (last.arrests.length > 0) window.setTimeout(thump, 500);
    const timer = window.setTimeout(() => { setStamps([]); }, 3_800);
    return () => { window.clearTimeout(timer); };
  }, [view, geo]);

  // 끝났다 → '장난 끝' → 리플레이 → 결과 (이미 끝난 방에 들어오면 바로 결과)
  const status = view?.status;
  const prevStatus = useRef<string | null>(null);
  useEffect(() => {
    if (!status) return;
    if (status === 'finished') {
      setEnding((current) => (current !== 'none' ? current : (prevStatus.current && prevStatus.current !== 'finished' ? 'over' : 'result')));
    }
    prevStatus.current = status;
  }, [status]);

  useEffect(() => {
    if (ending !== 'over') return undefined;
    const timer = window.setTimeout(() => { setEnding('replay'); }, 3_200);
    return () => { window.clearTimeout(timer); };
  }, [ending]);

  const remaining = useRemaining(view);

  const send = useCallback((command: string, args?: string) => {
    if (!view) return;
    setBusy(true);
    sendCommand({ session_id: sessionId, command, ...(args !== undefined ? { args } : {}) })
      .then(() => { load(); return true; })
      .catch(() => undefined)
      .finally(() => { setBusy(false); });
  }, [view, sessionId, load]);

  const pick = useCallback((room: number) => {
    if (!view) return;
    if (pickingWatch) {
      setPickingWatch(false);
      send(view.commands.ability, String(room));
      return;
    }
    const here = view.me !== null ? view.tokens.find((token) => token.seat === view.me)?.room : undefined;
    if (room === here) send(view.commands.hide);
    else send(view.commands.move, String(room));
  }, [view, pickingWatch, send]);

  if (!view) return null;

  const myToken = view.me !== null ? view.tokens.find((token) => token.seat === view.me) : undefined;
  const here = myToken?.room ?? null;
  const canAct = isPlayer && view.my_turn && !view.submitted;
  const reachable = canAct ? view.moves : [];
  const planned = view.planned?.room ?? null;
  const jailed = view.my_status === 'jailed';
  const out = view.my_status === 'out';
  const byseat = new Map(view.players.map((player) => [player.seat, player]));
  const names = view.team === 'student' ? view.student_name : view.prefect_name;
  const total = 45;

  const watchPending = view.role === 'watcher' && (view.items.ability ?? 0) > 0 && canAct;

  // 내 차례: 갈 수 있는 방(감시 고르기면 모든 방)만 남기고 나머지는 검은 오버레이로 덮는다
  const holes = pickingWatch ? view.map.rooms.map((room) => room.id) : reachable;
  const dimMask = holes.length > 0 ? `url("data:image/svg+xml;utf8,${encodeURIComponent(`<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 ${geo.width} ${geo.height}' preserveAspectRatio='none'><rect width='${geo.width}' height='${geo.height}' fill='white'/>${holes.map((room) => { const box = geo.rect(room); return `<rect x='${box.x - 6}' y='${box.y - 6}' width='${box.w + 12}' height='${box.h + 12}' rx='14' fill='black'/>`; }).join('')}</svg>`)}")` : null;

  const pct = (point: { x: number; y: number }) => ({ left: `${(point.x / geo.width) * 100}%`, top: `${(point.y / geo.height) * 100}%` });
  const dragged = new Set((view.last?.arrests ?? []).map((arrest) => arrest.seat));

  return createPortal(
    <div className='game-stage mm-stage' role='region' aria-label={name}>
      {/* 맨 위: 턴 · 제한 시간 · 목표 · 내 팀 */}
      <header className='mm-top'>
        <span className='mm-chip'><FormattedMessage id='mm.turn' defaultMessage='Turn {turn}/{max}' values={{ turn: view.turn, max: view.max_turns }} /></span>
        {remaining !== null && (
          <span className={remaining <= 5 ? 'mm-timer is-low' : 'mm-timer'}>
            <span className='mm-timer__bar'><motion.i animate={{ width: `${Math.min(100, (remaining / total) * 100)}%` }} transition={{ duration: 0.3 }} /></span>
            <b>{remaining}</b>
          </span>
        )}
        <span className='mm-chip'><FormattedMessage id='mm.goals' defaultMessage='Goals {done}/{total}' values={{ done: view.targets_done, total: view.targets_total }} /></span>
        {view.team && <span className={`mm-chip mm-chip--${view.team}`}>{names}</span>}
        {view.spectator && <span className='mm-chip mm-chip--dim'><FormattedMessage id='mm.spectating' defaultMessage='Spectating' /></span>}
        <button type='button' className='mm-exit' onClick={() => { history.push('/system/group'); }}><FormattedMessage id='mm.exit' defaultMessage='Exit' /></button>
      </header>

      {/* 지도 (양피지) */}
      <div className='mm-parchment'>
        <MapLegend view={view} />
        <div className='mm-board' style={{ aspectRatio: `${geo.width} / ${geo.height}` }}>
          <MapSvg view={view} geo={geo} reachable={reachable} here={here} planned={planned} pickingWatch={pickingWatch} draw={intro === 'oath' || (ending === 'none' && view.turn <= 1)} fade={ending === 'replay' || ending === 'result'} onPick={pick} />

          {/* 구역 공개(사감 팀): 대략적인 층/탑이 잉크로 번진다 */}
          {view.clues.filter((clue) => clue.kind === 'zone' && clue.zone && clue.age <= 3).map((clue) => {
            const zone = clue.zone as MZone;
            const rows = geo.rows;
            const style: React.CSSProperties = zone.kind === 'floor'
              ? { left: 0, width: '100%', top: `${((PAD + ((rows - 1 - (zone.y ?? 0)) * (CELL_H + GAP_Y)) - 14) / geo.height) * 100}%`, height: `${((CELL_H + 28) / geo.height) * 100}%` }
              : { top: 0, height: '100%', left: `${((PAD + ((zone.x ?? 0) * (CELL_W + GAP_X)) - 14) / geo.width) * 100}%`, width: `${((CELL_W + 28) / geo.width) * 100}%` };
            return (
              <motion.div key={`zone-${clue.turn}-${clue.seat}`} className='mm-zone' style={{ ...style, opacity: Math.max(0.18, 0.7 - (clue.age * 0.2)) }} initial={{ opacity: 0 }} animate={{ opacity: Math.max(0.18, 0.7 - (clue.age * 0.2)) }}>
                <NameTag player={byseat.get(clue.seat)} team='student' me={false} dim label={`${zone.name} 어딘가`} />
              </motion.div>
            );
          })}

          {/* 공개된 발자국(사감 팀)·내 흔적(학생 팀): 이름표와 함께 잉크 자국으로 남았다가 서서히 흐려진다 */}
          {view.clues.filter((clue) => (clue.kind === 'footprint' || clue.kind === 'watch') && clue.room !== undefined && clue.age <= 4).map((clue) => (
            <motion.div key={`mark-${clue.turn}-${clue.seat}-${clue.kind}`} className='mm-mark' style={pct(geo.center(clue.room ?? 0))} initial={{ opacity: 0, scale: 0.5 }} animate={{ opacity: Math.max(0.15, 1 - (clue.age * 0.28)), scale: 1 }}>
              <FootGlyph team='student' />
              <NameTag player={byseat.get(clue.seat)} team='student' me={clue.seat === view.me} dim={clue.age > 0} />
            </motion.div>
          ))}

          {view.clues.filter((clue) => clue.kind === 'scout' && clue.room !== undefined && clue.age <= 2).map((clue) => (
            <motion.div key={`scout-${clue.turn}-${clue.seat}`} className='mm-scout' style={pct(geo.center(clue.room ?? 0))} initial={{ scale: 0.2, opacity: 0.9 }} animate={{ scale: [0.2, 1, 1.15], opacity: [0.9, 0.7, Math.max(0.1, 0.6 - (clue.age * 0.25))] }} transition={{ duration: 1.4 }}>
              <span>👣 ×{clue.count}</span>
            </motion.div>
          ))}

          {/* 발자국 찍기 (이동·끌려감) */}
          {stamps.map((stamp) => (
            <motion.div key={stamp.id} className='mm-stamp' style={{ ...pct({ x: stamp.x, y: stamp.y }), rotate: stamp.angle }} initial={{ opacity: 0, scale: 0.4 }} animate={{ opacity: [0, 0.9, 0.9, 0], scale: [0.4, 1, 1, 1] }} transition={{ delay: stamp.delay, duration: 2.2 }}>
              <FootGlyph team={stamp.team} />
            </motion.div>
          ))}

          {/* 이름표 달린 발자국 토큰 */}
          {ending !== 'replay' && ending !== 'result' && view.tokens.map((token) => {
            const player = byseat.get(token.seat);
            const point = geo.center(token.room);
            const secret = view.last?.moves[String(token.seat)]?.secret;
            const arrested = dragged.has(token.seat);
            return (
              <motion.div
                key={token.seat}
                className={['mm-token', `mm-token--${token.team}`, token.status === 'jailed' && 'is-jailed', token.status === 'out' && 'is-out', token.seat === view.me && 'is-me'].filter(Boolean).join(' ')}
                initial={false}
                animate={{ left: pct(point).left, top: pct(point).top, opacity: secret ? [1, 0, 0, 1] : 1, rotate: arrested ? [0, -9, 9, -7, 7, 0] : 0 }}
                transition={{ left: { duration: arrested ? 2.4 : 1.1, delay: arrested ? 0.8 : 0.2 }, top: { duration: arrested ? 2.4 : 1.1, delay: arrested ? 0.8 : 0.2 }, opacity: { duration: 1.4 }, rotate: { duration: 0.7 } }}
              >
                <FootGlyph team={token.team} />
                <NameTag player={player} team={token.team} me={token.seat === view.me} label={token.status === 'jailed' ? '🔒' : token.status === 'out' ? '탈락' : undefined} />
              </motion.div>
            );
          })}

          {/* 전체 공개 말풍선 */}
          <AnimatePresence>
            {view.bubbles.map((bubble) => (
              <motion.div key={bubble.id} className='mm-bubble' style={pct(geo.center(bubble.room))} initial={{ opacity: 0, y: 10, scale: 0.8 }} animate={{ opacity: 1, y: -34, scale: 1 }} exit={{ opacity: 0 }} transition={{ duration: 0.3 }}>
                {bubble.text}
              </motion.div>
            ))}
          </AnimatePresence>

          {dimMask && (
            <>
              <motion.div key='dim' className='mm-dim' style={{ maskImage: dimMask, WebkitMaskImage: dimMask }} initial={{ opacity: 0 }} animate={{ opacity: 1 }} exit={{ opacity: 0 }} />
              <motion.p key='dim-text' className='mm-dim-text' initial={{ opacity: 0, y: -10 }} animate={{ opacity: 1, y: 0 }}>
                {pickingWatch ? <FormattedMessage id='mm.pick_watch' defaultMessage='Pick a room to watch.' /> : <FormattedMessage id='mm.pick_here' defaultMessage='Choose where to go!' />}
              </motion.p>
            </>
          )}

          {/* 끝난 뒤 리플레이 */}
          {(ending === 'replay' || ending === 'result') && <Replay view={view} geo={geo} />}
        </div>
      </div>

      {/* 아래: 상태 안내 + 아이템·능력 */}
      <div className='mm-dock'>
        <div className='mm-status'>
          {jailed && <p className='is-warn'><FormattedMessage id='mm.jailed' defaultMessage="You were caught and locked in Filch's office. You can only use the team chat until a teammate rescues you." /></p>}
          {out && <p className='is-warn'><FormattedMessage id='mm.out' defaultMessage='You were caught twice and are out. Watching the rest.' /></p>}
          {isPlayer && view.my_turn && view.submitted && view.status === 'active' && <p><FormattedMessage id='mm.waiting' defaultMessage='Waiting for: {names}' values={{ names: view.waiting.join(', ') || '…' }} /></p>}
          {view.log.length > 0 && <ul className='mm-log'>{view.log.slice(-4).map((line, index) => <li key={`${index}-${line}`}>{line}</li>)}</ul>}
        </div>
        {isPlayer && view.team === 'student' && !jailed && !out && (
          <button type='button' className='mm-button' disabled={!canAct || busy || (view.items.cloak ?? 0) <= 0 || Boolean(view.items.cloaked)} onClick={() => { send(view.commands.cloak); }}>
            <FormattedMessage id='mm.cloak' defaultMessage='Invisibility cloak ({count})' values={{ count: view.items.cloak ?? 0 }} />
          </button>
        )}
        {isPlayer && view.team === 'prefect' && view.role && (
          <button
            type='button'
            className='mm-button'
            disabled={!canAct || busy || !watchPending || view.chase}
            onClick={() => { if (view.role === 'watcher') setPickingWatch(true); else send(view.commands.ability); }}
          >
            {view.role === 'watcher' && <FormattedMessage id='mm.ability_watch' defaultMessage='Watch a room ({count})' values={{ count: view.items.ability ?? 0 }} />}
            {view.role === 'scout' && <FormattedMessage id='mm.ability_scout' defaultMessage='Scout ({count})' values={{ count: view.items.ability ?? 0 }} />}
            {view.role === 'chaser' && <FormattedMessage id='mm.ability_chase' defaultMessage='Chase: move 2 ({count})' values={{ count: view.items.ability ?? 0 }} />}
          </button>
        )}
      </div>

      <ChatDock sessionId={sessionId} chat={chat} team={view.team} canChat={isPlayer || staff} jailed={jailed} onSent={onChanged} />

      {/* 맹세 → 역할 안내 */}
      <AnimatePresence>
        {intro === 'oath' && <Oath key='oath' onDone={() => { finishIntro('role'); }} />}
        {intro === 'role' && view.team && <RoleModal key='role' view={view} onClose={() => { finishIntro('done'); }} />}
      </AnimatePresence>

      {/* 끝: 장난 끝 → 리플레이 → 결과 */}
      <AnimatePresence>
        {ending === 'over' && (
          <motion.div key='over' className='mm-over' initial={{ opacity: 0 }} animate={{ opacity: 1 }} exit={{ opacity: 0 }}>
            <motion.strong initial={{ scale: 2.6, opacity: 0, rotate: -6 }} animate={{ scale: 1, opacity: 1, rotate: -3 }} transition={{ type: 'spring', stiffness: 120, damping: 12 }}><FormattedMessage id='mm.mischief_over' defaultMessage='Mischief managed' /></motion.strong>
          </motion.div>
        )}
        {ending === 'replay' && (
          <motion.div key='replay-bar' className='mm-replay-bar' initial={{ opacity: 0 }} animate={{ opacity: 1 }} exit={{ opacity: 0 }}>
            <span><FormattedMessage id='mm.replay' defaultMessage='Where the students really went' /></span>
            <button type='button' className='mm-button' onClick={() => { setEnding('result'); }}><FormattedMessage id='mm.show_result' defaultMessage='Results' /></button>
          </motion.div>
        )}
        {ending === 'result' && view.finish && (
          <motion.div key='result' className='mm-result' initial={{ opacity: 0, y: 24 }} animate={{ opacity: 1, y: 0 }} exit={{ opacity: 0 }}>
            <h2>{view.winner === 'student' ? view.student_name : view.prefect_name} 팀 승리!</h2>
            <ul>
              {view.players.map((player) => {
                const reward = view.finish?.rewards[String(player.seat)];
                return (
                  <li key={player.seat} className={player.team === view.winner ? 'is-win' : undefined}>
                    <b>{player.name}</b>
                    <span>{player.team === 'student' ? view.student_name : view.prefect_name}</span>
                    {view.finish?.test ? <small><FormattedMessage id='mm.test' defaultMessage='Test play: no rewards' /></small> : reward && <small>{reward.points} pts{reward.money > 0 ? ` · ${reward.money} ${view.finish?.currency}` : ''}{reward.items.length > 0 ? ` · ${reward.items.join(', ')}` : ''}</small>}
                  </li>
                );
              })}
            </ul>
            <div className='mm-result__buttons'>
              <button type='button' className='mm-button mm-button--ghost' onClick={() => { setEnding('replay'); }}><FormattedMessage id='mm.see_replay' defaultMessage='Watch again' /></button>
              <button type='button' className='mm-button' onClick={() => { history.push('/system/group'); }}><FormattedMessage id='mm.leave' defaultMessage='Leave' /></button>
            </div>
          </motion.div>
        )}
      </AnimatePresence>
    </div>,
    document.body,
  );
};
