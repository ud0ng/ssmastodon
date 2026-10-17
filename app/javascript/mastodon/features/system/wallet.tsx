// 웹 재화·인벤토리 화면 (글쓰기창 아래 버튼에서 들어온다)
//   /system/wallet     보유 재화 카드(선물) + 재화 기록 (전체/획득/사용/아이템 탭, 날짜별, 더 보기)
//   /system/inventory  가진 아이템 양피지 카드 (상점 화면과 같은 해리포터 스타일). 누르면 아이템 모달 (item_modal)
import { useCallback, useMemo, useState } from 'react';

import { defineMessages, FormattedDate, FormattedMessage, FormattedTime, useIntl } from 'react-intl';

import { Helmet } from 'react-helmet';
import { useParams } from 'react-router-dom';

import CelebrationIcon from '@/material-icons/400-24px/celebration.svg?react';
import DeleteIcon from '@/material-icons/400-24px/delete.svg?react';
import DiamondIcon from '@/material-icons/400-24px/diamond.svg?react';
import DoneIcon from '@/material-icons/400-24px/done.svg?react';
import EditIcon from '@/material-icons/400-24px/edit.svg?react';
import FlagIcon from '@/material-icons/400-24px/flag.svg?react';
import InventoryIcon from '@/material-icons/400-24px/inventory_2.svg?react';
import MailIcon from '@/material-icons/400-24px/mail.svg?react';
import SearchIcon from '@/material-icons/400-24px/search.svg?react';
import SettingsIcon from '@/material-icons/400-24px/settings.svg?react';
import ShopIcon from '@/styles/bird-theme-svg/shop.svg?react';
import StarIcon from '@/styles/bird-theme-svg/star.svg?react';
import { openModal } from 'mastodon/actions/modal';
import { Column } from 'mastodon/components/column';
import { ColumnHeader } from 'mastodon/components/column_header';
import { Icon } from 'mastodon/components/icon';
import type { IconProp } from 'mastodon/components/icon';
import { LoadMore } from 'mastodon/components/load_more';
import { LoadingIndicator } from 'mastodon/components/loading_indicator';
import { useAppDispatch } from 'mastodon/store';

import { ItemImage } from './item_modal';

import type { RecordFilter, Wallet, WalletItem, WalletRecord } from './use_wallet';
import { useWallet, useWalletRecords } from './use_wallet';

const messages = defineMessages({
  wallet: { id: 'wallet.money', defaultMessage: 'Currency' },
  inventory: { id: 'wallet.inventory', defaultMessage: 'Inventory' },
});

const signed = (value: number) => (value > 0 ? `+${value.toLocaleString()}` : value.toLocaleString());

// 기록 종류마다 아이콘 (재화 기록 kind)
const KIND_ICONS: Record<string, { id: string; icon: IconProp }> = {
  content: { id: 'star', icon: StarIcon },
  purchase: { id: 'shop', icon: ShopIcon },
  use: { id: 'done', icon: DoneIcon },
  consume: { id: 'delete', icon: DeleteIcon },
  transfer: { id: 'mail', icon: MailIcon },
  attendance: { id: 'flag', icon: FlagIcon },
  toot: { id: 'edit', icon: EditIcon },
  randombox: { id: 'celebration', icon: CelebrationIcon },
  investigation: { id: 'search', icon: SearchIcon },
  admin: { id: 'settings', icon: SettingsIcon },
};

type Direction = 'gain' | 'spend' | 'item';

// 재화가 늘면 획득, 줄면 사용(차감), 재화 없이 아이템만 바뀌면 아이템
const directionOf = (record: WalletRecord): Direction => {
  if (record.money > 0) return 'gain';
  if (record.money < 0) return 'spend';
  return 'item';
};

const dayKey = (value: string | Date) => {
  const date = new Date(value);
  return `${date.getFullYear()}-${date.getMonth()}-${date.getDate()}`;
};

