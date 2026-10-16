// 웹 '상점' 메뉴 (/shop): 상점마다 파는 아이템 카드. 누르면 구매 모달 (shop_item_modal)
import { useCallback, useEffect, useState } from 'react';

import { defineMessages, FormattedMessage, useIntl } from 'react-intl';

import { Helmet } from 'react-helmet';

import DiamondIcon from '@/material-icons/400-24px/diamond.svg?react';
import ShopIcon from '@/styles/bird-theme-svg/shop.svg?react';
import { openModal } from 'mastodon/actions/modal';
import { apiRequestGet } from 'mastodon/api';
import { Column } from 'mastodon/components/column';
import { ColumnHeader } from 'mastodon/components/column_header';
import { Icon } from 'mastodon/components/icon';
import { LoadingIndicator } from 'mastodon/components/loading_indicator';
import { useAppDispatch } from 'mastodon/store';

import { ItemImage } from './item_modal';
import { CHANGED_EVENT } from './use_wallet';

const messages = defineMessages({
  title: { id: 'navigation_bar.shop', defaultMessage: 'Shop' },
});

export interface ShopItem {
  id: string;
  name: string;
  price: number;
  description: string;
  usable: boolean;
  image: string | null;
}

interface Shop {
  id: string;
  name: string;
  description: string;
  items: ShopItem[];
}

interface ShopData {
  currency: string;
  money: number;
  shops: Shop[];
}

const ShopPage: React.FC<{ multiColumn: boolean }> = ({ multiColumn }) => {
  const intl = useIntl();
  const dispatch = useAppDispatch();
  const [data, setData] = useState<ShopData | null>(null);
  const title = intl.formatMessage(messages.title);

  const load = useCallback(() => {
    apiRequestGet<ShopData>('v1/system/shop')
      .then(setData)
      .catch(() => {
        setData({ currency: '', money: 0, shops: [] });
      });
  }, []);

  useEffect(() => {
    load();
    window.addEventListener(CHANGED_EVENT, load);

    return () => {
      window.removeEventListener(CHANGED_EVENT, load);
    };
  }, [load]);

  const open = useCallback(
    (item: ShopItem) => {
      if (!data) return;
      dispatch(openModal({ modalType: 'SHOP_ITEM', modalProps: { item, currency: data.currency, money: data.money } }));
    },
    [dispatch, data],
  );

  return (
    <Column bindToDocument={!multiColumn} label={title}>
      <ColumnHeader icon='shop' iconComponent={ShopIcon} title={title} multiColumn={multiColumn} />

      <div className='scrollable wallet-page'>
        {!data ? (
          <LoadingIndicator />
        ) : (
          <>
            <div className='wallet-page__summary'>
              <Icon id='diamond' icon={DiamondIcon} />
              <strong>{data.money.toLocaleString()}</strong>
              <span>{data.currency}</span>
            </div>

            {data.shops.length === 0 && (
              <p className='wallet-page__empty'>
                <FormattedMessage id='shop.empty' defaultMessage='Nothing for sale right now.' />
              </p>
            )}

            {data.shops.map((shop) => (
              <section key={shop.id} className='shop-page__shop'>
                <h3 className='wallet-page__title'>{shop.name}</h3>
                {shop.description && <p className='shop-page__description'>{shop.description}</p>}
                <ul className='wallet-page__items'>
                  {shop.items.map((item) => (
                    <li key={item.id}>
                      <button type='button' className='wallet-page__item' onClick={() => { open(item); }}>
                        <ItemImage item={item} />
                        <span className='wallet-page__item-name'>{item.name}</span>
                        <span className='shop-page__price'>
                          <Icon id='diamond' icon={DiamondIcon} />
                          {item.price.toLocaleString()}
                        </span>
                      </button>
                    </li>
                  ))}
                </ul>
              </section>
            ))}
          </>
        )}
      </div>

      <Helmet>
        <title>{title}</title>
        <meta name='robots' content='noindex' />
      </Helmet>
    </Column>
  );
};

export default ShopPage;
