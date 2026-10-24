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
interface MPlayer { seat: number; name: string; account_id: string; acct?: string; avatar?: string | null; team: 'student' | 'prefect'; status: string | null; rescued: number; chosen?: boolean; cloaked?: boolean; ability?: { role: string | null; left: number } | null }
interface MLast {
  turn: number;
  moves: Record<string, { from: number; to: number; secret: boolean }>;
  arrests: { seat: number; by: number; room: number; out: boolean }[];
  rescued: number[];
  secret: number[];
  stairs: boolean;
  // 지도 위 그 자리에 띄울 소식 (서버 log 와 같은 글), 이번 턴에 이룬 목표 방 (사감에게는 방 없이 null)
  notes?: { kind: string; text: string; room?: number; zone?: MZone }[];
  goals?: (number | null)[];
}
interface MHistory { turn: number; positions: Record<string, number>; status_of?: Record<string, string>; arrests?: { seat: number; by: number; room: number; out: boolean }[]; rescued?: number[] }
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
  cloaks_left?: number | null;
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
  chatInfo: { id: 'mm.chat_info', defaultMessage: 'Info' },
  chatStudent: { id: 'mm.chat_student', defaultMessage: 'Students' },
  chatPrefect: { id: 'mm.chat_prefect', defaultMessage: 'Prefects' },
  placeholder: { id: 'mm.chat_placeholder', defaultMessage: 'Say something' },
  send: { id: 'mm.chat_send', defaultMessage: 'Send' },
});

const REFRESH_MS = 2_500;
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
        <pattern id='mm-hatch' width='8' height='8' patternUnits='userSpaceOnUse' patternTransform='rotate(45)'>
          <line x1='0' y1='0' x2='0' y2='8' stroke='#8a5a05' strokeWidth='2.2' opacity='0.75' />
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
            initial={draw ? { opacity: 0 } : false}
            animate={{ opacity: 0.85 }}
            transition={{ duration: 0.8, delay: draw ? 0.9 + ((index % 20) * 0.08) : 0 }}
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
              animate={open ? { opacity: 1 } : { opacity: 0.28 }}
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
            <rect x={box.x} y={box.y} width={box.w} height={box.h} rx={8} className='mm-room__base' />
            <rect x={box.x} y={box.y} width={box.w} height={box.h} rx={8} className='mm-room__shape' filter='url(#mm-ink)' />
            {isPlan && <rect x={box.x - 5} y={box.y - 5} width={box.w + 10} height={box.h + 10} rx={12} className='mm-room__ring' />}
            <rect x={box.x + 5} y={box.y + 5} width={box.w - 10} height={box.h - 10} rx={5} className='mm-room__inner' />
            <text x={box.x + (box.w / 2)} y={box.y + 27} textAnchor='middle' className='mm-room__name' textLength={Math.min(box.w - 24, room.name.length * 16)} lengthAdjust='spacingAndGlyphs'>{room.name}</text>
            {room.kind === 'office' && <SvgTIcon name='key' x={box.x + 10} y={box.y + 6} size={22} className='mm-room__icon' />}
            {target !== undefined && !target && <rect x={box.x + 5} y={box.y + 5} width={box.w - 10} height={box.h - 10} rx={5} className='mm-room__hatch' />}
            {target && <SvgTIcon name='check' x={box.x + box.w - 30} y={box.y + 6} size={22} className='mm-room__icon is-done' />}
          </motion.g>
        );
      })}
    </motion.svg>
  );
};

// ── Tabler 아이콘 (https://tabler.io/icons, MIT): 이모티콘 대신 쓰는 선 아이콘 ──
const TABLER: Record<string, string[]> = {
  volume: ['M15 8a5 5 0 0 1 0 8', 'M17.7 5a9 9 0 0 1 0 14', 'M6 15h-2a1 1 0 0 1 -1 -1v-4a1 1 0 0 1 1 -1h2l3.5 -4.5a.8 .8 0 0 1 1.5 .5v14a.8 .8 0 0 1 -1.5 .5l-3.5 -4.5'],
  'volume-off': ['M6 15h-2a1 1 0 0 1 -1 -1v-4a1 1 0 0 1 1 -1h2l3.5 -4.5a.8 .8 0 0 1 1.5 .5v14a.8 .8 0 0 1 -1.5 .5l-3.5 -4.5', 'M16 10l4 4m0 -4l-4 4'],
  'eye-off': ['M10.585 10.587a2 2 0 0 0 2.829 2.828', 'M16.681 16.673a8.717 8.717 0 0 1 -4.681 1.327c-3.6 0 -6.6 -2 -9 -6c1.272 -2.12 2.712 -3.678 4.32 -4.674m2.86 -1.146a9.055 9.055 0 0 1 1.82 -.18c3.6 0 6.6 2 9 6c-.666 1.11 -1.379 2.067 -2.138 2.87', 'M3 3l18 18'],
  lock: ['M5 13a2 2 0 0 1 2 -2h10a2 2 0 0 1 2 2v6a2 2 0 0 1 -2 2h-10a2 2 0 0 1 -2 -2v-6z', 'M11 16a1 1 0 1 0 2 0a1 1 0 0 0 -2 0', 'M8 11v-4a4 4 0 1 1 8 0v4'],
  key: ['M16.555 3.843l3.602 3.602a2.877 2.877 0 0 1 0 4.069l-2.643 2.643a2.877 2.877 0 0 1 -4.069 0l-.301 -.301l-6.558 6.558a2 2 0 0 1 -1.239 .578l-.175 .008h-1.172a1 1 0 0 1 -.993 -.883l-.007 -.117v-1.172a2 2 0 0 1 .467 -1.284l.119 -.13l.414 -.414h2v-2h2v-2l2.144 -2.144l-.301 -.301a2.877 2.877 0 0 1 0 -4.069l2.643 -2.643a2.877 2.877 0 0 1 4.069 0z'],
  check: ['M5 12l5 5l10 -10'],
  x: ['M18 6l-12 12', 'M6 6l12 12'],
  search: ['M3 10a7 7 0 1 0 14 0a7 7 0 1 0 -14 0', 'M21 21l-6 -6'],
  walk: ['M13 4m-1 0a1 1 0 1 0 2 0a1 1 0 1 0 -2 0', 'M7 21l3 -4', 'M16 21l-2 -4l-3 -3l1 -6', 'M6 12l2 -3l4 -1l3 3l3 1'],
  eye: ['M10 12a2 2 0 1 0 4 0a2 2 0 0 0 -4 0', 'M21 12c-2.4 4 -5.4 6 -9 6c-3.6 0 -6.6 -2 -9 -6c2.4 -4 5.4 -6 9 -6c3.6 0 6.6 2 9 6'],
  'info-circle': ['M3 12a9 9 0 1 0 18 0a9 9 0 0 0 -18 0', 'M12 9h.01', 'M11 12h1v4h1'],
  users: ['M9 7m-4 0a4 4 0 1 0 8 0a4 4 0 1 0 -8 0', 'M3 21v-2a4 4 0 0 1 4 -4h4a4 4 0 0 1 4 4v2', 'M16 3.13a4 4 0 0 1 0 7.75', 'M21 21v-2a4 4 0 0 0 -3 -3.85'],
};