// 날짜 묶음 제목: 오늘 / 어제 / 10월 14일 (화)
const DayTitle: React.FC<{ iso: string }> = ({ iso }) => {
  const now = new Date();
  if (dayKey(iso) === dayKey(now)) return <FormattedMessage id='wallet.today' defaultMessage='Today' />;
  if (dayKey(iso) === dayKey(new Date(now.getTime() - 86_400_000))) return <FormattedMessage id='wallet.yesterday' defaultMessage='Yesterday' />;
  return <FormattedDate value={iso} month='long' day='numeric' weekday='short' />;
};

// 내역 한 줄: [종류 아이콘] 무엇(사유) / 종류 · 시각 / 아이템 칩 … 오른쪽에 +획득 / -사용 금액
// itemsOnly: 아이템 탭은 획득/사용 구분 없이 아이템 칩만 (재화 금액·색 없이)
const RecordRow: React.FC<{ record: WalletRecord; currency: string; itemsOnly?: boolean }> = ({ record, currency, itemsOnly = false }) => {
  const direction = itemsOnly ? 'item' : directionOf(record);
  const kind = KIND_ICONS[record.kind] ?? { id: 'diamond', icon: DiamondIcon };

  return (
    <li className={`wallet-record wallet-record--${direction}`}>
      <span className='wallet-record__icon'>
        <Icon id={kind.id} icon={kind.icon} />
      </span>

      <div className='wallet-record__main'>
        <span className='wallet-record__title'>{record.reason || record.kind_name}</span>
        <span className='wallet-record__meta'>
          {record.kind_name} · <FormattedTime value={record.created_at} hour='2-digit' minute='2-digit' />
        </span>
        {record.items.length > 0 && (
          <span className='wallet-record__items'>
            {record.items.map((item) => (
              <span key={item.name} className={item.count > 0 ? 'wallet-record__item' : 'wallet-record__item wallet-record__item--minus'}>
                {item.name} {signed(item.count)}
              </span>
            ))}
          </span>
        )}
      </div>

      {!itemsOnly && record.money !== 0 && (
        <span className='wallet-record__amount'>
          <strong>{signed(record.money)}</strong>
          <span>{currency}</span>
        </span>
      )}
    </li>
  );
};

const FILTERS: RecordFilter[] = ['all', 'gain', 'spend', 'items'];

const FilterLabel: React.FC<{ filter: RecordFilter }> = ({ filter }) => {
  switch (filter) {
  case 'gain':
    return <FormattedMessage id='wallet.filter.gain' defaultMessage='Earned' />;
  case 'spend':
    return <FormattedMessage id='wallet.filter.spend' defaultMessage='Spent' />;
  case 'items':
    return <FormattedMessage id='wallet.filter.items' defaultMessage='Items' />;
  default:
    return <FormattedMessage id='wallet.filter.all' defaultMessage='All' />;
  }
};

