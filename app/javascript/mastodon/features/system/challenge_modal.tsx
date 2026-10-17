// 컨텐츠 세부 화면 [시작하기] 모달: 상대(여럿이 하는 컨텐츠면 여러 명) 골라 신청 → '@시스템 @상대 [명령어]' 툿 (board.sendCommand)
// 시스템이 판(방)을 만들면 바로 그 컨텐츠 방으로 간다.
import { useCallback, useEffect, useMemo, useState } from 'react';

import { defineMessages, FormattedMessage, useIntl } from 'react-intl';

import { useHistory } from 'react-router-dom';

import { apiRequestGet } from 'mastodon/api';
import { Button } from 'mastodon/components/button';

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
  // 신청자를 뺀 최소 상대 수 (퀴디치 같은 팀 대결은 최소 인원 - 1)
  minOpponents?: number;
  // 팀 대결(퀴디치): 우리 팀을 먼저 고르고 상대 팀을 고른다
  team?: boolean;
  // 팀 인원이 달라도 되는 팀 대결(도둑 지도): 우리 팀은 1명부터, 상대 팀은 우리 팀 인원 이상 ~ 최대
  unevenTeams?: boolean;
  onClose: () => void;
}

const ChallengeModal: React.FC<Props> = ({ gameKey, name, maxOpponents, minOpponents = 1, team = false, unevenTeams = false, onClose }) => {
  const intl = useIntl();
  const history = useHistory();
  const [members, setMembers] = useState<Member[]>([]);
  const [picked, setPicked] = useState<string[]>([]);
  // 팀 대결: 1단계(우리 팀 = picked) → 2단계(상대 팀 = rivals)
  const [rivals, setRivals] = useState<string[]>([]);
  const [step, setStep] = useState<'mine' | 'rivals'>('mine');
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
    const pool = team && step === 'rivals' ? members.filter((member) => !picked.includes(member.acct)) : members;
    return q ? pool.filter((member) => member.name.toLowerCase().includes(q) || member.acct.toLowerCase().includes(q)) : pool;
  }, [members, query, team, step, picked]);

  // 팀 대결 인원: 신청자를 포함한 전체가 짝수이고 양 팀이 같다. 우리 팀(나 포함) 크기 = 팀원 수 + 1
  const maxTotal = maxOpponents + 1;
  const minTotal = minOpponents + 1;
  // 인원이 다른 팀 대결: 상대 팀 최대 = (최대 상대 수 + 1) / 2
  const rivalMax = unevenTeams ? Math.floor(maxTotal / 2) + (maxTotal % 2) : 0;
  const minMates = unevenTeams ? 0 : Math.max(Math.ceil(minTotal / 2) - 1, 1);
  const maxMates = unevenTeams ? rivalMax - 1 : Math.max(Math.floor(maxTotal / 2) - 1, minMates);
  const teamSize = picked.length + 1;
  const rivalCap = unevenTeams ? rivalMax : teamSize;

  const toggle = useCallback(
    (acct: string) => {
      if (team && step === 'rivals') {
        setRivals((current) => {
          if (current.includes(acct)) return current.filter((item) => item !== acct);
          return current.length >= rivalCap ? current : [...current, acct];
        });
        return;
      }

      setPicked((current) => {
        if (current.includes(acct)) return current.filter((item) => item !== acct);
        if (team) return current.length >= maxMates ? current : [...current, acct];
        if (maxOpponents === 1) return [acct];
        return current.length >= maxOpponents ? current : [...current, acct];
      });
    },
    [team, step, rivalCap, maxMates, maxOpponents],
  );

  const send = useCallback(() => {
    setBusy(true);
    setFailed(false);
    sendCommand({ kind: gameKey, opponents: team ? [...picked, ...rivals] : picked, ...(unevenTeams ? { team_size: picked.length + 1 } : {}) })
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
  }, [gameKey, picked, rivals, team, onClose, history]);

  return (
    <div className='modal-root__modal safety-action-modal challenge-modal'>
      <div className='safety-action-modal__top'>
        <div className='challenge-modal__head'>
          <div className='safety-action-modal__confirmation'>
            <h1>{name}</h1>
            <p>
              {team ? (
                step === 'mine' ? (
                  <FormattedMessage id='system.game.pick_team_mine' defaultMessage='Pick your team (you plus {min}-{max} people)' values={{ min: minMates, max: maxMates }} />
                ) : unevenTeams ? (
                  <FormattedMessage id='system.game.pick_team_rival_range' defaultMessage='Pick {min}-{max} people for the other team' values={{ min: teamSize, max: rivalMax }} />
                ) : (
                  <FormattedMessage id='system.game.pick_team_rival' defaultMessage='Pick {count} people for the other team' values={{ count: teamSize }} />
                )
              ) : maxOpponents > 1 ? (
                <FormattedMessage id='system.game.pick_range' defaultMessage='Pick {min}-{max} people' values={{ min: minOpponents, max: maxOpponents }} />
              ) : (
                <FormattedMessage id='system.game.pick_one' defaultMessage='Pick an opponent' />
              )}
            </p>
          </div>
        </div>

        {team && !sent && (
          <div className='challenge-modal__steps'>
            <span className={step === 'mine' ? 'challenge-modal__step challenge-modal__step--on' : 'challenge-modal__step'}>
              <FormattedMessage id='system.game.team_mine' defaultMessage='Your team' /> {picked.length + 1}
            </span>
            <span className={step === 'rivals' ? 'challenge-modal__step challenge-modal__step--on' : 'challenge-modal__step'}>
              <FormattedMessage id='system.game.team_rival' defaultMessage='Other team' /> {unevenTeams ? `${rivals.length}/${teamSize}~${rivalMax}` : `${rivals.length}/${teamSize}`}
            </span>
          </div>
        )}

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
                const list = team && step === 'rivals' ? rivals : picked;
                const index = list.indexOf(member.acct);
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
                    {index >= 0 && (team || maxOpponents > 1) && <span className='system-member__order'>{index + 1}</span>}
                  </button>
                );
              })}
            </div>
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
              {team && step === 'rivals' ? (
                <button type='button' onClick={() => { setStep('mine'); setRivals([]); }} className='link-button'>
                  <FormattedMessage id='system.game.back' defaultMessage='Back' />
                </button>
              ) : (
                <button type='button' onClick={onClose} className='link-button'>
                  <FormattedMessage id='confirmation_modal.cancel' defaultMessage='Cancel' />
                </button>
              )}
              <div className='spacer' />
              {team && step === 'mine' ? (
                <Button disabled={picked.length < minMates} onClick={() => { setQuery(''); setStep('rivals'); }}>
                  <FormattedMessage id='system.game.next' defaultMessage='Next' />
                </Button>
              ) : (
                <Button disabled={busy || (team ? (unevenTeams ? rivals.length < teamSize || rivals.length > rivalMax : rivals.length !== teamSize) : picked.length < minOpponents)} onClick={send}>
                  <FormattedMessage id='system.game.invite' defaultMessage='Challenge' />
                </Button>
              )}
            </>
          )}
        </div>
      </div>
    </div>
  );
};

// eslint-disable-next-line import/no-default-export
export default ChallengeModal;
