// 컨텐츠 화면·성적 화면 맨 위: 내 캐릭터를 크게
//   [소속 문장·이름] | 캐릭터 이름
//                    | 전적
import { FormattedMessage } from 'react-intl';

import type { House } from './crest';
import { Crest } from './crest';

export const CharacterHeader: React.FC<{
  name: string;
  house?: House;
  houseTerm: string;
  record: { win: number; lose: number; draw: number };
}> = ({ name, house, houseTerm, record }) => (
  <div className='system-hero' style={{ '--house-color': house?.color || '#6b5b3e' } as React.CSSProperties}>
    <div className='system-hero__house'>
      <Crest house={house} large />
      <span className='system-hero__house-name'>
        {house ? house.name : <FormattedMessage id='system.no_house' defaultMessage='No {term} yet' values={{ term: houseTerm }} />}
      </span>
    </div>
    <div className='system-hero__main'>
      <span className='system-hero__name'>{name}</span>
      <span className='system-hero__record'>
        <FormattedMessage id='system.record' defaultMessage='{win} W · {lose} L · {draw} D' values={record} />
      </span>
    </div>
  </div>
);
