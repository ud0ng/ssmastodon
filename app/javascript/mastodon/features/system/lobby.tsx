// 여럿이 하는 컨텐츠 대기방 (웹게임 느낌): 전체 화면 어두운 스포트라이트 배경에 참가자 아바타, 아래에 소속 엠블럼 | 이름, 준비하기 / 준비 취소.
//   마스토돈 메뉴는 왼쪽에 아이콘만 남는다 (body.layout-game-stage, styles/mastodon/_game_stage.scss).
//   화면 아래에는 채팅 입력창, 그 위로 채팅이 말풍선으로 (호버하면 스크롤바).
//   모두 준비하면 검은 오버레이와 카운트다운, 누구든 [취소]하면 다시 준비하기 화면.
//   운영진은 모든 캐릭터의 준비·준비 취소를 바꿀 수 있다.
import { useCallback, useEffect, useLayoutEffect, useMemo, useRef, useState } from 'react';

import { defineMessages, FormattedMessage, useIntl } from 'react-intl';

import { createPortal } from 'react-dom';

import { openModal } from 'mastodon/actions/modal';
import { apiRequestPost } from 'mastodon/api';

import { Countdown } from 'mastodon/components/countdown';
import { useAppDispatch } from 'mastodon/store';

import { TokenAvatar, TokenName } from './game_token';
import { apiErrorMessage } from './use_wallet';

export interface LobbyPlayer {
  account_id: string;
  acct: string;
  name: string;
  avatar: string;
  house: { name: string; color: string } | null;
  ready: boolean;
  // 초대받고 아직 수락하지 않음 ('대기중...')
  waiting?: boolean;
  // 팀이 있는 이벤트(도둑 지도)의 팀
  team?: 'student' | 'prefect' | null;
}

// 팀이 있는 이벤트의 대기실: 위·아래 영역으로 나뉜 팀과 [팀 변경]
export interface LobbyTeams {
  names: Record<'student' | 'prefect', string>;
  caps: Record<'student' | 'prefect', number>;
  counts: Record<'student' | 'prefect', number>;
  mine: 'student' | 'prefect' | null;
  can_change: boolean;
  change_blocked: boolean;
}

export interface LobbyData {
  min: number;
  max: number;
  countdown_seconds: number;
  start_at: string | null;
  now: string;
  can_manage: boolean;
  // 모집 중(참가 받는 동안)이면 준비 대신 남은 모집 시간을 보여 준다
  recruiting?: boolean;
  // 아직 참가하지 않은 사람은 [참여하기], 참가한 사람은 [참여 취소] (시작 전에만)
  can_join?: boolean;
  can_leave?: boolean;
  // 초대한 이벤트: 운영진·연 사람은 캐릭터를 더 초대할 수 있다
  can_invite?: boolean;
  teams?: LobbyTeams | null;
  // 정원 초과·동시 진행·하루 제한으로 참가할 수 없을 때의 이유 (버튼이 '참가 불가'로 보이고 누르면 모달)
  join_block?: string | null;
  // 초대한 이벤트: 초대받은 사람은 대기방에서 [수락][거절]
  invite?: boolean;
  can_respond?: boolean;
  recruit_ends_at?: string | null;
  me: string | null;
  players: LobbyPlayer[];
}

export interface LobbyMessage {
  id: string;
  chat?: boolean;
  mine: boolean;
  name: string;
  acct?: string;
  avatar: string;
  text: string;
  created_at: string;
}

const messages = defineMessages({
  placeholder: { id: 'lobby.placeholder', defaultMessage: 'Say something to the room' },
  send: { id: 'lobby.send', defaultMessage: 'Send' },
  joinFailed: { id: 'lobby.join_failed', defaultMessage: 'Could not join' },
  ok: { id: 'lobby.ok', defaultMessage: 'OK' },
  noRewardTitle: { id: 'lobby.no_reward_title', defaultMessage: 'No points or rewards today' },
});

const STAGE_BODY_CLASS = 'layout-game-stage';

// 대기방에 있는 동안: 메뉴를 아이콘만 남기고 화면 전체를 대기방이 쓴다
export const useStageLayout = (active: boolean) => {
  useEffect(() => {
    if (!active) return undefined;
    document.body.classList.add(STAGE_BODY_CLASS);
    return () => {
      document.body.classList.remove(STAGE_BODY_CLASS);
    };
  }, [active]);
};

