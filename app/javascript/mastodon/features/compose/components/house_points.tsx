// 글쓰기 패널 재화 줄 바로 아래: 소속 점수 카드 (점수 기준 소속, 이번 시즌).
// 재화 줄과 같은 모양: 양피지 띠를 금빛 점선으로 나눈 칸마다 소속 이름 / 문장(깃발) + 점수. 표시만 한다 (따로 화면 없음).
// 1등 소속은 반짝반짝 블링블링한 금빛 효과(왕관·별빛·번쩍이는 빛줄기), 꼴등 소속은 똥 효과(똥·파리·냄새·덜덜 떨리는 글자).
// 모두 같은 점수면(처음 시작 등) 효과를 넣지 않는다. 효과는 CSS 애니메이션이라 따로 라이브러리가 필요 없고, 움직임 줄이기 설정이면 멈춘다.
import { useIntl } from 'react-intl';

import { Crest } from 'mastodon/features/system/crest';
import { useWallet } from 'mastodon/features/system/use_wallet';

interface Particle { glyph: string; x: string; y?: string; size: string; duration: string; delay: string }

// 1등: 별빛 (위치·크기·주기를 달리해서 제각각 반짝인다)
const SPARKS: Particle[] = [
  { glyph: '✦', x: '8%', y: '18%', size: '10px', duration: '1.5s', delay: '0s' },
  { glyph: '✧', x: '24%', y: '70%', size: '12px', duration: '1.9s', delay: '0.4s' },
  { glyph: '✨', x: '40%', y: '12%', size: '11px', duration: '2.1s', delay: '0.9s' },
  { glyph: '✦', x: '58%', y: '62%', size: '9px', duration: '1.4s', delay: '0.2s' },
  { glyph: '✧', x: '72%', y: '20%', size: '13px', duration: '1.8s', delay: '0.7s' },
  { glyph: '✨', x: '86%', y: '66%', size: '10px', duration: '2.3s', delay: '1.2s' },
  { glyph: '✦', x: '92%', y: '14%', size: '8px', duration: '1.6s', delay: '0.5s' },
  { glyph: '⭐', x: '14%', y: '46%', size: '7px', duration: '2s', delay: '1.5s' },
  { glyph: '✧', x: '66%', y: '42%', size: '8px', duration: '1.7s', delay: '1s' },
];

// 꼴등: 떠오르는 똥, 빙빙 도는 파리, 올라가는 냄새
const POOPS: Particle[] = [
  { glyph: '💩', x: '10%', size: '12px', duration: '3.4s', delay: '0s' },
  { glyph: '💩', x: '30%', size: '9px', duration: '2.8s', delay: '0.9s' },
  { glyph: '💩', x: '52%', size: '14px', duration: '3.8s', delay: '0.3s' },
  { glyph: '💩', x: '70%', size: '10px', duration: '3s', delay: '1.6s' },
  { glyph: '💩', x: '88%', size: '12px', duration: '3.6s', delay: '1.1s' },
];

const FLIES: Particle[] = [
  { glyph: '🪰', x: '0', size: '10px', duration: '2.2s', delay: '0s' },
  { glyph: '🪰', x: '0', size: '8px', duration: '1.6s', delay: '0.6s' },
  { glyph: '🪰', x: '0', size: '9px', duration: '2.8s', delay: '1.1s' },
];

const STINKS: Particle[] = [
  { glyph: '〰', x: '20%', size: '12px', duration: '2.4s', delay: '0.2s' },
  { glyph: '〰', x: '46%', size: '10px', duration: '2s', delay: '1s' },
  { glyph: '〰', x: '78%', size: '12px', duration: '2.6s', delay: '0.6s' },
];

const style = (particle: Particle) => ({ '--x': particle.x, '--y': particle.y, '--s': particle.size, '--d': particle.duration, '--delay': particle.delay }) as React.CSSProperties;

const GoldFx: React.FC = () => (
  <span className='house-points__fx house-points__fx--gold' aria-hidden>
    <span className='fx-glint' />
    {SPARKS.map((particle, index) => <span key={index} className='fx-spark' style={style(particle)}>{particle.glyph}</span>)}
    <span className='fx-crown'>👑</span>
  </span>
);

const PoopFx: React.FC = () => (
  <span className='house-points__fx house-points__fx--poop' aria-hidden>
    <span className='fx-drip' />
    {STINKS.map((particle, index) => <span key={`s${index}`} className='fx-stink' style={style(particle)}>{particle.glyph}</span>)}
    {POOPS.map((particle, index) => <span key={`p${index}`} className='fx-poop' style={style(particle)}>{particle.glyph}</span>)}
    {FLIES.map((particle, index) => <span key={`f${index}`} className='fx-fly' style={style(particle)}>{particle.glyph}</span>)}
    <span className='fx-big-poop'>💩</span>
  </span>
);

export const HousePoints: React.FC = () => {
  const intl = useIntl();
  const wallet = useWallet();

  if (!wallet || wallet.houses.length === 0) return null;

  const houses = [...wallet.houses].sort((a, b) => b.total - a.total);
  const label = intl.formatMessage({ id: 'system.houses', defaultMessage: '{term} points' }, { term: wallet.house_term });
  // 점수가 다 같으면 1등·꼴등이 없다. 공동 1등·공동 꼴등은 모두 효과를 받는다.
  const top = houses[0]?.total ?? 0;
  const bottom = houses[houses.length - 1]?.total ?? 0;
  const ranked = wallet.rank_effects !== false && houses.length >= 2 && top !== bottom;

  return (
    <div className='house-points' role='group' aria-label={label} style={{ gridTemplateColumns: `repeat(${houses.length}, minmax(0, 1fr))` }}>
      {houses.map((house) => {
        const first = ranked && house.total === top;
        const last = ranked && house.total === bottom;
        const classes = ['house-points__item', house.id === wallet.my_house_id && 'house-points__item--mine', first && 'house-points__item--first', last && 'house-points__item--last'].filter(Boolean).join(' ');
        return (
          <span key={house.id} className={classes}>
            {first && <GoldFx />}
            {last && <PoopFx />}
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
