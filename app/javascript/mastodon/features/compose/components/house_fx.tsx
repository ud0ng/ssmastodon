// 소속 카드의 블링블링(gold)·똥(poop) 효과: 예전 1등·꼴등 효과 그대로 (styles: components.scss .house-points__item--first/--last, .house-points__fx)
// 1등: 반짝반짝 블링블링한 금빛 효과(왕관·별빛·번쩍이는 빛줄기), 똥: 똥·파리·냄새·덜덜 떨리는 글자. 관리 화면 미리보기(admin/game_effects/_house_fx)와 같은 마크업.
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

export const GoldFx: React.FC = () => (
  <span className='house-points__fx house-points__fx--gold' aria-hidden>
    <span className='fx-glint' />
    {SPARKS.map((particle, index) => <span key={index} className='fx-spark' style={style(particle)}>{particle.glyph}</span>)}
    <span className='fx-crown'>👑</span>
  </span>
);

export const PoopFx: React.FC = () => (
  <span className='house-points__fx house-points__fx--poop' aria-hidden>
    <span className='fx-drip' />
    {STINKS.map((particle, index) => <span key={`s${index}`} className='fx-stink' style={style(particle)}>{particle.glyph}</span>)}
    {POOPS.map((particle, index) => <span key={`p${index}`} className='fx-poop' style={style(particle)}>{particle.glyph}</span>)}
    {FLIES.map((particle, index) => <span key={`f${index}`} className='fx-fly' style={style(particle)}>{particle.glyph}</span>)}
    <span className='fx-big-poop'>💩</span>
  </span>
);

// 블링블링·똥은 위 모양, 나머지(불꽃·눈송이 등)는 공통 효과 겹 (components/game_fx)
export const HOUSE_FX_CLASS: Record<string, string> = { gold: 'house-points__item--first', poop: 'house-points__item--last' };
