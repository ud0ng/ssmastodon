// 웹 전용 컨텐츠(미로·도둑 지도·비밀의 방) 판 맨 위 고정 헤더: 지금 단계(아이콘·제목) · 시간 · 참가자 아바타
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
