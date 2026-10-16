// 웹 '상점' 메뉴 (/shop): 상점마다 파는 아이템 양피지 카드 (시스템 화면 스타일). 누르면 구매 모달 (shop_item_modal)
import { useCallback, useEffect, useState } from 'react';

import { defineMessages, FormattedMessage, useIntl } from 'react-intl';

import { Helmet } from 'react-helmet';

import ShopIcon from '@/styles/bird-theme-svg/shop.svg?react';
import { openModal } from 'mastodon/actions/modal';
import { apiRequestGet } from 'mastodon/api';
import { Column } from 'mastodon/components/column';
import { ColumnHeader } from 'mastodon/components/column_header';
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

      {/* 시스템 화면과 같은 해리포터 분위기: 상점 이름은 금빛 선 제목, 아이템은 양피지 카드 */}
      <div className='scrollable system-page shop-page'>
        {!data ? (
          <LoadingIndicator />
        ) : (
          <>
            {data.shops.length === 0 && (
              <p className='system-page__empty'>
                <FormattedMessage id='shop.empty' defaultMessage='Nothing for sale right now.' />
              </p>
            )}

            {data.shops.map((shop) => (
              <section key={shop.id} className='system-section'>
                <h3 className='system-section__title'>{shop.name}</h3>
                {shop.description && <p className='shop-page__description'>{shop.description}</p>}
                <ul className='shop-page__items'>
                  {shop.items.map((item) => (
                    <li key={item.id}>
                      <button type='button' className='shop-card' onClick={() => { open(item); }}>
                        <ItemImage item={item} />
                        <span className='shop-card__name'>{item.name}</span>
                        <span className='shop-card__price'>
                          {item.price.toLocaleString()} {data.currency}
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
