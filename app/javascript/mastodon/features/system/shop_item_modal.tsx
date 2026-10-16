// 상점 아이템 모달: 그림·이름·설명·가격 + 개수 → [구매]
import { useCallback, useState } from 'react';

import { defineMessages, FormattedMessage, useIntl } from 'react-intl';

import DiamondIcon from '@/material-icons/400-24px/diamond.svg?react';
import { apiRequestPost } from 'mastodon/api';
import { Button } from 'mastodon/components/button';
import { Icon } from 'mastodon/components/icon';

import { CountInput, ItemImage } from './item_modal';
import type { ShopItem } from './shop';
import { apiErrorMessage, refreshWallet } from './use_wallet';

const messages = defineMessages({
  failed: { id: 'item.failed', defaultMessage: 'Something went wrong. Please try again.' },
});

const MAX_COUNT = 99;

const ShopItemModal: React.FC<{ item: ShopItem; currency: string; money: number; onClose: () => void }> = ({ item, currency, money, onClose }) => {
  const intl = useIntl();
  const [count, setCount] = useState(1);
  const [busy, setBusy] = useState(false);
  const [result, setResult] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const total = item.price * count;

  const buy = useCallback(() => {
    setBusy(true);
    setError(null);
    apiRequestPost<{ message: string }>('v1/system/shop/purchase', { item_id: item.id, count })
      .then(({ message }) => {
        setResult(message);
        refreshWallet();
        return message;
      })
      .catch((reason: unknown) => {
        setError(apiErrorMessage(reason) ?? intl.formatMessage(messages.failed));
      })
      .finally(() => {
        setBusy(false);
      });
  }, [item.id, count, intl]);

  return (
    <div className='modal-root__modal safety-action-modal item-modal'>
      <div className='safety-action-modal__top'>
        <div className='item-modal__head'>
          <ItemImage item={item} />
          <div className='safety-action-modal__confirmation'>
            <h1>{item.name}</h1>
            <p className='item-modal__description'>
              {item.description || <FormattedMessage id='item.no_description' defaultMessage='No description.' />}
            </p>
          </div>
        </div>

        {result ? (
          <p className='item-modal__result'>{result}</p>
        ) : (
          <>
            <CountInput value={count} max={MAX_COUNT} onChange={setCount} />
            <p className='item-modal__total'>
              <Icon id='diamond' icon={DiamondIcon} />
              <strong>{total.toLocaleString()}</strong> {currency}
              <span className='item-modal__money'>
                <FormattedMessage id='shop.have' defaultMessage='(you have {money})' values={{ money: money.toLocaleString() }} />
              </span>
            </p>
            {error && <p className='item-modal__error'>{error}</p>}
          </>
        )}
      </div>

      <div className='safety-action-modal__bottom'>
        <div className='safety-action-modal__actions'>
          {result ? (
            <>
              <div className='spacer' />
              {/* eslint-disable-next-line jsx-a11y/no-autofocus -- we are in a modal and thus autofocusing is justified */}
              <Button onClick={onClose} autoFocus>
                <FormattedMessage id='item.done' defaultMessage='Done' />
              </Button>
            </>
          ) : (
            <>
              <button type='button' onClick={onClose} className='link-button'>
                <FormattedMessage id='confirmation_modal.cancel' defaultMessage='Cancel' />
              </button>
              <div className='spacer' />
              <Button disabled={busy || total > money} onClick={buy}>
                <FormattedMessage id='shop.buy' defaultMessage='Buy' />
              </Button>
            </>
          )}
        </div>
      </div>
    </div>
  );
};

export default ShopItemModal;
