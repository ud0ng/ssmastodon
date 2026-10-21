// 이벤트 열기 모달 (운영진, 여럿이 하는 컨텐츠): 참가자 모집하기 / 참가자 고르기 / 테스트 플레이 / 취소
//   모집: 시스템 계정이 팔로워 공개 툿으로 모집하고 모두에게 컨텐츠 알림 (기존 방식)
//   고르기: 모달에서 고른 참가자에게만 알림이 가고 바로 시작
//   테스트 플레이: 고른 참가자끼리 단체 DM 으로만 진행 — 다른 사람에게는 웹·앱 어디서도 보이지 않는다 (운영진은 목록에서 자물쇠로 관전)
// 마스토돈 확인 모달(safety-action-modal) 틀을 쓴다.
import { useCallback, useEffect, useMemo, useState } from 'react';

import { defineMessages, FormattedMessage, useIntl } from 'react-intl';

import { apiRequestGet, apiRequestPost } from 'mastodon/api';
import { Button } from 'mastodon/components/button';

import { apiErrorMessage } from './use_wallet';

interface Member {
  acct: string;
  name: string;
  avatar: string;
}

type Mode = 'menu' | 'pick' | 'test';

const messages = defineMessages({
  search: { id: 'event_open.search', defaultMessage: 'Search for a player' },
  failed: { id: 'event_open.failed', defaultMessage: 'Something went wrong. Please try again.' },
});

const EventOpenModal: React.FC<{
  gameKey: string;
  name: string;
  minPlayers?: number;
  maxPlayers?: number;
  joinMinutes?: number;
  onOpened: () => void;
  onClose: () => void;
}> = ({ gameKey, name, minPlayers = 2, maxPlayers = 4, joinMinutes = 30, onOpened, onClose }) => {
  const intl = useIntl();
  const [mode, setMode] = useState<Mode>('menu');
  const [members, setMembers] = useState<Member[]>([]);
  const [picked, setPicked] = useState<string[]>([]);
  const [query, setQuery] = useState('');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  // 고르기·테스트 플레이: 운영진 본인도 고를 수 있다
  useEffect(() => {
    if (mode === 'menu' || members.length > 0) return;
    apiRequestGet<Member[]>('v1/system/members', { include_me: '1' })
      .then(setMembers)
      .catch(() => {
        setMembers([]);
      });
  }, [mode, members.length]);

  const shown = useMemo(() => {
    const q = query.trim().toLowerCase();
    return q ? members.filter((member) => member.name.toLowerCase().includes(q) || member.acct.toLowerCase().includes(q)) : members;
  }, [members, query]);

  const send = useCallback(
    (openMode: 'recruit' | 'pick' | 'test') => {
      setBusy(true);
      setError(null);
      apiRequestPost(`v1/system/games/${gameKey}/open`, { mode: openMode, ...(openMode === 'recruit' ? {} : { accts: picked }) })
        .then(() => {
          onClose();
          onOpened();
          return true;
        })
        .catch((reason: unknown) => {
          setError(apiErrorMessage(reason) ?? intl.formatMessage(messages.failed));
        })
        .finally(() => {
          setBusy(false);
        });
    },
    [gameKey, picked, onClose, onOpened, intl],
  );

  const toggle = useCallback((acct: string) => {
    setPicked((current) => (current.includes(acct) ? current.filter((each) => each !== acct) : [...current, acct]));
  }, []);

  const back = useCallback(() => {
    setMode('menu');
    setError(null);
  }, []);

  const ready = picked.length >= minPlayers && picked.length <= maxPlayers;

  return (
    <div className='modal-root__modal safety-action-modal event-open-modal'>
      <div className='safety-action-modal__top'>
        <div className='safety-action-modal__confirmation'>
          <h1><FormattedMessage id='event_open.title' defaultMessage='Open event: {name}' values={{ name }} /></h1>
        </div>

        {mode === 'menu' ? (
          <div className='event-open-modal__choices'>
            <button type='button' className='event-open-modal__choice' disabled={busy} onClick={() => { send('recruit'); }}>
              <strong><FormattedMessage id='event_open.recruit' defaultMessage='Recruit players' /></strong>
              <span><FormattedMessage id='event_open.recruit_hint' defaultMessage='Recruits {min}–{max} players for {minutes} minutes.' values={{ minutes: joinMinutes, min: minPlayers, max: maxPlayers }} /></span>
            </button>
            <button type='button' className='event-open-modal__choice' disabled={busy} onClick={() => { setMode('pick'); }}>
              <strong><FormattedMessage id='event_open.pick' defaultMessage='Pick players' /></strong>
              <span><FormattedMessage id='event_open.pick_hint' defaultMessage='Pick {min}–{max} players.' values={{ min: minPlayers, max: maxPlayers }} /></span>
            </button>
            <button type='button' className='event-open-modal__choice' disabled={busy} onClick={() => { setMode('test'); }}>
              <strong><FormattedMessage id='event_open.test' defaultMessage='Test play' /></strong>
              <span><FormattedMessage id='event_open.test_hint' defaultMessage='Played in private, with no rewards.' /></span>
            </button>
          </div>
        ) : (
          <>
            <p className='event-open-modal__hint'>
              {mode === 'test'
                ? <FormattedMessage id='event_open.test_pick' defaultMessage='Pick the players. Nobody else can see this on the web or in apps; staff can watch it from the list with a lock icon.' />
                : <FormattedMessage id='event_open.pick_pick' defaultMessage='Pick the players. Only they are notified.' />}
            </p>
            <input
              type='text'
              className='event-open-modal__search'
              value={query}
              placeholder={intl.formatMessage(messages.search)}
              onChange={(event) => { setQuery(event.target.value); }}
            />
            <ul className='event-open-modal__members'>
              {shown.map((member) => (
                <li key={member.acct}>
                  <label className='event-open-modal__member'>
                    <input type='checkbox' checked={picked.includes(member.acct)} onChange={() => { toggle(member.acct); }} />
                    <img src={member.avatar} alt='' />
                    <span>{member.name}</span>
                  </label>
                </li>
              ))}
            </ul>
            <p className='event-open-modal__count'>
              <FormattedMessage id='event_open.count' defaultMessage='{count} picked ({min}–{max} players)' values={{ count: picked.length, min: minPlayers, max: maxPlayers }} />
            </p>
          </>
        )}

        {error && <p className='item-modal__error'>{error}</p>}
      </div>

      <div className='safety-action-modal__bottom'>
        <div className='safety-action-modal__actions'>
          {mode === 'menu' ? (
            <Button onClick={onClose} secondary><FormattedMessage id='event_open.cancel' defaultMessage='Cancel' /></Button>
          ) : (
            <>
              <Button onClick={back} secondary><FormattedMessage id='event_open.back' defaultMessage='Back' /></Button>
              <Button onClick={() => { send(mode); }} disabled={!ready || busy}><FormattedMessage id='event_open.start' defaultMessage='Start' /></Button>
            </>
          )}
        </div>
      </div>
    </div>
  );
};

// eslint-disable-next-line import/no-default-export
export default EventOpenModal;
