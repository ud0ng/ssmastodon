// 컨텐츠 세부 화면 [시작하기] 모달: 상대(여럿이 하는 컨텐츠면 여러 명) 골라 신청 → '@시스템 @상대 [명령어]' 툿 (board.sendCommand)
// 시스템이 판(방)을 만들면 바로 그 컨텐츠 방으로 간다.
import { useCallback, useEffect, useMemo, useState } from 'react';

import { defineMessages, FormattedMessage, useIntl } from 'react-intl';

import { useHistory } from 'react-router-dom';

import { apiRequestGet } from 'mastodon/api';
import { Button } from 'mastodon/components/button';
import { ICONS } from 'mastodon/components/content_card';

import { sendCommand, waitForSession } from './board';

const messages = defineMessages({
  search: { id: 'system.game.search', defaultMessage: 'Find a member' },
});

interface Member {
  acct: string;
  name: string;
  avatar: string;
  house: { name: string; color: string; emoji: string } | null;
}

interface Props {
  gameKey: string;
  name: string;
  maxOpponents: number;
  onClose: () => void;
}

const ChallengeModal: React.FC<Props> = ({ gameKey, name, maxOpponents, onClose }) => {
  const intl = useIntl();
  const history = useHistory();
  const [members, setMembers] = useState<Member[]>([]);
  const [picked, setPicked] = useState<string[]>([]);
  const [query, setQuery] = useState('');
  const [busy, setBusy] = useState(false);
  const [sent, setSent] = useState(false);
  const [failed, setFailed] = useState(false);

  useEffect(() => {
    apiRequestGet<Member[]>('v1/system/members')
      .then((list) => {
        setMembers(list);
        return list;
      })
      .catch(() => {
        setMembers([]);
      });
  }, []);

  const shown = useMemo(() => {
    const q = query.trim().toLowerCase();
    return q ? members.filter((member) => member.name.toLowerCase().includes(q) || member.acct.toLowerCase().includes(q)) : members;
  }, [members, query]);

  const toggle = useCallback(
    (acct: string) => {
      setPicked((current) => {
        if (current.includes(acct)) return current.filter((item) => item !== acct);
        if (maxOpponents === 1) return [acct];
        return current.length >= maxOpponents ? current : [...current, acct];
      });
    },
    [maxOpponents],
  );

  const send = useCallback(() => {
    setBusy(true);
    setFailed(false);
    sendCommand({ kind: gameKey, opponents: picked })
      .then(() => waitForSession(gameKey))
      .then((sessionId) => {
        if (sessionId) {
          onClose();
          history.push(`/system/sessions/${sessionId}`);
        } else {
          setSent(true);
        }
        return sessionId;
      })
      .catch(() => {
        setFailed(true);
      })
      .finally(() => {
        setBusy(false);
      });
  }, [gameKey, picked, onClose, history]);

  return (
    <div className='modal-root__modal safety-action-modal challenge-modal'>
      <div className='safety-action-modal__top'>
        <div className='challenge-modal__head'>
          <span className='challenge-modal__icon' aria-hidden>{ICONS[gameKey] ?? '📜'}</span>
          <div className='safety-action-modal__confirmation'>
            <h1>{name}</h1>
            <p>
              {maxOpponents > 1 ? (
                <FormattedMessage id='system.game.pick_many' defaultMessage='Pick up to {max} people' values={{ max: maxOpponents }} />
              ) : (
                <FormattedMessage id='system.game.pick_one' defaultMessage='Pick an opponent' />
              )}
            </p>
          </div>
        </div>

        {sent ? (
          <p className='challenge-modal__result'>
            <FormattedMessage id='system.game.sent' defaultMessage='Sent. The system will answer in a moment.' />
          </p>
        ) : (
          <>
            <input
              className='challenge-modal__search'
              type='search'
              value={query}
              onChange={(event) => { setQuery(event.target.value); }}
              placeholder={intl.formatMessage(messages.search)}
              aria-label={intl.formatMessage(messages.search)}
            />
            <div className='system-newgame__members challenge-modal__members'>
              {shown.map((member) => {
                const index = picked.indexOf(member.acct);
                return (
                  <button
                    key={member.acct}
                    type='button'
                    className={index >= 0 ? 'system-member system-member--picked' : 'system-member'}
                    style={{ '--house-color': member.house?.color || '#6b5b3e' } as React.CSSProperties}
                    onClick={() => { toggle(member.acct); }}
                  >
                    <img src={member.avatar} alt='' />
                    <span className='system-member__name'>{member.name}</span>
                    {member.house && <span className='system-member__house'>{member.house.name}</span>}
                    {index >= 0 && maxOpponents > 1 && <span className='system-member__order'>{index + 1}</span>}
                  </button>
                );
              })}
            </div>
            {gameKey === 'quidditch' && picked.length > 1 && (
              <p className='hint'>
                <FormattedMessage id='system.game.teams_hint' defaultMessage='You and the first {half} picked are one team.' values={{ half: Math.max(Math.floor((picked.length + 1) / 2) - 1, 0) }} />
              </p>
            )}
            {failed && (
              <p className='item-modal__error'>
                <FormattedMessage id='item.failed' defaultMessage='Something went wrong. Please try again.' />
              </p>
            )}
          </>
        )}
      </div>

      <div className='safety-action-modal__bottom'>
        <div className='safety-action-modal__actions'>
          {sent ? (
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
              <Button disabled={busy || picked.length === 0} onClick={send}>
                <FormattedMessage id='system.game.invite' defaultMessage='Challenge' />
              </Button>
            </>
          )}
        </div>
      </div>
    </div>
  );
};

// eslint-disable-next-line import/no-default-export
export default ChallengeModal;
