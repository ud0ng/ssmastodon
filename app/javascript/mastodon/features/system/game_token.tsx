// 게임 토큰: 캐릭터 아바타 + 그 아래 이름. 아이템으로 붙은 데코(아바타 둘레)·칭호(이름 글자)가 대기방·게임방 어디서나 그대로 붙는다.
//   효과는 components/game_fx 의 공용 저장소(useAccountFx)에서 계정 번호로 받는다.
import { GameFx, useAccountFx } from 'mastodon/components/game_fx';

import { Crest } from './crest';

export interface TokenHouse {
  name: string;
  color: string;
}

// 원형 아바타 (+ 데코). size 는 px, 24 미만에는 데코를 붙이지 않는다
export const TokenAvatar: React.FC<{ accountId: string; avatar: string | null | undefined; size: number }> = ({ accountId, avatar, size }) => {
  const fx = useAccountFx(accountId);
  const plain = (
    <div className='account__avatar gtoken__avatar' style={{ width: `${size}px`, height: `${size}px` }}>
      {avatar && <img src={avatar} alt='' />}
    </div>
  );

  return fx.deco && size >= 24 ? (
    <span className={`game-fx-deco game-fx-deco--${fx.deco} game-fx-deco-wrap`}>
      {plain}
      <GameFx slot='deco' preset={fx.deco} />
    </span>
  ) : plain;
};

// 이름 (칭호 효과 포함, 소속 문장은 선택)
export const TokenName: React.FC<{ accountId: string; name: string; house?: TokenHouse | null }> = ({ accountId, name, house }) => {
  const fx = useAccountFx(accountId);
  const label = <span className='gtoken__name-text'>{name}</span>;

  return (
    <span className='gtoken__name'>
      {house && <Crest house={{ id: '', name: house.name, emoji: '', color: house.color, total: 0 }} />}
      {fx.title ? (
        <span className={`game-fx-title game-fx-title--${fx.title}`}>
          <span className='game-fx-name'>{label}</span>
          <GameFx slot='title' preset={fx.title} />
        </span>
      ) : label}
    </span>
  );
};

export const GameToken: React.FC<{
  accountId: string;
  avatar: string | null | undefined;
  name: string;
  house?: TokenHouse | null;
  size?: number;
  className?: string;
  // 아바타 바로 아래(이름 위)에 붙는 것: 비행 대결의 빗자루
  children?: React.ReactNode;
  // 이름 아래에 붙는 것: 비행 대결의 내구도 배지
  footer?: React.ReactNode;
}> = ({ accountId, avatar, name, house, size = 64, className, children, footer }) => (
  <span className={['gtoken', className].filter(Boolean).join(' ')}>
    <TokenAvatar accountId={accountId} avatar={avatar} size={size} />
    {children}
    <TokenName accountId={accountId} name={name} house={house} />
    {footer}
  </span>
);
