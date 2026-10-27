// 글쓰기 패널 재화 줄 바로 아래: 소속 점수 카드 (점수 기준 소속, 이번 시즌).
// 재화 줄과 같은 모양: 양피지 띠를 금빛 점선으로 나눈 칸마다 소속 이름 / 문장(깃발) + 점수. 표시만 한다 (따로 화면 없음).
// 시즌 종료 상태(새 시즌 전)면 맨 위에 '○○ 시즌 종료' 줄과 칸마다 최종 순위(1위·2위…)를 보여 준다.
// 아이템으로 소속에 효과(상점 설정 > 효과 목록)가 붙어 있으면 그 칸에 효과를 그린다. 블링블링·똥은 예전 1등·꼴등 모양(house_fx), 나머지는 components/game_fx.
import { FormattedMessage, useIntl } from 'react-intl';

import { Link } from 'react-router-dom';

import { GameFx } from 'mastodon/components/game_fx';
import { Crest } from 'mastodon/features/system/crest';
import { ChangeBadge } from 'mastodon/features/system/change_badge';
import type { Wallet } from 'mastodon/features/system/use_wallet';
import { useWallet } from 'mastodon/features/system/use_wallet';
import { useChanged } from 'mastodon/features/system/wallet_changes';

import { GoldFx, HOUSE_FX_CLASS, PoopFx } from './house_fx';

const RANK_MEDALS = ['🥇', '🥈', '🥉'];

const HouseCard: React.FC<{ house: Wallet['houses'][number]; wallet: Wallet; classes: string }> = ({ house, wallet, classes }) => {
  const changed = useChanged('house', wallet, house.id);

  return (
    <Link to={`/system/houses/${house.id}`} className={classes}>
      <ChangeBadge show={changed} />
      {house.fx === 'gold' && <GoldFx />}
      {house.fx === 'poop' && <PoopFx />}
      {house.fx && !HOUSE_FX_CLASS[house.fx] && <GameFx slot='card' preset={house.fx} />}
      {wallet.season_closed && house.rank && (
        <span className={`house-points__rank house-points__rank--${house.rank}`}>
          {RANK_MEDALS[house.rank - 1] ?? ''}
          <FormattedMessage id='house.rank' defaultMessage='#{rank}' values={{ rank: house.rank }} />
        </span>
      )}
      <span className='house-points__name'>{house.name}</span>
      <span className='house-points__value'>
        <Crest house={{ ...house, emoji: '' }} />
        <strong>{house.total.toLocaleString()}</strong>
      </span>
    </Link>
  );
};

export const HousePoints: React.FC = () => {
  const intl = useIntl();
  const wallet = useWallet();

  if (!wallet || wallet.houses.length === 0) return null;

  const houses = [...wallet.houses].sort((a, b) => b.total - a.total);
  const label = intl.formatMessage({ id: 'system.houses', defaultMessage: '{term} points' }, { term: wallet.house_term });

  return (
    <div className={wallet.season_closed ? 'house-points house-points--closed' : 'house-points'} role='group' aria-label={label} style={{ gridTemplateColumns: `repeat(${houses.length}, minmax(0, 1fr))` }}>
      {wallet.season_closed && (
        <span className='house-points__season'>
          <FormattedMessage id='house.season_closed' defaultMessage='{season} season ended · final ranking' values={{ season: wallet.season_closed }} />
        </span>
      )}
      {houses.map((house) => {
        const classes = [
          'house-points__item',
          house.id === wallet.my_house_id && 'house-points__item--mine',
          house.fx && (HOUSE_FX_CLASS[house.fx] ?? `game-fx-host game-fx-host--card game-fx-host--${house.fx}`),
        ].filter(Boolean).join(' ');
        return <HouseCard key={house.id} house={house} wallet={wallet} classes={classes} />;
      })}
    </div>
  );
};
