// 대기방에서 캐릭터를 더 초대하는 모달 (초대하기·테스트 플레이): 실수로 거절한 사람이나 나중에 더해지는 사람을 위해.
// 이미 초대받은(대기방에 있는) 사람은 목록에서 빠진다. 마스토돈 확인 모달(safety-action-modal) 틀을 쓴다.
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

const messages = defineMessages({
  search: { id: 'event_open.search', defaultMessage: 'Search for a player' },
  failed: { id: 'event_open.failed', defaultMessage: 'Something went wrong. Please try again.' },
});

const EventInviteModal: React.FC<{
  sessionId: string;
  exclude: string[];
  onInvited: () => void;
  onClose: () => void;
}> = ({ sessionId, exclude, onInvited, onClose }) => {
  const intl = useIntl();
  const [members, setMembers] = useState<Member[]>([]);
  const [picked, setPicked] = useState<string[]>([]);
  const [query, setQuery] = useState('');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    apiRequestGet<Member[]>('v1/system/members', { include_me: '1' })
      .then(setMembers)
      .catch(() => {
        setMembers([]);
      });
  }, []);

  const shown = useMemo(() => {
    const q = query.trim().toLowerCase();
    const rest = members.filter((member) => !exclude.includes(member.acct));
    return q ? rest.filter((member) => member.name.toLowerCase().includes(q) || member.acct.toLowerCase().includes(q)) : rest;
  }, [members, query, exclude]);

  const toggle = useCallback((acct: string) => {
    setPicked((current) => (current.includes(acct) ? current.filter((each) => each !== acct) : [...current, acct]));
  }, []);

  const send = useCallback(() => {
    setBusy(true);
    setError(null);
    apiRequestPost(`v1/system/sessions/${sessionId}/invite_more`, { accts: picked })
      .then(() => {
        onClose();
        onInvited();
        return true;
      })
      .catch((reason: unknown) => {
        setError(apiErrorMessage(reason) ?? intl.formatMessage(messages.failed));
      })
      .finally(() => {
        setBusy(false);
      });
  }, [sessionId, picked, onClose, onInvited, intl]);

  return (
    <div className='modal-root__modal safety-action-modal event-open-modal'>
      <div className='safety-action-modal__top'>
        <div className='safety-action-modal__confirmation'>
          <h1><FormattedMessage id='event_invite.title' defaultMessage='Invite more characters' /></h1>
        </div>
        <p className='event-open-modal__hint'>
          <FormattedMessage id='event_invite.hint' defaultMessage='Pick the characters to invite to this waiting room. Only they are notified.' />
        </p>
        <input type='text' className='event-open-modal__search' value={query} placeholder={intl.formatMessage(messages.search)} onChange={(event) => { setQuery(event.target.value); }} />
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
          <FormattedMessage id='event_invite.count' defaultMessage='{count} picked' values={{ count: picked.length }} />
        </p>
        {error && <p className='item-modal__error'>{error}</p>}
      </div>

      <div className='safety-action-modal__bottom'>
        <div className='safety-action-modal__actions'>
          <Button onClick={onClose} secondary><FormattedMessage id='event_open.cancel' defaultMessage='Cancel' /></Button>
          <Button onClick={send} disabled={picked.length === 0 || busy}><FormattedMessage id='event_invite.send' defaultMessage='Invite' /></Button>
        </div>
      </div>
    </div>
  );
};

// eslint-disable-next-line import/no-default-export
export default EventInviteModal;
