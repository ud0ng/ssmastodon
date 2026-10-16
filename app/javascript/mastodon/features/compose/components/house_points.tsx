// 글쓰기 패널 재화 줄 바로 아래: 소속 점수 카드 (점수 기준 소속, 이번 시즌).
// 재화 줄과 같은 모양: 양피지 띠를 금빛 점선으로 나눈 칸마다 소속 이름 / 문장(깃발) + 점수. 표시만 한다 (따로 화면 없음).
import { useIntl } from 'react-intl';

import { Crest } from 'mastodon/features/system/crest';
import { useWallet } from 'mastodon/features/system/use_wallet';

export const HousePoints: React.FC = () => {
  const intl = useIntl();
  const wallet = useWallet();

  if (!wallet || wallet.houses.length === 0) return null;

  const houses = [...wallet.houses].sort((a, b) => b.total - a.total);
  const label = intl.formatMessage({ id: 'system.houses', defaultMessage: '{term} points' }, { term: wallet.house_term });

  return (
    <div className='house-points' role='group' aria-label={label} style={{ gridTemplateColumns: `repeat(${houses.length}, minmax(0, 1fr))` }}>
      {houses.map((house) => (
        <span
          key={house.id}
          className={house.id === wallet.my_house_id ? 'house-points__item house-points__item--mine' : 'house-points__item'}
        >
          <span className='house-points__name'>{house.name}</span>
          <span className='house-points__value'>
            <Crest house={{ ...house, emoji: '' }} />
            <strong>{house.total.toLocaleString()}</strong>
          </span>
        </span>
      ))}
    </div>
  );
};