const TIcon: React.FC<{ name: string; size?: number; className?: string }> = ({ name, size = 16, className }) => (
  <svg className={['mm-ti', className].filter(Boolean).join(' ')} width={size} height={size} viewBox='0 0 24 24' fill='none' stroke='currentColor' strokeWidth='2' strokeLinecap='round' strokeLinejoin='round' aria-hidden>
    {(TABLER[name] ?? []).map((d) => <path key={d} d={d} />)}
  </svg>
);

// SVG 안(지도)에 그리는 아이콘
const SvgTIcon: React.FC<{ name: string; x: number; y: number; size?: number; className?: string }> = ({ name, x, y, size = 20, className }) => (
  <g transform={`translate(${x} ${y}) scale(${size / 24})`} className={className} fill='none' stroke='currentColor' strokeWidth='2.2' strokeLinecap='round' strokeLinejoin='round'>
    {(TABLER[name] ?? []).map((d) => <path key={d} d={d} />)}
  </g>
);

// ── 지도 양 옆 팀 열: 아바타 · 이름 · 배지(선택 완료·갇힘·망토·남은 능력) ──
const TeamSide: React.FC<{ view: MView; team: 'student' | 'prefect' }> = ({ view, team }) => (
  <ul className={`mm-side mm-side--${team}`}>
    {team === 'student' && view.cloaks_left != null && <li className='mm-side__cloaks' title='cloaks'><TIcon name='eye-off' size={14} /> ×{view.cloaks_left}</li>}
    {view.players.filter((player) => player.team === team).map((player) => (
      <li key={player.seat} className={['mm-side__player', player.chosen && 'is-chosen', player.status === 'jailed' && 'is-jailed', player.status === 'out' && 'is-out', player.seat === view.me && 'is-me'].filter(Boolean).join(' ')}>
        {player.avatar ? <img src={player.avatar} alt='' /> : <span className='mm-side__noimg' />}
        <b>{player.name}</b>
        <span className='mm-side__badges'>
          {view.status === 'active' && player.chosen && <i title='choice done'><TIcon name='check' size={12} /></i>}
          {player.cloaked && <i title='invisible'><TIcon name='eye-off' size={12} /></i>}
          {player.status === 'jailed' && <i><TIcon name='lock' size={12} /></i>}
          {player.status === 'out' && <i><TIcon name='x' size={12} /></i>}
          {player.ability && <i title={player.role ?? ''}><TIcon name={player.role === 'watcher' ? 'eye' : player.role === 'scout' ? 'search' : 'walk'} size={12} />×{player.ability.left}</i>}
        </span>
      </li>
    ))}
  </ul>
);

