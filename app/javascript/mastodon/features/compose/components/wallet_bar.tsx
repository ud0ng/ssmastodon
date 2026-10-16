// 글쓰기창 아래: (재화 이름) | 인벤토리 | 전적. 누르면 재화 화면 / 인벤토리 화면 / 성적 화면.
// 색은 사용자 화면 테마(커뮤니티 테마 낮/밤)를 따른다.
import { FormattedMessage } from 'react-intl';

import { Link } from 'react-router-dom';

import DiamondIcon from '@/material-icons/400-24px/diamond.svg?react';
import InventoryIcon from '@/material-icons/400-24px/inventory_2.svg?react';
import { Icon } from 'mastodon/components/icon';
import { useWallet } from 'mastodon/features/system/use_wallet';

export const WalletBar: React.FC = () => {
  const wallet = useWallet();

  if (!wallet) return null;

  const { win, lose, draw } = wallet.record;

  return (
    <nav className='wallet-bar'>
      <Link to='/system/wallet' className='wallet-bar__item'>
        <span className='wallet-bar__label'>
          {wallet.currency}
        </span>
        <span className='wallet-bar__value'>
          <Icon id='diamond' icon={DiamondIcon} />
          {wallet.money.toLocaleString()}
        </span>
      </Link>

      <Link to='/system/inventory' className='wallet-bar__item'>
        <span className='wallet-bar__label'>
          <FormattedMessage id='wallet.inventory' defaultMessage='Inventory' />
        </span>
        <span className='wallet-bar__value'>
          <Icon id='inventory' icon={InventoryIcon} />
        </span>
      </Link>

      <Link to='/system/record' className='wallet-bar__item'>
        <span className='wallet-bar__label'>
          <FormattedMessage id='wallet.record' defaultMessage='Record' />
        </span>
        <span className='wallet-bar__value'>
          <FormattedMessage id='wallet.record_summary' defaultMessage='{win}W {lose}L {draw}D' values={{ win, lose, draw }} />
        </span>
      </Link>
    </nav>
  );
};