// 서버 시계 기준으로 남은 초 (내 컴퓨터 시계가 달라도 같게 센다)
const useRemaining = (lobby: LobbyData) => {
  const offset = useMemo(() => Date.parse(lobby.now) - Date.now(), [lobby.now]);
  const [tick, setTick] = useState(0);

  useEffect(() => {
    if (!lobby.start_at) return undefined;
    const timer = window.setInterval(() => { setTick((value) => value + 1); }, 250);
    return () => { window.clearInterval(timer); };
  }, [lobby.start_at]);

  if (!lobby.start_at) return null;
  void tick;
  return Math.max(0, Math.ceil((Date.parse(lobby.start_at) - (Date.now() + offset)) / 1000));
};

const BUBBLE_MS = 6_000;

const PlayerCard: React.FC<{
  player: LobbyPlayer;
  mine: boolean;
  canToggle: boolean;
  busy: boolean;
  bubble?: string;
  onToggle: (player: LobbyPlayer) => void;
}> = ({ player, mine, canToggle, busy, bubble, onToggle }) => (
  <li className={['game-stage__player', player.ready && 'game-stage__player--ready', mine && 'game-stage__player--me'].filter(Boolean).join(' ')}>
    {bubble && <span className='game-stage__speech' key={bubble}>{bubble}</span>}
    <span className='game-stage__avatar'>
      <TokenAvatar accountId={player.account_id} avatar={player.avatar} size={88} />
      {player.ready && <span className='game-stage__check' aria-hidden>✓</span>}
      {player.waiting && <span className='game-stage__waiting'><FormattedMessage id='lobby.waiting' defaultMessage='Waiting...' /></span>}
    </span>
    <span className='game-stage__who'>
      <TokenName accountId={player.account_id} name={player.name} house={player.house} />
    </span>
    {canToggle && (
      <button type='button' className={player.ready ? 'game-stage__button game-stage__button--off' : 'game-stage__button'} disabled={busy} onClick={() => { onToggle(player); }}>
        {player.ready
          ? <FormattedMessage id='lobby.unready' defaultMessage='Cancel ready' />
          : <FormattedMessage id='lobby.ready' defaultMessage='Ready' />}
      </button>
    )}
  </li>
);

