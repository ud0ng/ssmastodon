// 재화 선물 모달 (재화 화면의 보유 재화 카드 [선물]): 받을 사람(검색창) + 금액 → [선물하기]
import { useCallback, useState } from 'react';

import { defineMessages, FormattedMessage, useIntl } from 'react-intl';

import DiamondIcon from '@/material-icons/400-24px/diamond.svg?react';
import { apiRequestPost } from 'mastodon/api';
import { Button } from 'mastodon/components/button';
import { Icon } from 'mastodon/components/icon';

import type { Member } from './item_modal';
import { CountInput, GiftPicker } from './item_modal';
import { apiErrorMessage, refreshWallet } from './use_wallet';

const messages = defineMessages({
  failed: { id: 'item.failed', defaultMessage: 'Something went wrong. Please try again.' },
});

const MoneyGiftModal: React.FC<{ money: number; currency: string; onClose: () => void }> = ({ money, currency, onClose }) => {
  const intl = useIntl();
  const [receiver, setReceiver] = useState<Member | null>(null);
  const [amount, setAmount] = useState(1);
  const [busy, setBusy] = useState(false);
  const [result, setResult] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);

  const send = useCallback(() => {
    setBusy(true);
    setError(null);
    apiRequestPost<{ message: string }>('v1/system/wallet/gift', { acct: receiver?.acct, amount })
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
  }, [receiver, amount, intl]);

  return (
    <div className='modal-root__modal safety-action-modal item-modal'>
      <div className='safety-action-modal__top'>
        <div className='item-modal__head'>
          <span className='item-modal__coin'>
            <Icon id='diamond' icon={DiamondIcon} />
          </span>
          <div className='safety-action-modal__confirmation'>
            <h1>
              <FormattedMessage id='wallet.gift_title' defaultMessage='Gift {currency}' values={{ currency }} />
            </h1>
            <p className='item-modal__description'>
              <FormattedMessage id='wallet.gift_have' defaultMessage='You have {money} {currency}.' values={{ money: money.toLocaleString(), currency }} />
            </p>
          </div>
        </div>

        {result ? (
          <p className='item-modal__result'>{result}</p>
        ) : (
          <>
            <GiftPicker picked={receiver} onPick={setReceiver} />
            <CountInput value={amount} max={Math.max(money, 1)} onChange={setAmount} unit={currency} />
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
              <Button disabled={busy || !receiver || amount > money} onClick={send}>
                <FormattedMessage id='item.gift_send' defaultMessage='Send gift' />
              </Button>
            </>
          )}
        </div>
      </div>
    </div>
  );
};

export default MoneyGiftModal;