const MoneyView: React.FC<{ wallet: Wallet }> = ({ wallet }) => {
  const dispatch = useAppDispatch();
  const [filter, setFilter] = useState<RecordFilter>('all');
  const { records, loading, hasMore, loadMore } = useWalletRecords(filter);

  // 기록을 날짜별로 묶는다 (기록은 최신순)
  const groups = useMemo(
    () =>
      (records ?? []).reduce<{ key: string; iso: string; records: WalletRecord[] }[]>((list, record) => {
        const key = dayKey(record.created_at);
        const last = list[list.length - 1];
        if (last?.key === key) last.records.push(record);
        else list.push({ key, iso: record.created_at, records: [record] });
        return list;
      }, []),
    [records],
  );

  const openGift = useCallback(() => {
    dispatch(openModal({ modalType: 'MONEY_GIFT', modalProps: { money: wallet.money, currency: wallet.currency } }));
  }, [dispatch, wallet.money, wallet.currency]);

  return (
    <>
      <div className='wallet-page__padded'>
        <div className='wallet-card'>
          <span className='wallet-card__top'>
            <span className='wallet-card__label'>
              <FormattedMessage id='wallet.balance_named' defaultMessage='Your {currency}' values={{ currency: wallet.currency }} />
            </span>
            {wallet.transfer_enabled && (
              <button type='button' className='wallet-card__gift' onClick={openGift} disabled={wallet.money <= 0}>
                <Icon id='mail' icon={MailIcon} />
                <FormattedMessage id='item.gift' defaultMessage='Gift' />
              </button>
            )}
          </span>
          <span className='wallet-card__balance'>
            <Icon id='diamond' icon={DiamondIcon} />
            <strong>{wallet.money.toLocaleString()}</strong>
            <span>{wallet.currency}</span>
          </span>
          <span className='wallet-card__stats'>
            <span>
              <FormattedMessage id='wallet.total_gain' defaultMessage='Total earned' />
              <strong>{signed(wallet.gained)}</strong>
            </span>
            <span>
              <FormattedMessage id='wallet.total_spend' defaultMessage='Total spent' />
              <strong>{signed(wallet.spent)}</strong>
            </span>
          </span>
        </div>
      </div>

      <div className='notification__filter-bar wallet-page__filter'>
        {FILTERS.map((key) => (
          <button key={key} type='button' className={filter === key ? 'active' : undefined} onClick={() => { setFilter(key); }}>
            <FilterLabel filter={key} />
          </button>
        ))}
      </div>

      {records === null ? (
        <LoadingIndicator />
      ) : groups.length === 0 ? (
        <p className='wallet-page__empty'>
          <FormattedMessage id='wallet.no_records' defaultMessage='No history yet.' />
        </p>
      ) : (
        <>
          {groups.map((group) => (
            <section key={group.key} className='wallet-page__day'>
              <h3 className='wallet-page__day-title'>
                <DayTitle iso={group.iso} />
              </h3>
              <ul className='wallet-page__records'>
                {group.records.map((record) => <RecordRow key={record.id} record={record} currency={wallet.currency} itemsOnly={filter === 'items'} />)}
              </ul>
            </section>
          ))}
          {hasMore && <LoadMore onClick={loadMore} loading={loading} />}
        </>
      )}
    </>
  );
};

const InventoryView: React.FC<{ wallet: Wallet }> = ({ wallet }) => {
  const dispatch = useAppDispatch();

  const open = (item: WalletItem) => {
    dispatch(openModal({ modalType: 'INVENTORY_ITEM', modalProps: { item, transferEnabled: wallet.transfer_enabled } }));
  };

  // 상점과 같은 해리포터 분위기: 금빛 선 제목 + 양피지 카드 (개수는 금빛 배지, 메모는 이름 아래)
  return (
    <section className='system-section'>
      <h3 className='system-section__title'>
        <FormattedMessage id='wallet.inventory_title' defaultMessage='Belongings · {count}' values={{ count: wallet.item_count }} />
      </h3>
      {wallet.wearing && wallet.wearing.length > 0 && (
        <p className='wallet-page__wearing'>
          <FormattedMessage id='wallet.wearing' defaultMessage='Wearing' />: {wallet.wearing.map((wear) => wear.label).join(', ')}
        </p>
      )}
      {wallet.inventory.length === 0 ? (
        <p className='system-page__empty'>
          <FormattedMessage id='wallet.no_items' defaultMessage='No items yet.' />
        </p>
      ) : (
        <ul className='shop-page__items'>
          {wallet.inventory.map((item) => (
            <li key={item.name}>
              <button type='button' className='shop-card' onClick={() => { open(item); }}>
                <ItemImage item={item} count={item.count} />
                <span className='shop-card__name'>{item.name}</span>
                {item.note && <span className='shop-card__note'>{item.note}</span>}
              </button>
            </li>
          ))}
        </ul>
      )}
    </section>
  );
};

const WalletPage: React.FC<{ multiColumn: boolean }> = ({ multiColumn }) => {
  const intl = useIntl();
  const { section } = useParams<{ section: 'wallet' | 'inventory' }>();
  const wallet = useWallet();
  const inventory = section === 'inventory';
  const title = intl.formatMessage(inventory ? messages.inventory : messages.wallet);

  return (
    <Column bindToDocument={!multiColumn} label={title}>
      <ColumnHeader icon={inventory ? 'inventory' : 'diamond'} iconComponent={inventory ? InventoryIcon : DiamondIcon} title={title} multiColumn={multiColumn} showBackButton />

      <div className={inventory ? 'scrollable system-page shop-page' : 'scrollable wallet-page wallet-page--money'}>
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
