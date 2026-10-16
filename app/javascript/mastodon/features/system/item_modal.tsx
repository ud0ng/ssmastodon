// 인벤토리 아이템 모달: 그림·이름·개수·설명 + [선물] [버리기] [사용]
// 마스토돈 확인 모달(safety-action-modal) 틀을 그대로 쓴다. 선물 받을 사람은 검색창 컴포넌트(search).
import { useCallback, useEffect, useMemo, useState } from 'react';

import { defineMessages, FormattedMessage, useIntl } from 'react-intl';

import classNames from 'classnames';

import CancelIcon from '@/material-icons/400-24px/cancel-fill.svg?react';
import AddIcon from '@/material-icons/400-24px/add.svg?react';
import RemoveIcon from '@/material-icons/400-24px/remove.svg?react';
import SearchIcon from '@/material-icons/400-24px/search.svg?react';
import { apiRequestGet, apiRequestPost } from 'mastodon/api';
import { Button } from 'mastodon/components/button';
import { Icon } from 'mastodon/components/icon';
import { IconButton } from 'mastodon/components/icon_button';

import type { WalletItem } from './use_wallet';
import { apiErrorMessage, refreshWallet } from './use_wallet';

const messages = defineMessages({
  search: { id: 'item.search', defaultMessage: 'Search for someone' },
  count: { id: 'item.count', defaultMessage: 'Count' },
  clear: { id: 'search.clear', defaultMessage: 'Clear search' },
  less: { id: 'item.less', defaultMessage: 'One less' },
  more: { id: 'item.more', defaultMessage: 'One more' },
  failed: { id: 'item.failed', defaultMessage: 'Something went wrong. Please try again.' },
});

export interface Member {
  acct: string;
  name: string;
  avatar: string;
}

type Mode = 'menu' | 'use' | 'gift' | 'discard';

export const ItemImage: React.FC<{ item: Pick<WalletItem, 'name' | 'image'>; count?: number }> = ({ item, count }) => (
  <span className='wallet-page__item-image'>
    {item.image ? <img src={item.image} alt='' loading='lazy' /> : <span className='wallet-page__item-letter'>{item.name.trim().charAt(0)}</span>}
    {count !== undefined && <span className='wallet-page__item-count'>×{count}</span>}
  </span>
);

// 개수: − 숫자 + (마스토돈 IconButton), 오른쪽에 최대 개수
// unit: 재화 선물처럼 개수 대신 금액일 때 (라벨·최대 표시를 그 단위로)
export const CountInput: React.FC<{ value: number; max: number; onChange: (value: number) => void; unit?: string }> = ({ value, max, onChange, unit }) => {
  const intl = useIntl();
  const set = (next: number) => { onChange(Math.min(Math.max(next, 1), max)); };

  return (
    <div className='item-modal__count'>
      <span className='item-modal__count-label'>{unit ?? intl.formatMessage(messages.count)}</span>
      <div className='item-modal__stepper'>
        <IconButton icon='remove' iconComponent={RemoveIcon} title={intl.formatMessage(messages.less)} disabled={value <= 1} onClick={() => { set(value - 1); }} />
        <input
          type='text'
          inputMode='numeric'
          value={value}
          aria-label={intl.formatMessage(messages.count)}
          onChange={(event) => { set(Number(event.target.value.replace(/D/g, '')) || 1); }}
        />
        <IconButton icon='add' iconComponent={AddIcon} title={intl.formatMessage(messages.more)} disabled={value >= max} onClick={() => { set(value + 1); }} />
      </div>
      {unit ? (
        <span className='item-modal__count-max'>
          <FormattedMessage id='wallet.gift_max' defaultMessage='up to {max}' values={{ max: max.toLocaleString() }} />
        </span>
      ) : max < 99 && (
        <span className='item-modal__count-max'>
          <FormattedMessage id='item.count_max' defaultMessage='up to {max}' values={{ max }} />
        </span>
      )}
    </div>
  );
};

