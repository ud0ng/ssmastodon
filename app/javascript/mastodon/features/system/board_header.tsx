import { useRef, useState } from 'react';

// 웹 전용 컨텐츠(미로·도둑 지도·비밀의 방) 판 맨 위 고정 헤더: 지금 단계(아이콘·제목) · 시간 · 참가자 아바타, 그리고 판 위 말(아바타)
import { RelativeTimestamp } from 'mastodon/components/relative_timestamp';
import { GameIcon } from 'mastodon/components/game_icons';

export interface HeaderPerson {
  key: string | number;
  name: string;
  avatar?: string | null;
  out?: boolean;
  badge?: string;
}

export const BoardHeader: React.FC<{
  icon: string;
  night?: boolean;
  title: React.ReactNode;
  subtitle?: React.ReactNode;
  deadline?: string | null;
  ends?: React.ReactNode;
  people: HeaderPerson[];
  peopleNote?: React.ReactNode;
}> = ({ icon, night, title, subtitle, deadline, ends, people, peopleNote }) => (
  <div className='chamber-head'>
    <div className='chamber-head__phase'>
      <span className={night ? 'chamber-head__icon chamber-head__icon--night' : 'chamber-head__icon'}>
        <GameIcon name={icon} />
      </span>
      <div className='chamber-head__title'>
        <strong>{title}</strong>
        {subtitle && <small>{subtitle}</small>}
      </div>
    </div>
    {(deadline || ends) && (
      <div className='chamber-head__time'>
        {deadline && <span><GameIcon name='hourglass' /> <RelativeTimestamp timestamp={deadline} futureDate /></span>}
        {ends && <small>{ends}</small>}
      </div>
    )}
    <div className='chamber-head__people'>
      <span className='chamber-head__avatars'>
        {people.map((person) => (
          <span key={person.key} className={person.out ? 'chamber-head__avatar chamber-head__avatar--out' : 'chamber-head__avatar'} title={person.name}>
            {person.avatar && <img src={person.avatar} alt='' />}
          </span>
        ))}
      </span>
      {peopleNote && <small>{peopleNote}</small>}
    </div>
  </div>
);

// SVG 판 위의 말: 아바타 (없으면 이름 첫 글자). 마우스를 올리면 이름이 뜬다. <AvatarClip /> 을 같은 svg 안 defs 에 한 번 둔다.
export const AvatarClip: React.FC = () => (
  <defs>
    <clipPath id='board-avatar-clip' clipPathUnits='objectBoundingBox'>
      <circle cx='0.5' cy='0.5' r='0.5' />
    </clipPath>
  </defs>
);

// 판 위에 올리는 말풍선(툴팁): 가리키는 것 위쪽에 예쁘게 뜬다 (SVG 기본 툴팁 대신)
export interface TipApi {
  show: (element: Element, title: string, lines?: string[]) => void;
  hide: () => void;
}

interface TipState { x: number; y: number; title: string; lines: string[] }

export const useBoardTip = () => {
  const wrapRef = useRef<HTMLDivElement>(null);
  const [tip, setTip] = useState<TipState | null>(null);

  const api: TipApi = {
    show: (element, title, lines = []) => {
      const wrap = wrapRef.current?.getBoundingClientRect();
      const box = element.getBoundingClientRect();
      if (!wrap) return;
      setTip({ x: box.left - wrap.left + (box.width / 2), y: box.top - wrap.top, title, lines });
    },
    hide: () => { setTip(null); },
  };

  return { wrapRef, tip, api };
};

export const BoardTip: React.FC<{ tip: TipState | null }> = ({ tip }) => (
  tip ? (
    <div className='board-tip' style={{ left: tip.x, top: tip.y }} role='tooltip'>
      <strong>{tip.title}</strong>
      {tip.lines.map((line) => <span key={line}>{line}</span>)}
    </div>
  ) : null
);

export const AvatarPin: React.FC<{
  x: number;
  y: number;
  r: number;
  name: string;
  avatar?: string | null;
  color: string;
  ring?: 'me' | 'student' | 'hostile' | null;
  stunned?: boolean;
  tip?: TipApi;
  lines?: string[];
}> = ({ x, y, r, name, avatar, color, ring, stunned, tip, lines }) => (
  <g
    className={['avatar-pin', ring && `avatar-pin--${ring}`, stunned && 'avatar-pin--stunned'].filter(Boolean).join(' ')}
    onMouseEnter={tip ? (event) => { tip.show(event.currentTarget, name, lines); } : undefined}
    onMouseLeave={tip?.hide}
  >
    {!tip && <title>{name}</title>}
    <circle className='avatar-pin__ring' cx={x} cy={y} r={r + 3} style={{ stroke: color }} />
    {avatar ? (
      <image href={avatar} x={x - r} y={y - r} width={r * 2} height={r * 2} clipPath='url(#board-avatar-clip)' preserveAspectRatio='xMidYMid slice' />
    ) : (
      <>
        <circle cx={x} cy={y} r={r} style={{ fill: color }} />
        <text x={x} y={y + 4} textAnchor='middle'>{[...name][0]}</text>
      </>
    )}
  </g>
);
