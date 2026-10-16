// 웹 재화·인벤토리 화면 (글쓰기창 아래 버튼에서 들어온다)
//   /system/wallet     지금 재화 + 재화 기록
//   /system/inventory  가진 아이템 (상점 그림 + 개수 배지 + 이름)
import { defineMessages, FormattedMessage, useIntl } from 'react-intl';

import { Helmet } from 'react-helmet';
import { useParams } from 'react-router-dom';

import DiamondIcon from '@/material-icons/400-24px/diamond.svg?react';
import InventoryIcon from '@/material-icons/400-24px/inventory_2.svg?react';
import { Column } from 'mastodon/components/column';
import { ColumnHeader } from 'mastodon/components/column_header';
import { Icon } from 'mastodon/components/icon';
import { LoadingIndicator } from 'mastodon/components/loading_indicator';
import { RelativeTimestamp } from 'mastodon/components/relative_timestamp';

import type { Wallet, WalletRecord } from './use_wallet';
import { useWallet } from './use_wallet';

const messages = defineMessages({
  wallet: { id: 'wallet.money', defaultMessage: 'Currency' },
  inventory: { id: 'wallet.inventory', defaultMessage: 'Inventory' },
});

const signed = (value: number) => (value > 0 ? `+${value.toLocaleString()}` : value.toLocaleString());

// 재화 기록 한 줄: 종류 · 사유 / 바뀐 재화·아이템 / 언제
const RecordRow: React.FC<{ record: WalletRecord; currency: string }> = ({ record, currency }) => {
  const changes = [
    ...(record.money !== 0 ? [`${signed(record.money)} ${currency}`] : []),
    ...record.items.map((item) => `${item.name} ${signed(item.count)}`),
  ];

  return (
    <li className='wallet-page__record'>
      <div className='wallet-page__record-main'>
        <span className='wallet-page__kind'>{record.kind_name}</span>
        {record.reason && <span className='wallet-page__reason'>{record.reason}</span>}
      </div>
      <span className={record.money < 0 ? 'wallet-page__change wallet-page__change--minus' : 'wallet-page__change'}>{changes.join(', ') || '—'}</span>
      <RelativeTimestamp timestamp={record.created_at} />
    </li>
  );
};

const MoneyView: React.FC<{ wallet: Wallet }> = ({ wallet }) => (
  <>
    <div className='wallet-page__summary'>
      <Icon id='diamond' icon={DiamondIcon} />
      <strong>{wallet.money.toLocaleString()}</strong>
      <span>{wallet.currency}</span>
    </div>

    <h3 className='wallet-page__title'>
      <FormattedMessage id='wallet.records' defaultMessage='History' />
    </h3>
    {wallet.records.length === 0 ? (
      <p className='wallet-page__empty'>
        <FormattedMessage id='wallet.no_records' defaultMessage='No history yet.' />
      </p>
    ) : (
      <ul className='wallet-page__records'>
        {wallet.records.map((record) => <RecordRow key={record.id} record={record} currency={wallet.currency} />)}
      </ul>
    )}
  </>
);

const InventoryView: React.FC<{ wallet: Wallet }> = ({ wallet }) =>
  wallet.inventory.length === 0 ? (
    <p className='wallet-page__empty'>
      <FormattedMessage id='wallet.no_items' defaultMessage='No items yet.' />
    </p>
  ) : (
    <ul className='wallet-page__items'>
      {wallet.inventory.map((item) => (
        <li key={item.name} className='wallet-page__item' title={[item.description, item.note].filter(Boolean).join('\n') || undefined}>
          <span className='wallet-page__item-image'>
            {item.image ? <img src={item.image} alt='' loading='lazy' /> : <span className='wallet-page__item-letter'>{item.name.trim().charAt(0)}</span>}
            <span className='wallet-page__item-count'>×{item.count}</span>
          </span>
          <span className='wallet-page__item-name'>{item.name}</span>
        </li>
      ))}
    </ul>
  );

const WalletPage: React.FC<{ multiColumn: boolean }> = ({ multiColumn }) => {
  const intl = useIntl();
  const { section } = useParams<{ section: 'wallet' | 'inventory' }>();
  const wallet = useWallet();
  const inventory = section === 'inventory';
  const title = intl.formatMessage(inventory ? messages.inventory : messages.wallet);

  return (
    <Column bindToDocument={!multiColumn} label={title}>
      <ColumnHeader icon={inventory ? 'inventory' : 'diamond'} iconComponent={inventory ? InventoryIcon : DiamondIcon} title={title} multiColumn={multiColumn} showBackButton />

      <div className='scrollable wallet-page'>
        {!wallet ? <LoadingIndicator /> : inventory ? <InventoryView wallet={wallet} /> : <MoneyView wallet={wallet} />}
      </div>

      <Helmet>
        <title>{title}</title>
        <meta name='robots' content='noindex' />
      </Helmet>
    </Column>
  );
};

export default WalletPage;
