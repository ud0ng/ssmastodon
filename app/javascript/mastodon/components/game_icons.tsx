// 컨텐츠 화면 전용 아이콘 (이모티콘 대신). Tabler Icons(outline, MIT)를 images/tabler 에서 가져온다.
// 글자 크기(1em)·글자색(currentColor)을 따른다. 칠하기는 .game-icon CSS (components.scss).
//   컨텐츠를 대표하는 아이콘은 쓰지 않는다 (사용자 요청). 상태·보상·행동 표시용 아이콘만.
//   그 밖: heart · crown · hourglass · check · star · coin · gift · cloak · scope · compass · bulb · stun · sword · hands · foot · sparkle · sun · moon
import BulbIcon from '@/images/tabler/bulb.svg?react';
import CheckIcon from '@/images/tabler/check.svg?react';
import CoinIcon from '@/images/tabler/coin.svg?react';
import CompassIcon from '@/images/tabler/compass.svg?react';
import CrownIcon from '@/images/tabler/crown.svg?react';
import FileTextIcon from '@/images/tabler/file-text.svg?react';
import GiftIcon from '@/images/tabler/gift.svg?react';
import HangerIcon from '@/images/tabler/hanger.svg?react';
import HandshakeIcon from '@/images/tabler/heart-handshake.svg?react';
import HeartIcon from '@/images/tabler/heart.svg?react';
import HourglassIcon from '@/images/tabler/hourglass.svg?react';
import DizzyIcon from '@/images/tabler/mood-sad-dizzy.svg?react';
import MoonIcon from '@/images/tabler/moon.svg?react';
import PawIcon from '@/images/tabler/paw.svg?react';
import SparklesIcon from '@/images/tabler/sparkles.svg?react';
import StarIcon from '@/images/tabler/star.svg?react';
import SunIcon from '@/images/tabler/sun.svg?react';
import SwordsIcon from '@/images/tabler/swords.svg?react';
import TelescopeIcon from '@/images/tabler/telescope.svg?react';
import TrophyIcon from '@/images/tabler/trophy.svg?react';

type SvgComponent = React.FC<React.SVGProps<SVGSVGElement>>;

const ICONS: Record<string, SvgComponent> = {
  tournament: TrophyIcon,
  heart: HeartIcon,
  crown: CrownIcon,
  hourglass: HourglassIcon,
  check: CheckIcon,
  star: StarIcon,
  coin: CoinIcon,
  gift: GiftIcon,
  cloak: HangerIcon,
  scope: TelescopeIcon,
  compass: CompassIcon,
  bulb: BulbIcon,
  stun: DizzyIcon,
  sword: SwordsIcon,
  hands: HandshakeIcon,
  foot: PawIcon,
  sparkle: SparklesIcon,
  sun: SunIcon,
  moon: MoonIcon,
};

// x·y·size: SVG 그림(도둑 지도 칸) 안에 놓을 때 위치와 크기(px)
export const GameIcon: React.FC<{ name: string; className?: string; title?: string; x?: number; y?: number; size?: number }> = ({ name, className, title, x, y, size }) => {
  const Svg = ICONS[name] ?? FileTextIcon;
  return (
    <Svg
      className={['game-icon', `game-icon--${name}`, className].filter(Boolean).join(' ')}
      aria-hidden={title ? undefined : true}
      aria-label={title}
      {...(x === undefined ? {} : { x, y })}
      {...(size === undefined ? {} : { style: { width: size, height: size } })}
    />
  );
};

// 서버가 보낸 문구 안의 이모티콘은 지운다 (컨텐츠 화면은 아이콘만 쓴다). 화살표(→)는 남긴다.
const EMOJI = /[\u{1F000}-\u{1FAFF}\u{2600}-\u{27BF}\u{231A}\u{231B}\u{23E9}-\u{23FA}\u{2B50}\u{2B55}\u{FE0F}\u{200D}]/gu;

export const stripEmoji = (text: string) => text.replace(EMOJI, '').replace(/[ \t]{2,}/g, ' ').replace(/^[ \t]+/gm, '');
