// 글쓰기 패널 재화 줄 바로 아래: 소속 점수 카드 (점수 기준 소속, 이번 시즌).
// 재화 줄과 같은 모양: 양피지 띠를 금빛 점선으로 나눈 칸마다 소속 이름 / 문장(깃발) + 점수. 표시만 한다 (따로 화면 없음).
// 아이템으로 소속에 효과(상점 설정 > 효과 목록)가 붙어 있으면 그 칸에 효과를 그린다. 블링블링·똥은 예전 1등·꼴등 모양(house_fx), 나머지는 components/game_fx.
import { useIntl } from 'react-intl';

import { GameFx } from 'mastodon/components/game_fx';
import { Crest } from 'mastodon/features/system/crest';
import { useWallet } from 'mastodon/features/system/use_wallet';

import { GoldFx, HOUSE_FX_CLASS, PoopFx } from './house_fx';

export const HousePoints: React.FC = () => {
  const intl = useIntl();
  const wallet = useWallet();

  if (!wallet || wallet.houses.length === 0) return null;

  const houses = [...wallet.houses].sort((a, b) => b.total - a.total);
  const label = intl.formatMessage({ id: 'system.houses', defaultMessage: '{term} points' }, { term: wallet.house_term });

  return (
    <div className='house-points' role='group' aria-label={label} style={{ gridTemplateColumns: `repeat(${houses.length}, minmax(0, 1fr))` }}>
      {houses.map((house) => {
        const classes = [
          'house-points__item',
          house.id === wallet.my_house_id && 'house-points__item--mine',
          house.fx && (HOUSE_FX_CLASS[house.fx] ?? `game-fx-host game-fx-host--card game-fx-host--${house.fx}`),
        ].filter(Boolean).join(' ');
        return (
          <span key={house.id} className={classes}>
            {house.fx === 'gold' && <GoldFx />}
            {house.fx === 'poop' && <PoopFx />}
            {house.fx && !HOUSE_FX_CLASS[house.fx] && <GameFx slot='card' preset={house.fx} />}
            <span className='house-points__name'>{house.name}</span>
            <span className='house-points__value'>
              <Crest house={{ ...house, emoji: '' }} />
              <strong>{house.total.toLocaleString()}</strong>
            </span>
          </span>
        );
      })}
    </div>
  );
};