export const LobbyStage: React.FC<{
  sessionId: string;
  name: string;
  lobby: LobbyData;
  messages: LobbyMessage[];
  onChanged: () => void;
}> = ({ sessionId, name, lobby, messages: log, onChanged }) => {
  const intl = useIntl();
  const dispatch = useAppDispatch();
  const [text, setText] = useState('');
  const [busy, setBusy] = useState(false);
  const logRef = useRef<HTMLUListElement>(null);
  const lastId = useRef<string | null>(null);
  const remaining = useRemaining(lobby);
  const counting = remaining !== null;
  const recruiting = Boolean(lobby.recruiting);
  const readyCount = lobby.players.filter((player) => player.ready).length;
  const participant = lobby.me !== null;
  // 채팅 말풍선: 토큰 위에 몇 초 동안만 (서버 시계 기준)
  const offset = useMemo(() => Date.parse(lobby.now) - Date.now(), [lobby.now]);
  const [clock, setClock] = useState(0);
  useEffect(() => {
    const timer = window.setInterval(() => { setClock((value) => value + 1); }, 500);
    return () => { window.clearInterval(timer); };
  }, []);
  void clock;
  const bubbles = useMemo(() => {
    const found: Record<string, string> = {};
    const now = Date.now() + offset;
    log.forEach((message) => {
      if (message.chat && message.acct && now - Date.parse(message.created_at) < BUBBLE_MS) found[message.acct] = message.text;
    });
    return found;
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [log, offset, clock]);

  useStageLayout(true);

  // 새 채팅이 오면 맨 아래로
  useLayoutEffect(() => {
    const newest = log[log.length - 1]?.id ?? null;
    if (newest !== lastId.current && logRef.current) logRef.current.scrollTop = logRef.current.scrollHeight;
    lastId.current = newest;
  }, [log]);

  const post = useCallback(
    (action: string, params: Record<string, unknown> = {}) => {
      setBusy(true);
      apiRequestPost<{ notice?: string | null }>(`v1/system/sessions/${sessionId}/${action}`, params)
        .then((response) => {
          onChanged();
          // 참가는 됐지만 오늘 받을 수 있는 보상 횟수를 채워서 점수·보상이 없다는 안내
          if (response?.notice && ['join', 'accept'].includes(action)) {
            dispatch(openModal({ modalType: 'CONFIRM', modalProps: { title: intl.formatMessage(messages.noRewardTitle), message: response.notice, confirm: intl.formatMessage(messages.ok), hideCancel: true, onConfirm: () => undefined } }));
          }
          return true;
        })
        .catch((reason: unknown) => {
          onChanged();
          // 참가·수락이 막히면 (정원 초과·하루 제한 등) 서버가 보낸 이유를 모달로 알린다
          const message = apiErrorMessage(reason);
          if (message && ['join', 'accept', 'team'].includes(action)) {
            dispatch(openModal({ modalType: 'CONFIRM', modalProps: { title: intl.formatMessage(messages.joinFailed), message, confirm: intl.formatMessage(messages.ok), hideCancel: true, onConfirm: () => undefined } }));
          }
        })
        .finally(() => {
          setBusy(false);
        });
    },
    [sessionId, onChanged, dispatch, intl],
  );

  // 참가 불가 버튼을 누르면 이유를 모달로
  const blocked = useCallback((message: string) => {
    dispatch(openModal({ modalType: 'CONFIRM', modalProps: { title: intl.formatMessage(messages.joinFailed), message, confirm: intl.formatMessage(messages.ok), hideCancel: true, onConfirm: () => undefined } }));
  }, [dispatch, intl]);

  const toggle = useCallback(
    (player: LobbyPlayer) => {
      post('ready', { ready: !player.ready, ...(player.account_id === lobby.me ? {} : { acct: player.acct }) });
    },
    [post, lobby.me],
  );

  const submit = useCallback(
    (event: React.FormEvent) => {
      event.preventDefault();
      const value = text.trim();
      if (!value) return;
      setText('');
      post('chat', { text: value });
    },
    [post, text],
  );

  return createPortal(
    <div className='game-stage' role='dialog' aria-label={name}>
      <div className='game-stage__spot' aria-hidden />

      <header className='game-stage__head'>
        <small className='game-stage__eyebrow'>{recruiting ? <FormattedMessage id='lobby.recruit_title' defaultMessage='Gathering players' /> : <FormattedMessage id='lobby.title' defaultMessage='Waiting room' />}</small>
        <h1>{name}</h1>
        <p>
          {recruiting ? (
            <>
              <FormattedMessage id='lobby.recruiting' defaultMessage='Recruiting · {total} joined · {min}–{max} players' values={{ total: lobby.players.length, min: lobby.min, max: lobby.max }} />
              {lobby.recruit_ends_at && <> · <Countdown until={lobby.recruit_ends_at} /></>}
            </>
          ) : (
            <FormattedMessage id='lobby.status' defaultMessage='{ready} of {total} ready · {min}–{max} players' values={{ ready: readyCount, total: lobby.players.length, min: lobby.min, max: lobby.max }} />
          )}
        </p>
      </header>

      {lobby.teams ? (
        <div className='lobby-teams'>
          {(['student', 'prefect'] as const).map((team) => (
            <section key={team} className={`lobby-team lobby-team--${team}`}>
              <header className='lobby-team__head'>
                <strong>{lobby.teams?.names[team]} <FormattedMessage id='lobby.team_suffix' defaultMessage='Team' /></strong>
                <span>{lobby.teams?.counts[team]}/{lobby.teams?.caps[team]}</span>
                {lobby.teams?.mine === team && <em><FormattedMessage id='lobby.my_team' defaultMessage='My team' /></em>}
              </header>
              <ul className='game-stage__players'>
                {lobby.players.filter((player) => player.team === team && !player.waiting).map((player: LobbyPlayer) => (
                <PlayerCard
                  key={player.account_id}
                  player={player}
                  mine={player.account_id === lobby.me}
                  canToggle={!recruiting && !player.waiting && (player.account_id === lobby.me || lobby.can_manage)}
                  busy={busy || counting}
                  bubble={bubbles[player.acct]}
                  onToggle={toggle}
                />
              ))}
              </ul>
            </section>
          ))}
          {lobby.players.some((player) => !player.team || player.waiting) && (
            <ul className='game-stage__players'>
              {lobby.players.filter((player) => !player.team || player.waiting).map((player: LobbyPlayer) => (
                <PlayerCard
                  key={player.account_id}
                  player={player}
                  mine={player.account_id === lobby.me}
                  canToggle={!recruiting && !player.waiting && (player.account_id === lobby.me || lobby.can_manage)}
                  busy={busy || counting}
                  bubble={bubbles[player.acct]}
                  onToggle={toggle}
                />
              ))}
            </ul>
          )}
        </div>
      ) : (
        <ul className='game-stage__players'>
          {lobby.players.map((player) => (
            <PlayerCard
              key={player.account_id}
              player={player}
              mine={player.account_id === lobby.me}
              canToggle={!recruiting && !player.waiting && (player.account_id === lobby.me || lobby.can_manage)}
              busy={busy || counting}
              bubble={bubbles[player.acct]}
              onToggle={toggle}
            />
          ))}
        </ul>
      )}

      {(lobby.can_join || lobby.can_leave || lobby.can_respond || (lobby.teams?.can_change && !counting) || (lobby.can_invite && !counting) || ((lobby.recruiting || lobby.invite) && lobby.can_manage && !counting)) && (
        <div className='game-stage__membership'>
          {lobby.teams?.can_change && !counting && (
            <button type='button' className='game-stage__join game-stage__join--off lobby-team-change' disabled={busy || lobby.teams?.change_blocked} onClick={() => { post('team'); }}>
              {lobby.teams?.change_blocked
                ? <FormattedMessage id='lobby.team_full' defaultMessage='The other team is full' />
                : <FormattedMessage id='lobby.change_team' defaultMessage='Change team' />}
            </button>
          )}
          {lobby.can_respond && (
            <>
              <button type='button' className={lobby.join_block ? 'game-stage__join game-stage__join--off' : 'game-stage__join'} disabled={busy} onClick={() => { if (lobby.join_block) blocked(lobby.join_block); else post('accept'); }}>
                {lobby.join_block ? <FormattedMessage id='lobby.cannot_join' defaultMessage='Cannot join' /> : <FormattedMessage id='lobby.accept' defaultMessage='Accept' />}
              </button>
              <button type='button' className='game-stage__join game-stage__join--off' disabled={busy} onClick={() => { post('decline'); }}>
                <FormattedMessage id='lobby.decline' defaultMessage='Decline' />
              </button>
            </>
          )}
          {(lobby.recruiting || lobby.invite) && lobby.can_manage && !counting && (
            <button type='button' className='game-stage__join' disabled={busy} onClick={() => { post('start_now'); }}>
              <FormattedMessage id='lobby.start_now' defaultMessage='Start now' />
            </button>
          )}
          {lobby.can_invite && !counting && (
            <button
              type='button'
              className='game-stage__join'
              disabled={busy}
              onClick={() => { dispatch(openModal({ modalType: 'EVENT_INVITE', modalProps: { sessionId, exclude: lobby.players.map((player) => player.acct), onInvited: onChanged } })); }}
            >
              <FormattedMessage id='lobby.invite_more' defaultMessage='Add characters' />
            </button>
          )}
          {lobby.can_join && (
            <button type='button' className={lobby.join_block ? 'game-stage__join game-stage__join--off' : 'game-stage__join'} disabled={busy} onClick={() => { if (lobby.join_block) blocked(lobby.join_block); else post('join'); }}>
              {lobby.join_block ? <FormattedMessage id='lobby.cannot_join' defaultMessage='Cannot join' /> : <FormattedMessage id='lobby.join' defaultMessage='Join' />}
            </button>
          )}
          {lobby.can_leave && !counting && (
            <button type='button' className='game-stage__join game-stage__join--off' disabled={busy} onClick={() => { post('leave'); }}>
              <FormattedMessage id='lobby.leave' defaultMessage='Cancel joining' />
            </button>
          )}
        </div>
      )}

      <section className='game-stage__chat'>
        <ul className='game-stage__log' ref={logRef}>
          {log.map((message) => (
            message.chat ? (
              <li key={message.id} className={message.mine ? 'game-stage__line game-stage__line--mine' : 'game-stage__line'}>
                <img src={message.avatar} alt='' />
                <strong>{message.name}</strong>
                <span className='game-stage__line-text'>: {message.text}</span>
              </li>
            ) : (
              <li key={message.id} className='game-stage__note'>{message.text}</li>
            )
          ))}
        </ul>
        {(participant || lobby.can_manage) && (
          <form className='game-stage__input' onSubmit={submit}>
            <input
              type='text'
              value={text}
              maxLength={200}
              placeholder={intl.formatMessage(messages.placeholder)}
              onChange={(event) => { setText(event.target.value); }}
            />
            <button type='submit' disabled={busy || !text.trim()}>{intl.formatMessage(messages.send)}</button>
          </form>
        )}
      </section>

      {counting && (
        <div className='game-stage__overlay'>
          <small className='game-stage__overlay-label'>
            <FormattedMessage id='lobby.opening' defaultMessage='Opening the game' />
          </small>
          <p className='game-stage__overlay-text'>
            <FormattedMessage id='lobby.starting' defaultMessage='Everyone is ready. The game starts soon!' />
          </p>
          <strong className='game-stage__count'>{(remaining ?? 0) > 0 ? remaining : '…'}</strong>
          {(participant || lobby.can_manage) && (remaining ?? 0) > 0 && (
            <button type='button' className='game-stage__cancel' disabled={busy} onClick={() => { post('cancel_start'); }}>
              <FormattedMessage id='lobby.cancel' defaultMessage='Cancel' />
            </button>
          )}
        </div>
      )}
    </div>,
    document.body,
  );
};