// 받을 사람: 오른쪽 위 검색창과 같은 입력칸 + 드롭다운 (search, search__popout)
export const GiftPicker: React.FC<{ picked: Member | null; onPick: (member: Member | null) => void }> = ({ picked, onPick }) => {
  const intl = useIntl();
  const [members, setMembers] = useState<Member[]>([]);
  const [query, setQuery] = useState('');
  const [expanded, setExpanded] = useState(false);
  const [selected, setSelected] = useState(-1);

  useEffect(() => {
    apiRequestGet<Member[]>('v1/system/members')
      .then(setMembers)
      .catch(() => {
        setMembers([]);
      });
  }, []);

  const shown = useMemo(() => {
    const q = query.trim().toLowerCase();
    return q ? members.filter((member) => member.name.toLowerCase().includes(q) || member.acct.toLowerCase().includes(q)) : members;
  }, [members, query]);

  const choose = useCallback(
    (member: Member) => {
      onPick(member);
      setQuery(member.name);
      setExpanded(false);
      setSelected(-1);
    },
    [onPick],
  );

  const handleChange = useCallback(
    (event: React.ChangeEvent<HTMLInputElement>) => {
      setQuery(event.target.value);
      setExpanded(true);
      setSelected(-1);
      onPick(null);
    },
    [onPick],
  );

  const handleClear = useCallback(() => {
    setQuery('');
    setSelected(-1);
    onPick(null);
  }, [onPick]);

  const handleKeyDown = useCallback(
    (event: React.KeyboardEvent<HTMLInputElement>) => {
      if (event.key === 'ArrowDown') {
        event.preventDefault();
        setExpanded(true);
        setSelected((current) => Math.min(current + 1, shown.length - 1));
      } else if (event.key === 'ArrowUp') {
        event.preventDefault();
        setSelected((current) => Math.max(current - 1, 0));
      } else if (event.key === 'Enter') {
        event.preventDefault();
        const member = shown[Math.max(selected, 0)];
        if (member) choose(member);
      } else if (event.key === 'Escape' && expanded) {
        event.stopPropagation();
        setExpanded(false);
      }
    },
    [shown, selected, expanded, choose],
  );

  return (
    <div className={classNames('search item-modal__gift', { active: expanded })}>
      <span className='search__icon' aria-hidden='true'>
        <Icon id='search' icon={SearchIcon} />
      </span>

      <input
        className='search__input'
        type='text'
        value={query}
        placeholder={intl.formatMessage(messages.search)}
        aria-label={intl.formatMessage(messages.search)}
        onChange={handleChange}
        onKeyDown={handleKeyDown}
        onFocus={() => { setExpanded(true); }}
        onBlur={() => { setExpanded(false); }}
      />

      {query && (
        <button type='button' className='search__clear' onClick={handleClear} aria-label={intl.formatMessage(messages.clear)}>
          <Icon id='times-circle' icon={CancelIcon} />
        </button>
      )}

      <div className='search__popout'>
        <div className='search__popout__menu'>
          {shown.length > 0 ? (
            shown.map((member, index) => (
              <button
                key={member.acct}
                type='button'
                className={classNames('search__popout__menu__item item-modal__member', { selected: selected === index || picked?.acct === member.acct })}
                onMouseDown={(event) => { event.preventDefault(); choose(member); }}
              >
                <img className='item-modal__avatar' src={member.avatar} alt='' />
                <span>{member.name}</span>
                <span className='item-modal__acct'>@{member.acct}</span>
              </button>
            ))
          ) : (
            <div className='search__popout__menu__message'>
              <FormattedMessage id='item.no_member' defaultMessage='No one found.' />
            </div>
          )}
        </div>
      </div>
    </div>
  );
};