// ── 이름표 달린 발자국 토큰 ──
const NameTag: React.FC<{ player: MPlayer | undefined; team: 'student' | 'prefect'; me: boolean; dim?: boolean; label?: React.ReactNode; cloaked?: boolean }> = ({ player, team, me, dim, label, cloaked }) => (
  <motion.span
    className={['mm-tag', `mm-tag--${(player?.seat ?? 0) % 6}`, team === 'prefect' && 'is-prefect', me && 'is-me', dim && 'is-dim'].filter(Boolean).join(' ')}
    animate={{ y: [0, -5, 0] }}
    transition={{ duration: 2.4 + ((player?.seat ?? 0) % 3) * 0.4, repeat: Infinity, ease: 'easeInOut' }}
  >
    {player?.avatar && <img src={player.avatar} alt='' />}
    <b>{player?.name ?? '?'}</b>
    {cloaked && <i className='mm-tag__cloak' title='invisible'><TIcon name='eye-off' size={15} /></i>}
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

// 발자국 한 짝 (왼발·오른발)
const StepGlyph: React.FC<{ team: 'student' | 'prefect'; side: 1 | -1 }> = ({ team, side }) => (
  <svg className={`mm-foot mm-foot--${team} mm-foot--step`} viewBox='0 0 16 26' style={{ transform: side < 0 ? 'scaleX(-1)' : undefined }} aria-hidden>
    <Shoe x={8} y={13} rot={0} />
  </svg>
);

// 걸어간 자리: 길(복도·계단)을 따라 왼발·오른발이 번갈아 찍힌다
const stepsAlong = (from: { x: number; y: number }, to: { x: number; y: number }, key: string, team: 'student' | 'prefect', delayBase: number, gap = 0.2): Stamp[] => {
  const dx = to.x - from.x;
  const dy = to.y - from.y;
  const length = Math.hypot(dx, dy) || 1;
  const count = Math.max(4, Math.min(14, Math.round(length / 34)));
  const angle = (Math.atan2(dy, dx) * 180) / Math.PI + 90;
  return Array.from({ length: count }, (_, index) => {
    const t = (index + 0.5) / count;
    const side: 1 | -1 = index % 2 === 0 ? 1 : -1;
    return { id: `${key}-${index}`, x: from.x + (dx * t) + ((-dy / length) * 9 * side), y: from.y + (dy * t) + ((dx / length) * 9 * side), team, delay: delayBase + (index * gap), angle, side };
  });
};

const FootGlyph: React.FC<{ team: 'student' | 'prefect' }> = ({ team }) => (
  <svg className={`mm-foot mm-foot--${team}`} viewBox='0 0 38 26' aria-hidden>
    <Shoe x={11} y={12} rot={-8} />
    <Shoe x={27} y={14} rot={8} />
  </svg>
);

interface Stamp { id: string; x: number; y: number; team: 'student' | 'prefect'; delay: number; angle: number; side: 1 | -1 }

// ── 범례: 지도에 그려진 것이 무엇인지 ──
const LegendSample: React.FC<{ children: React.ReactNode }> = ({ children }) => (
  <svg className='mm-legend__sample' viewBox='0 0 44 20' aria-hidden>{children}</svg>
);

const MapLegend: React.FC<{ view: MView }> = ({ view }) => {
  const every = view.map.stairs_every;
  const left = every - ((view.turn - 1) % every);
  // 지도 안내는 접었다 펼 수 있다
  const [open, setOpen] = useState(true);
  return (
    <div className='mm-legends'>
    <aside className={open ? 'mm-legend' : 'mm-legend is-closed'} aria-label='legend'>
      <button type='button' className='mm-legend__toggle' aria-expanded={open} onClick={() => { setOpen((value) => !value); }}>
        <h4><FormattedMessage id='mm.legend' defaultMessage='Map key' /></h4>
        <span aria-hidden>{open ? '▾' : '▸'}</span>
      </button>
      {open && <ul>
        <li><LegendSample><line x1='3' y1='10' x2='41' y2='10' className='mm-road-outer' /><line x1='3' y1='10' x2='41' y2='10' className='mm-road-inner' /></LegendSample><FormattedMessage id='mm.legend_corridor' defaultMessage='Corridor' /></li>
        <li><LegendSample><line x1='3' y1='10' x2='41' y2='10' className='mm-stairs' /></LegendSample><FormattedMessage id='mm.legend_stairs' defaultMessage='Stairs (between floors)' /></li>
        <li><LegendSample><line x1='3' y1='10' x2='41' y2='10' className='mm-stairs mm-stairs--open' /></LegendSample><span><FormattedMessage id='mm.legend_moving' defaultMessage='Moving stairs (open now)' /> <small><FormattedMessage id='mm.legend_moving_note' defaultMessage='Switch every {every} turns, next in {left}' values={{ every, left }} /></small></span></li>
        <li><LegendSample><line x1='3' y1='10' x2='41' y2='10' className='mm-stairs mm-stairs--closed' /></LegendSample><FormattedMessage id='mm.legend_closed' defaultMessage='Moving stairs (closed now)' /></li>
        {view.secret.length > 0 && <li><LegendSample><path d='M3 14 Q22 -4 41 14' className='mm-passage' /><text x='34' y='9' className='mm-door'>✦</text></LegendSample><FormattedMessage id='mm.legend_secret' defaultMessage='Secret passage (students only)' /></li>}
        {view.targets.length > 0 && <li><LegendSample><rect x='6' y='2' width='32' height='16' rx='3' className='mm-room__shape is-goal-sample' /><rect x='9' y='5' width='26' height='10' rx='2' className='mm-room__hatch is-sample' /></LegendSample><FormattedMessage id='mm.legend_goal' defaultMessage='Goal place' /></li>}
        <li><LegendSample><rect x='6' y='2' width='32' height='16' rx='3' className='mm-legend__office' /><SvgTIcon name='key' x={8} y={3} size={14} className='mm-room__icon' /></LegendSample><FormattedMessage id='mm.legend_office' defaultMessage="Filch's office (jail)" /></li>
        <li><LegendSample><rect x='6' y='2' width='32' height='16' rx='3' className='mm-legend__tower' /></LegendSample><FormattedMessage id='mm.legend_tower' defaultMessage='Tower room' /></li>
        <li><span className='mm-legend__feet'><FootGlyph team='student' /></span><FormattedMessage id='mm.legend_foot' defaultMessage='Footprints = where someone is (ribbon = name)' /></li>
      </ul>}
    </aside>
    </div>
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

// ── 효과음: 웹 오디오로 바로 만든다 (파일 없음). 머리 줄의 소리 버튼으로 끄고, 브라우저가 막으면 조용히 넘어간다 ──
const SOUND_KEY = 'ssm:mm-sound';
let audioContext: AudioContext | null = null;

const soundOn = () => {
  try {
    return window.localStorage.getItem(SOUND_KEY) !== 'off';
  } catch {
    return true;
  }
};

const audio = () => {
  if (!soundOn()) return null;
  try {
    const Context = window.AudioContext ?? (window as unknown as { webkitAudioContext?: typeof AudioContext }).webkitAudioContext;
    if (!Context) return null;
    audioContext ??= new Context();
    if (audioContext.state === 'suspended') void audioContext.resume();
    return audioContext;
  } catch {
    return null;
  }
};

// 소리 하나: at 초 뒤에 length 초 동안 (to 가 있으면 그 높이로 미끄러진다)
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

// 짧은 잡음 (발소리·계단 긁히는 소리)
const noise = (at: number, length: number, volume: number, frequency: number) => {
  const context = audio();
  if (!context) return;
  const start = context.currentTime + at;
  const buffer = context.createBuffer(1, Math.ceil(context.sampleRate * length), context.sampleRate);
  const data = buffer.getChannelData(0);
  for (let index = 0; index < data.length; index += 1) data[index] = (Math.random() * 2 - 1) * (1 - index / data.length);
  const source = context.createBufferSource();
  source.buffer = buffer;
  const filter = context.createBiquadFilter();
  filter.type = 'bandpass';
  filter.frequency.value = frequency;
  const gain = context.createGain();
  gain.gain.value = volume;
  source.connect(filter);
  filter.connect(gain);
  gain.connect(context.destination);
  source.start(start);
};

const sfx = {
  // 체포: 둔탁한 타격음
  thump: () => { tone(140, 0, 0.35, { type: 'triangle', volume: 0.5, to: 40 }); },
  // 내 차례: 두 음 종소리
  turn: () => { tone(660, 0, 0.3, { volume: 0.18 }); tone(990, 0.14, 0.45, { volume: 0.16 }); },
  // 소식이 뜰 때
  note: (at = 0) => { tone(520, at, 0.14, { type: 'triangle', volume: 0.12 }); },
  // 발소리 한 번
  step: (at = 0) => { noise(at, 0.08, 0.5, 700); },
  // 계단이 움직인다: 낮게 긁히는 소리
  stairs: (at = 0) => { tone(95, at, 1.1, { type: 'sawtooth', volume: 0.08, to: 55 }); noise(at, 1, 0.25, 260); },
  // 목표 장소: 올라가는 화음
  goal: (at = 0) => { [523, 659, 784, 1047].forEach((freq, index) => { tone(freq, at + (index * 0.09), 0.45, { volume: 0.16 }); }); },
  // 투옥: 타격음 + 철창 닫히는 소리
  jail: (at = 0) => { tone(140, at, 0.35, { type: 'triangle', volume: 0.45, to: 40 }); tone(220, at + 0.25, 0.5, { type: 'square', volume: 0.06, to: 110 }); },
  // 탈출(구출): 위로 솟는 소리
  escape: (at = 0) => { tone(330, at, 0.6, { type: 'triangle', volume: 0.18, to: 880 }); tone(1320, at + 0.45, 0.35, { volume: 0.1 }); },
  // 새 채팅
  message: () => { tone(880, 0, 0.1, { volume: 0.08 }); tone(1175, 0.08, 0.14, { volume: 0.07 }); },
};
const thump = sfx.thump;

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
  const [page, setPage] = useState<'role' | 'how'>('role');
  const key = view.team === 'student' ? 'student' : (view.role ?? 'chaser');
  const info = ROLE_LINES[key] ?? ROLE_LINES.chaser;
  if (!info) return null;
  return (
    <motion.div className='mm-modal' initial={{ opacity: 0 }} animate={{ opacity: 1 }} exit={{ opacity: 0 }}>
      <motion.div key={page} className='mm-modal__card' initial={{ y: 30, scale: 0.92, rotate: -1.5 }} animate={{ y: 0, scale: 1, rotate: 0 }} transition={{ type: 'spring', stiffness: 160, damping: 16 }}>
        <small>{view.team === 'student' ? view.student_name : view.prefect_name} 팀 · {page === 'role' ? '1' : '2'} / 2</small>
        {page === 'role' ? (
          <>
            <h2>{info.title}</h2>
            {info.lines.map((line) => <p key={line}>{line}</p>)}
            <ul>
              {info.items.map((item) => <li key={item.name}><strong>{item.name}</strong> {item.text}</li>)}
            </ul>
          </>
        ) : (
          <>
            <h2>갈 곳 고르기</h2>
            {/* 실제 지도와 같은 빛나는 방 */}
            <svg className='mm-modal__room' viewBox='0 0 200 70' aria-hidden>
              <g className='mm-room is-go'><rect x='60' y='10' width='80' height='46' rx='8' className='mm-room__shape' /><rect x='65' y='15' width='70' height='36' rx='5' className='mm-room__inner' /></g>
            </svg>
            <p>내 차례가 되면 내 이름표 아래에 안내가 뜨고, 지도에서 <strong>빛나는 방</strong>이 갈 수 있는 곳이 됩니다. 눌러서 고르세요. 지금 있는 방을 누르면 제자리입니다.</p>
            <p>모두 고르면 한꺼번에 움직입니다. 제한 시간 안에 고르지 않으면 제자리에 있습니다.</p>
            <p>{view.team === 'student' ? '투명 망토는 이동 안내 옆의 버튼으로 씁니다.' : '능력은 이동 안내 옆의 버튼으로 씁니다.'}</p>
          </>
        )}
        <div className='mm-modal__actions'>
          {page === 'role'
            ? <button type='button' className='mm-button' onClick={() => { setPage('how'); }}>다음</button>
            : (
              <>
                <button type='button' className='mm-button mm-button--ghost' onClick={() => { setPage('role'); }}>이전</button>
                <button type='button' className='mm-button' onClick={onClose}>시작하기</button>
              </>
            )}
        </div>
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
type ChatTab = 'all' | 'info' | 'student' | 'prefect';

const ChatDock: React.FC<{
  sessionId: string;
  chat: MmChatMessage[];
  team: 'student' | 'prefect' | null;
  canChat: boolean;
  jailed: boolean;
  infos: { id: string; text: string }[];
  onSent: () => void;
}> = ({ sessionId, chat, team, canChat, jailed, infos, onSent }) => {
  const intl = useIntl();
  // 탭: 구경하는 사람은 전체·학생·사감, 학생은 전체·학생, 사감은 전체·사감
  // (정보 탭은 모든 사람에게 보인다)
  const tabs: ChatTab[] = team ? ['all', 'info', team] : ['all', 'info', 'student', 'prefect'];
  const [channel, setChannel] = useState<ChatTab>(jailed && team ? team : 'all');
  const [text, setText] = useState('');
  const listRef = useRef<HTMLUListElement>(null);
  // 전체 탭에는 모든 채팅이 올라온다 (팀 채팅은 앞에 [학생]/[사감] 표시)
  const shown = channel === 'info' ? [] : chat.filter((message) => (channel === 'all' ? true : message.team === channel));
  const shownInfos = channel === 'all' || channel === 'info' ? infos : [];
  // 안 본 메시지 수 (보고 있는 탭은 0). 다른 사람의 새 채팅은 짧은 소리
  const counts: Record<ChatTab, number> = { all: chat.length + infos.length, info: infos.length, student: chat.filter((message) => message.team === 'student').length, prefect: chat.filter((message) => message.team === 'prefect').length };
  const seen = useRef<Record<ChatTab, number>>({ ...counts });
  seen.current[channel] = counts[channel];
  const unread = (tab: ChatTab) => Math.max(0, counts[tab] - seen.current[tab]);
  const others = chat.filter((message) => !message.mine).length;
  const heard = useRef(others);
  useEffect(() => {
    if (others > heard.current) sfx.message();
    heard.current = others;
  }, [others]);
  const label = (tab: ChatTab) => (tab === 'all' ? intl.formatMessage(messages.chatAll) : tab === 'info' ? intl.formatMessage(messages.chatInfo) : intl.formatMessage(tab === 'student' ? messages.chatStudent : messages.chatPrefect));

  useEffect(() => {
    if (listRef.current) listRef.current.scrollTop = listRef.current.scrollHeight;
  }, [shown.length, shownInfos.length, channel]);

  const submit = useCallback((event: React.FormEvent) => {
    event.preventDefault();
    const value = text.trim();
    if (!value) return;
    setText('');
    apiRequestPost(`v1/system/sessions/${sessionId}/chat`, { text: value, channel: channel === 'all' ? 'all' : 'team' })
      .then(() => { onSent(); return true; })
      .catch(() => { onSent(); });
  }, [sessionId, text, channel, onSent]);

  return (
    <section className='mm-chat'>
      <div className='mm-chat__tabs'>
        {tabs.map((tab) => (
          <button key={tab} type='button' className={[`is-${tab}`, channel === tab && 'is-on'].filter(Boolean).join(' ')} onClick={() => { setChannel(tab); }}>
            {label(tab)}
            {channel !== tab && unread(tab) > 0 && <b className='mm-chat__badge'>{unread(tab) > 99 ? '99+' : unread(tab)}</b>}
          </button>
        ))}
      </div>
      <ul ref={listRef} className='mm-chat__list'>
        {shownInfos.map((info) => (
          <li key={info.id} className='is-info'>
            <em className='mm-chat__tag is-info'>[{label('info')}]</em>
            <span>{info.text}</span>
          </li>
        ))}
        {shown.map((message) => (
          <li key={message.id} className={message.mine ? 'is-mine' : undefined}>
            {channel === 'all' && <em className={`mm-chat__tag is-${message.team ?? 'all'}`}>[{label(message.team ?? 'all')}]</em>}
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

// ── 끝: 라운드별로 다시 보기 / 경로만 보기 ──
const PATH_COLORS = ['#1f4e9a', '#9a2a2a', '#2a7a46', '#8a5a14', '#6a2fa0', '#157a85', '#a07a14', '#8a2f66', '#444444', '#c0561b'];

const routeColor = (view: MView, seat: number) => PATH_COLORS[Math.max(view.players.findIndex((player) => player.seat === seat), 0) % PATH_COLORS.length] ?? '#444444';

// 지도 위에 사람마다 실제로 지나간 길을 점선 발자국으로 그린다 (지도는 그대로 보인다)
const RoutesLayer: React.FC<{ view: MView; geo: Geometry; seats: number[] }> = ({ view, geo, seats }) => {
  const history = view.history ?? [];
  return (
    <svg className='mm-replay' viewBox={`0 0 ${geo.width} ${geo.height}`} aria-hidden>
      {seats.map((seat, order) => {
        const rooms = history.map((entry) => entry.positions[String(seat)]).filter((room): room is number => room !== undefined);
        const trail = rooms.filter((room, index) => index === 0 || room !== rooms[index - 1]);
        if (trail.length === 0) return null;
        const shift = ((order % 5) - 2) * 4;
        const points = trail.map((room) => geo.center(room)).map((point) => ({ x: point.x + shift, y: point.y + shift }));
        const d = points.map((point, index) => `${index === 0 ? 'M' : 'L'} ${point.x} ${point.y}`).join(' ');
        const color = routeColor(view, seat);
        const last = points[points.length - 1] ?? points[0];
        const first = points[0];
        if (!first || !last) return null;
        return (
          <g key={seat}>
            {points.length > 1 && <motion.path d={d} fill='none' stroke={color} strokeWidth={7} strokeLinecap='round' strokeLinejoin='round' strokeDasharray='1 12' initial={{ pathLength: 0 }} animate={{ pathLength: 1 }} transition={{ duration: 1.8 }} />}
            <circle cx={first.x} cy={first.y} r={9} fill='#fff8e2' stroke={color} strokeWidth={4} />
            <circle cx={last.x} cy={last.y} r={9} fill={color} stroke='#fff8e2' strokeWidth={3} />
          </g>
        );
      })}
    </svg>
  );
};

const ReviewBar: React.FC<{
  view: MView;
  mode: 'rounds' | 'routes';
  round: number;
  playing: boolean;
  seats: number[];
  onMode: (mode: 'rounds' | 'routes') => void;
  onRound: (round: number) => void;
  onPlay: () => void;
  onSeat: (seat: number) => void;
  onResult: () => void;
}> = ({ view, mode, round, playing, seats, onMode, onRound, onPlay, onSeat, onResult }) => {
  const history = view.history ?? [];
  const last = Math.max(history.length - 1, 0);
  const entry = history[round];
  const byseat = new Map(view.players.map((player) => [player.seat, player]));
  const name = (seat: number) => byseat.get(seat)?.name ?? '?';
  const notes = [
    ...(entry?.arrests ?? []).map((arrest) => `${name(arrest.by)} → ${name(arrest.seat)} 체포${arrest.out ? ' (탈락)' : ''}`),
    ...((entry?.rescued ?? []).length > 0 ? [`구출: ${(entry?.rescued ?? []).map(name).join(', ')}`] : []),
  ];

  return (
    <motion.div className='mm-review' initial={{ opacity: 0, y: 16 }} animate={{ opacity: 1, y: 0 }} exit={{ opacity: 0 }}>
      <div className='mm-review__row'>
        <span className='mm-review__label'>{mode === 'rounds' ? <FormattedMessage id='mm.review_rounds' defaultMessage='Rounds' /> : <FormattedMessage id='mm.review_routes' defaultMessage='Routes' />}</span>
        {mode === 'rounds' ? (
          <>
            {history.map((each, index) => (
              <button key={each.turn} type='button' className={index === round ? 'is-on' : undefined} onClick={() => { onRound(index); }}>
                {index === 0 ? <FormattedMessage id='mm.review_start' defaultMessage='Start' /> : index}
              </button>
            ))}
            <button type='button' className='mm-review__play' onClick={onPlay}>
              {playing ? <FormattedMessage id='mm.review_pause' defaultMessage='Pause' /> : <FormattedMessage id='mm.review_play' defaultMessage='Play' />}
            </button>
          </>
        ) : (
          view.players.map((player) => (
            <button key={player.seat} type='button' className={seats.includes(player.seat) ? 'is-on' : undefined} style={{ '--route': routeColor(view, player.seat) } as React.CSSProperties} onClick={() => { onSeat(player.seat); }}>
              <i />{player.name}
            </button>
          ))
        )}
        <span className='mm-review__spacer' />
        <button type='button' className={mode === 'routes' ? 'mm-review__mode is-on' : 'mm-review__mode'} onClick={() => { onMode(mode === 'routes' ? 'rounds' : 'routes'); }}>
          {mode === 'routes' ? <FormattedMessage id='mm.review_by_round' defaultMessage='By round' /> : <FormattedMessage id='mm.review_routes_only' defaultMessage='Routes only' />}
        </button>
        <button type='button' className='mm-review__mode' onClick={onResult}><FormattedMessage id='mm.show_result' defaultMessage='Results' /></button>
      </div>
      {mode === 'rounds' && <p className='mm-review__note'>{round === 0 ? '출발 위치' : `${round}/${last}라운드`}{notes.length > 0 ? ` · ${notes.join(' · ')}` : ''}</p>}
    </motion.div>
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
  // 소식(누가 어디 있는지·계단 변화 등): 지도 위에 잠깐 떴다 사라지고, 채팅의 [정보]로 남는다
  const [infos, setInfos] = useState<{ id: string; text: string }[]>([]);
  const [toasts, setToasts] = useState<{ id: string; text: string }[]>([]);
  const seenInfo = useRef<Set<string> | null>(null);
  // pending: 아직 모름 (첫 화면을 받기 전). 대기실 카운트다운이 끝나고 들어오면 지도를 먼저 보여 주지 않고 바로 맹세(오프닝)부터
  const [intro, setIntro] = useState<'pending' | 'oath' | 'role' | 'done'>('pending');
  const [pickingWatch, setPickingWatch] = useState(false);
  const [ending, setEnding] = useState<'none' | 'over' | 'review' | 'result'>('none');
  // 끝난 뒤 복기: 라운드별 / 경로만, 보고 있는 라운드, 자동 재생, 경로로 보여 줄 사람
  const [reviewMode, setReviewMode] = useState<'rounds' | 'routes'>('rounds');
  const [reviewRound, setReviewRound] = useState(0);
  const [playing, setPlaying] = useState(false);
  const [routeSeats, setRouteSeats] = useState<number[] | null>(null);
  const [busy, setBusy] = useState(false);
  const seenLast = useRef<number>(-1);
  // 지도 위 그 자리에 잠깐 떴다 사라지는 소식·효과 (목표·투옥·탈출), 계단이 움직이는 중
  const [notes, setNotes] = useState<{ id: string; kind: string; text: string; x: number; y: number; delay: number }[]>([]);
  const [bursts, setBursts] = useState<{ id: string; kind: 'goal' | 'jail' | 'escape'; x: number; y: number; delay: number; label: string }[]>([]);
  const [stairsShift, setStairsShift] = useState(false);
  const [sound, setSound] = useState(soundOn);
  const toggleSound = useCallback(() => {
    setSound((current) => {
      try { window.localStorage.setItem(SOUND_KEY, current ? 'off' : 'on'); } catch { /* 저장이 막혀도 이번에는 바뀐다 */ }
      return !current;
    });
  }, []);
  const askedTurn = useRef<number>(-1);

  useEffect(() => {
    if (!view) return undefined;
    const lines = view.log.map((text, index) => ({ id: `${view.turn}-${index}-${text}`, text }));
    const first = seenInfo.current === null;
    const known = seenInfo.current ?? new Set<string>();
    const fresh = lines.filter((line) => !known.has(line.id));
    if (fresh.length === 0) return undefined;
    fresh.forEach((line) => known.add(line.id));
    seenInfo.current = known;
    setInfos((current) => [...current, ...fresh].slice(-60));
    if (first) return undefined;
    const placed = new Set((view.last?.notes ?? []).map((note) => note.text));
    const loose = fresh.filter((line) => !placed.has(line.text));
    if (loose.length === 0) return undefined;
    setToasts((current) => [...current, ...loose]);
    const timer = window.setTimeout(() => { setToasts((current) => current.filter((toast) => !loose.some((line) => line.id === toast.id))); }, 6_000);
    return () => { window.clearTimeout(timer); };
  }, [view]);
  const introChecked = useRef(false);
  // 맹세가 끝날 때 가장 최근 화면 (팀을 보고 역할 안내를 띄운다)
  const viewRef = useRef<MView | null>(null);
  viewRef.current = view;
  const stageRef = useRef<HTMLDivElement>(null);

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
    // 구경하는 사람도 맹세로 시작한다 (역할 안내는 팀이 있는 사람만)
    if (view.status !== 'active' || (!view.team && view.turn > 1)) {
      setIntro('done');
      return;
    }
    let seen = false;
    try {
      seen = window.sessionStorage.getItem(`ssm:mm-intro:${sessionId}`) === '1';
    } catch {
      seen = false;
    }
    setIntro(seen ? 'done' : view.turn <= 1 ? 'oath' : view.team ? 'role' : 'done');
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
      next.push(...stepsAlong(from, to, `${last.turn}-${seat}`, player?.team ?? 'student', 0.1));
    });
    last.arrests.forEach((arrest) => {
      const from = geo.center(arrest.room);
      const to = geo.center(view.map.office);
      next.push(...stepsAlong(from, to, `${last.turn}-a${arrest.seat}`, 'student', 0.9, 0.24));
    });
    setStamps(next);
    // 발소리: 찍히는 발자국에 맞춰 (너무 많으면 앞의 것만)
    next.slice(0, 18).forEach((stamp) => { sfx.step(stamp.delay); });

    // 소식: 방이면 그 방, 층·탑 구역이면 그 띠 가운데, 계단은 지도 위쪽. 같은 자리에 겹치면 위로 쌓는다
    const zoneCenter = (zone: MZone) => (zone.kind === 'floor'
      ? { x: geo.width / 2, y: PAD + ((geo.rows - 1 - (zone.y ?? 0)) * (CELL_H + GAP_Y)) + (CELL_H / 2) }
      : { x: PAD + ((zone.x ?? 0) * (CELL_W + GAP_X)) + (CELL_W / 2), y: geo.height / 2 });
    const stacked = new Map<string, number>();
    const placed = (last.notes ?? []).map((note, index) => {
      const point = note.room !== undefined ? geo.center(note.room) : note.zone ? zoneCenter(note.zone) : { x: geo.width / 2, y: geo.height * 0.12 };
      const spot = `${Math.round(point.x)}:${Math.round(point.y)}`;
      const level = stacked.get(spot) ?? 0;
      stacked.set(spot, level + 1);
      return { id: `${last.turn}-n${index}`, kind: note.kind, text: note.text, x: point.x, y: point.y - (level * 34), delay: 1.2 + (index * 0.7) };
    });
    setNotes(placed);
    placed.forEach((note) => { if (note.kind !== 'stairs' && note.kind !== 'caught') sfx.note(note.delay); });

    // 목표 장소 · 투옥 · 탈출 효과
    const effects: { id: string; kind: 'goal' | 'jail' | 'escape'; x: number; y: number; delay: number; label: string }[] = [];
    (last.goals ?? []).forEach((room, index) => {
      const point = room === null ? { x: geo.width / 2, y: geo.height * 0.3 } : geo.center(room);
      effects.push({ id: `${last.turn}-g${index}`, kind: 'goal', x: point.x, y: point.y, delay: 1.3 + (index * 0.4), label: '목표 달성!' });
      sfx.goal(1.3 + (index * 0.4));
    });
    if (last.arrests.length > 0) {
      const office = geo.center(view.map.office);
      effects.push({ id: `${last.turn}-jail`, kind: 'jail', x: office.x, y: office.y, delay: 2.8, label: last.arrests.some((arrest) => arrest.out) ? '탈락!' : '투옥!' });
      window.setTimeout(thump, 500);
      sfx.jail(2.8);
    }
    if (last.rescued.length > 0) {
      const office = geo.center(view.map.office);
      effects.push({ id: `${last.turn}-esc`, kind: 'escape', x: office.x, y: office.y, delay: 1.4, label: '탈출!' });
      sfx.escape(1.4);
    }
    setBursts(effects);
    if (last.stairs) {
      setStairsShift(true);
      sfx.stairs(0.6);
    }
    const timer = window.setTimeout(() => { setStamps([]); }, 3_800);
    const clear = window.setTimeout(() => { setNotes([]); setBursts([]); setStairsShift(false); }, 2_000 + (Math.max(placed.length, 1) * 700) + 5_000);
    return () => { window.clearTimeout(timer); window.clearTimeout(clear); };
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
    const timer = window.setTimeout(() => { setEnding('review'); setReviewMode('rounds'); setReviewRound(0); setPlaying(true); }, 3_200);
    return () => { window.clearTimeout(timer); };
  }, [ending]);

  // 복기 자동 재생: 1.8초마다 다음 라운드로
  const lastRound = Math.max((view?.history?.length ?? 1) - 1, 0);
  useEffect(() => {
    if (!playing || ending !== 'review' || reviewMode !== 'rounds') return undefined;
    const timer = window.setInterval(() => {
      setReviewRound((current) => {
        if (current >= lastRound) {
          setPlaying(false);
          return current;
        }
        return current + 1;
      });
    }, 1_800);
    return () => { window.clearInterval(timer); };
  }, [playing, ending, reviewMode, lastRound]);

  // 복기 중 라운드가 바뀌면 그 라운드의 이동을 발자국으로 찍는다 (체포는 사무실까지 끌려간다)
  useEffect(() => {
    if (!view || ending !== 'review' || reviewMode !== 'rounds' || reviewRound <= 0) return undefined;
    const entry = view.history?.[reviewRound];
    const prev = view.history?.[reviewRound - 1];
    if (!entry || !prev) return undefined;
    const next: Stamp[] = [];
    Object.entries(entry.positions).forEach(([seat, room]) => {
      const before = prev.positions[seat];
      if (before === undefined || before === room) return;
      const player = view.players.find((each) => String(each.seat) === seat);
      next.push(...stepsAlong(geo.center(before), geo.center(room), `r${reviewRound}-${seat}`, player?.team ?? 'student', 0.1));
    });
    (entry.arrests ?? []).forEach((arrest) => {
      next.push(...stepsAlong(geo.center(arrest.room), geo.center(view.map.office), `r${reviewRound}-a${arrest.seat}`, 'student', 0.9, 0.24));
    });
    setStamps(next);
    const timer = window.setTimeout(() => { setStamps([]); }, 3_400);
    return () => { window.clearTimeout(timer); };
  }, [view, geo, ending, reviewMode, reviewRound]);

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

  const selecting = Boolean(view && (pickingWatch || (isPlayer && view.my_turn && !view.submitted && view.moves.length > 0)));
  const turnNow = view?.turn ?? -1;
  useEffect(() => {
    if (!selecting || intro !== 'done' || askedTurn.current === turnNow) return;
    askedTurn.current = turnNow;
    sfx.turn();
  }, [selecting, intro, turnNow]);

  // 첫 화면을 받기 전·맹세를 할지 정하기 전에는 빈 무대만 (지도가 잠깐 보였다가 오프닝이 덮지 않게)
  if (!view || intro === 'pending') return createPortal(<div className='game-stage mm-stage' role='region' aria-label={name} />, document.body);

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

  const pct = (point: { x: number; y: number }) => ({ left: `${(point.x / geo.width) * 100}%`, top: `${(point.y / geo.height) * 100}%` });
  const dragged = new Set((view.last?.arrests ?? []).map((arrest) => arrest.seat));
  // 복기(라운드별)면 그 라운드가 끝났을 때의 자리, 경로만 보기면 토큰 없이 길만
  const reviewEntry = ending === 'review' && reviewMode === 'rounds' ? view.history?.[reviewRound] : undefined;
  const shownTokens: MToken[] = reviewEntry
    ? view.players.map((player) => ({ seat: player.seat, room: reviewEntry.positions[String(player.seat)] ?? 0, team: player.team, status: reviewEntry.status_of?.[String(player.seat)] ?? null }))
    : (ending === 'review' ? [] : view.tokens);
  const reviewDragged = new Set((reviewEntry?.arrests ?? []).map((arrest) => arrest.seat));
  const routeList = routeSeats ?? view.players.filter((player) => player.team === 'student').map((player) => player.seat);

  return createPortal(
    <div className='game-stage mm-stage' role='region' aria-label={name} ref={stageRef}>
      {/* 맨 위: 턴 · 제한 시간 · 목표 · 내 팀 */}
      <header className='mm-top'>
        <span className='mm-chip'><FormattedMessage id='mm.turn' defaultMessage='Turn {turn}/{max}' values={{ turn: view.turn, max: view.max_turns }} /></span>
        {remaining !== null && (
          <span className={remaining <= 5 ? 'mm-timer is-low' : 'mm-timer'}>
            <span className='mm-timer__bar'><motion.i animate={{ width: `${Math.min(100, (remaining / total) * 100)}%` }} transition={{ duration: 0.3 }} /></span>
            <b>{remaining}</b>
          </span>
        )}
        {view.items.cloaked && <span className='mm-chip mm-chip--cloak'><TIcon name='eye-off' size={15} /> <FormattedMessage id='mm.cloaked' defaultMessage='Invisible' /></span>}
        <span className='mm-chip'><FormattedMessage id='mm.goals' defaultMessage='Goals {done}/{total}' values={{ done: view.targets_done, total: view.targets_total }} /></span>
        {view.team && <span className={`mm-chip mm-chip--${view.team}`}>{names}</span>}
        {view.spectator && <span className='mm-chip mm-chip--dim'><FormattedMessage id='mm.spectating' defaultMessage='Spectating' /></span>}
        <button type='button' className={sound ? 'mm-sound' : 'mm-sound is-off'} onClick={toggleSound} title={sound ? '소리 끄기' : '소리 켜기'} aria-pressed={sound}><TIcon name={sound ? 'volume' : 'volume-off'} size={16} /></button>
        <button type='button' className='mm-exit' onClick={() => { history.push('/system/group'); }}><FormattedMessage id='mm.exit' defaultMessage='Exit' /></button>
      </header>

      {/* 지도 (양피지) + 양 옆 팀 열 */}
      <div className='mm-arena'>
        <TeamSide view={view} team='student' />
      <div className='mm-parchment' style={{ '--mm-k': Math.max(0.5, Math.min(1, 1000 / geo.width)) } as React.CSSProperties}>
        <MapLegend view={view} />
        {/* 안내글은 전부 지도 위에: 이동 선택 안내, 갇힘·탈락 안내, 소식(누가 어디에 있는지·계단 변화 등) */}
        <ul className='mm-notice' aria-live='polite'>
          {jailed && <li className='is-warn'><FormattedMessage id='mm.jailed' defaultMessage="You were caught and locked in the prefects' room. You can only use the team chat until a teammate rescues you." /></li>}
          {out && <li className='is-warn'><FormattedMessage id='mm.out' defaultMessage='You were caught twice and are out. Watching the rest.' /></li>}
        </ul>
        <div className={stairsShift ? 'mm-board is-shifting' : 'mm-board'} style={{ aspectRatio: `${geo.width} / ${geo.height}` }}>
          <MapSvg view={view} geo={geo} reachable={reachable} here={here} planned={planned} pickingWatch={pickingWatch} draw={intro === 'oath' || (ending === 'none' && view.turn <= 1)} fade={false} onPick={pick} />

          {/* 구역 공개(사감 팀): 대략적인 층/탑이 잉크로 번진다 */}
          {ending !== 'review' && view.clues.filter((clue) => clue.kind === 'zone' && clue.zone && clue.age <= 3).map((clue) => {
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
          {ending !== 'review' && view.clues.filter((clue) => (clue.kind === 'footprint' || clue.kind === 'watch') && clue.room !== undefined && clue.age <= 4).map((clue) => (
            <motion.div key={`mark-${clue.turn}-${clue.seat}-${clue.kind}`} className='mm-mark' style={pct(geo.center(clue.room ?? 0))} initial={{ opacity: 0, scale: 0.5 }} animate={{ opacity: Math.max(0.55, 1 - (clue.age * 0.15)), scale: 1 }}>
              <FootGlyph team='student' />
              <NameTag player={byseat.get(clue.seat)} team='student' me={clue.seat === view.me} dim={clue.age > 0} />
            </motion.div>
          ))}

          {ending !== 'review' && view.clues.filter((clue) => clue.kind === 'scout' && clue.room !== undefined && clue.age <= 2).map((clue) => (
            <motion.div key={`scout-${clue.turn}-${clue.seat}`} className='mm-scout' style={pct(geo.center(clue.room ?? 0))} initial={{ scale: 0.2, opacity: 0.9 }} animate={{ scale: [0.2, 1, 1.15], opacity: [0.9, 0.7, Math.max(0.1, 0.6 - (clue.age * 0.25))] }} transition={{ duration: 1.4 }}>
              <span><TIcon name='search' size={18} /> <TIcon name='walk' size={18} /> ×{clue.count}</span>
            </motion.div>
          ))}

          {/* 발자국 찍기 (이동·끌려감) */}
          {stamps.map((stamp) => (
            <motion.div key={stamp.id} className='mm-stamp' style={{ ...pct({ x: stamp.x, y: stamp.y }), rotate: stamp.angle }} initial={{ opacity: 0, scale: 0.4 }} animate={{ opacity: [0, 1, 1, 0], scale: [0.4, 1, 1, 1] }} transition={{ delay: stamp.delay, duration: 2.6 }}>
              <StepGlyph team={stamp.team} side={stamp.side} />
            </motion.div>
          ))}

          {/* 이름표 달린 발자국 토큰 */}
          {shownTokens.map((token) => {
            const player = byseat.get(token.seat);
            const point = geo.center(token.room);
            const secret = reviewEntry ? false : view.last?.moves[String(token.seat)]?.secret;
            const arrested = reviewEntry ? reviewDragged.has(token.seat) : dragged.has(token.seat);
            return (
              <motion.div
                key={token.seat}
                className={['mm-token', `mm-token--${token.team}`, token.status === 'jailed' && 'is-jailed', token.status === 'out' && 'is-out', token.seat === view.me && 'is-me'].filter(Boolean).join(' ')}
                initial={false}
                animate={{ left: pct(point).left, top: pct(point).top, opacity: secret ? [1, 0, 0, 1] : 1, rotate: arrested ? [0, -9, 9, -7, 7, 0] : 0 }}
                transition={{ left: { duration: arrested ? 2.4 : 1.1, delay: arrested ? 0.8 : 0.2 }, top: { duration: arrested ? 2.4 : 1.1, delay: arrested ? 0.8 : 0.2 }, opacity: { duration: 1.4 }, rotate: { duration: 0.7 } }}
              >
                <FootGlyph team={token.team} />
                <NameTag player={player} team={token.team} me={token.seat === view.me} label={token.status === 'jailed' ? <TIcon name='lock' size={14} /> : token.status === 'out' ? '탈락' : undefined} cloaked={Boolean(player?.cloaked)} />
                {token.seat === view.me && selecting && intro === 'done' && (
                  <motion.span className='mm-token__ask' initial={{ opacity: 0, y: -4 }} animate={{ opacity: 1, y: [0, 4, 0] }} transition={{ y: { duration: 1.4, repeat: Infinity } }}>
                    {pickingWatch ? '감시할 방을 고르세요!' : '갈 곳을 고르세요!'}
                  </motion.span>
                )}
              </motion.div>
            );
          })}

          {/* 지도 위 그 자리에 잠깐 뜨는 소식 */}
          <AnimatePresence>
            {notes.map((note) => (
              <motion.div key={note.id} className={`mm-note mm-note--${note.kind}`} style={pct({ x: note.x, y: note.y })} initial={{ opacity: 0, y: 10, scale: 0.85 }} animate={{ opacity: [0, 1, 1, 0], y: [10, -6, -10, -18], scale: [0.85, 1, 1, 0.98] }} transition={{ delay: note.delay, duration: 5.2, times: [0, 0.1, 0.85, 1] }}>
                {note.text}
              </motion.div>
            ))}
          </AnimatePresence>

          {/* 목표 달성 · 투옥 · 탈출 효과 */}
          {bursts.map((burst) => (
            <motion.div key={burst.id} className={`mm-burst mm-burst--${burst.kind}`} style={pct({ x: burst.x, y: burst.y })} initial={{ opacity: 0, scale: 0.3 }} animate={{ opacity: [0, 1, 1, 0], scale: [0.3, 1.25, 1, 1.05] }} transition={{ delay: burst.delay, duration: 2.6, times: [0, 0.2, 0.8, 1] }}>
              <i aria-hidden />
              <strong>{burst.label}</strong>
            </motion.div>
          ))}

          {/* 전체 공개 말풍선 */}
          <AnimatePresence>
            {view.bubbles.map((bubble) => (
              <motion.div key={bubble.id} className='mm-bubble' style={pct(geo.center(bubble.room))} initial={{ opacity: 0, y: 10, scale: 0.8 }} animate={{ opacity: 1, y: -34, scale: 1 }} exit={{ opacity: 0 }} transition={{ duration: 0.3 }}>
                {bubble.text}
              </motion.div>
            ))}
          </AnimatePresence>


          {/* 끝난 뒤 리플레이 */}
          {ending === 'review' && reviewMode === 'routes' && <RoutesLayer view={view} geo={geo} seats={routeList} />}
        </div>
      </div>

        <TeamSide view={view} team='prefect' />
      </div>

      {/* 맹세(오프닝)는 메뉴 띠까지 덮는 전체 화면, 끝나면 아이콘 메뉴가 있는 지도 화면 */}
      {createPortal(<AnimatePresence>{intro === 'oath' && <Oath key='oath' onDone={() => { finishIntro(viewRef.current?.team ? 'role' : 'done'); }} />}</AnimatePresence>, document.body)}

      {selecting && (
        <div className='mm-prompt'>
          <span>{pickingWatch ? <FormattedMessage id='mm.pick_watch' defaultMessage='Pick a room to watch.' /> : <FormattedMessage id='mm.pick_here' defaultMessage='Choose where to go!' />}</span>
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
      )}

      {/* 소식 토스트: 채팅창 왼쪽에서 오른쪽으로 밀려 들어온다 */}
      <ul className='mm-toasts' aria-live='polite'>
        <AnimatePresence>
          {toasts.map((toast) => (
            <motion.li key={toast.id} initial={{ opacity: 0, x: -40 }} animate={{ opacity: 1, x: 0 }} exit={{ opacity: 0, x: -20 }} transition={{ duration: 0.4 }}><TIcon name='info-circle' size={20} /><span>{toast.text}</span></motion.li>
          ))}
        </AnimatePresence>
      </ul>

      <ChatDock sessionId={sessionId} chat={chat} team={view.team} canChat={(isPlayer || staff) && view.status !== 'finished'} jailed={jailed} infos={infos} onSent={onChanged} />

      {/* 맹세 → 역할 안내 */}
      <AnimatePresence>
        {intro === 'role' && view.team && <RoleModal key='role' view={view} onClose={() => { finishIntro('done'); }} />}
      </AnimatePresence>

      {/* 끝: 장난 끝 → 리플레이 → 결과 */}
      <AnimatePresence>
        {ending === 'over' && (
          <motion.div key='over' className='mm-over' initial={{ opacity: 0 }} animate={{ opacity: 1 }} exit={{ opacity: 0 }}>
            <motion.strong initial={{ scale: 2.6, opacity: 0, rotate: -6 }} animate={{ scale: 1, opacity: 1, rotate: -3 }} transition={{ type: 'spring', stiffness: 120, damping: 12 }}><FormattedMessage id='mm.mischief_over' defaultMessage='Mischief managed' /></motion.strong>
          </motion.div>
        )}
        {ending === 'review' && (
          <ReviewBar
            key='review'
            view={view}
            mode={reviewMode}
            round={reviewRound}
            playing={playing}
            seats={routeList}
            onMode={(mode) => { setReviewMode(mode); setPlaying(false); setStamps([]); }}
            onRound={(round) => { setReviewRound(round); setPlaying(false); }}
            onPlay={() => { if (reviewRound >= lastRound) setReviewRound(0); setPlaying((value) => !value); }}
            onSeat={(seat) => { setRouteSeats((current) => { const list = current ?? view.players.filter((player) => player.team === 'student').map((player) => player.seat); return list.includes(seat) ? list.filter((each) => each !== seat) : [...list, seat]; }); }}
            onResult={() => { setEnding('result'); setPlaying(false); }}
          />
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
              <button type='button' className='mm-button mm-button--ghost' onClick={() => { setEnding('review'); setReviewMode('rounds'); setReviewRound(lastRound); setPlaying(false); }}><FormattedMessage id='mm.see_replay' defaultMessage='Watch again' /></button>
              <button type='button' className='mm-button' onClick={() => { history.push('/system/group'); }}><FormattedMessage id='mm.leave' defaultMessage='Leave' /></button>
            </div>
          </motion.div>
        )}
      </AnimatePresence>
    </div>,
    document.body,
  );
};