const ItemModal: React.FC<{ item: WalletItem; transferEnabled: boolean; onClose: () => void }> = ({ item, transferEnabled, onClose }) => {
  const intl = useIntl();
  const [mode, setMode] = useState<Mode>('menu');
  const [count, setCount] = useState(1);
  const [receiver, setReceiver] = useState<Member | null>(null);
  const [busy, setBusy] = useState(false);
  const [result, setResult] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);

  const send = useCallback(
    (action: 'use' | 'gift' | 'discard', params: Record<string, unknown> = {}) => {
      setBusy(true);
      setError(null);
      apiRequestPost<{ message: string }>(`v1/system/items/${action}`, { name: item.name, ...params })
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
    },
    [item.name, intl],
  );

  const back = useCallback(() => {
    setMode('menu');
    setError(null);
  }, []);

  return (
    <div className='modal-root__modal safety-action-modal item-modal'>
      <div className='safety-action-modal__top'>
        <div className='item-modal__head'>
          <ItemImage item={item} count={result ? undefined : item.count} />
          <div className='safety-action-modal__confirmation'>
            <h1>{item.name}</h1>
            <p className='item-modal__description'>
              {item.description || <FormattedMessage id='item.no_description' defaultMessage='No description.' />}
            </p>
            {item.note && <p className='item-modal__note'>{item.note}</p>}
          </div>
        </div>

        {result ? (
          <p className='item-modal__result'>{result}</p>
        ) : (
          <>
            {mode === 'gift' && (
              <>
                <GiftPicker picked={receiver} onPick={setReceiver} />
                {item.count > 1 && <CountInput value={count} max={item.count} onChange={setCount} />}
              </>
            )}
            {mode === 'use' && (
              <p className='item-modal__ask'>
                <FormattedMessage id='item.use_confirm' defaultMessage='Use one {name}?' values={{ name: item.name }} />
                {item.stat && item.stat_value && (
                  <span className='item-modal__effect'>
                    <FormattedMessage id='item.use_effect' defaultMessage='{stat} {value}' values={{ stat: item.stat, value: item.stat_value }} />
                  </span>
                )}
              </p>
            )}
            {mode === 'discard' && (
              <>
                <p className='item-modal__ask'>
                  <FormattedMessage id='item.discard_confirm' defaultMessage='Discarded items are gone for good.' />
                </p>
                {item.count > 1 && <CountInput value={count} max={item.count} onChange={setCount} />}
              </>
            )}
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
          ) : mode === 'menu' ? (
            // 세로 모달: [사용] 한 줄, [선물] [버리기] 한 줄, 맨 아래 취소
            <div className='item-modal__menu'>
              {item.usable && (
                <Button block onClick={() => { setMode('use'); }}>
                  <FormattedMessage id='item.use' defaultMessage='Use' />
                </Button>
              )}
              <div className='item-modal__menu-row'>
                {transferEnabled && (
                  <Button secondary block onClick={() => { setMode('gift'); }}>
                    <FormattedMessage id='item.gift' defaultMessage='Gift' />
                  </Button>
                )}
                <Button secondary block onClick={() => { setMode('discard'); }}>
                  <FormattedMessage id='item.discard' defaultMessage='Discard' />
                </Button>
              </div>
              <button type='button' onClick={onClose} className='link-button'>
                <FormattedMessage id='confirmation_modal.cancel' defaultMessage='Cancel' />
              </button>
            </div>
          ) : (
            <>
              <button type='button' onClick={back} className='link-button'>
                <FormattedMessage id='column_back_button.label' defaultMessage='Back' />
              </button>
              <div className='spacer' />
              {mode === 'use' && (
                <Button disabled={busy} onClick={() => { send('use'); }}>
                  <FormattedMessage id='item.use' defaultMessage='Use' />
                </Button>
              )}
              {mode === 'gift' && (
                <Button disabled={busy || !receiver} onClick={() => { send('gift', { acct: receiver?.acct, count }); }}>
                  <FormattedMessage id='item.gift_send' defaultMessage='Send gift' />
                </Button>
              )}
              {mode === 'discard' && (
                <Button dangerous disabled={busy} onClick={() => { send('discard', { count }); }}>
                  <FormattedMessage id='item.discard' defaultMessage='Discard' />
                </Button>
              )}
            </>
          )}
        </div>
      </div>
    </div>
  );
};

export default ItemModal;
