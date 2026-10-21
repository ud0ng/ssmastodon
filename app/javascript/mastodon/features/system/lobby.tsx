// 여럿이 하는 컨텐츠 대기방 (웹게임 느낌): 전체 화면 어두운 스포트라이트 배경에 참가자 아바타, 아래에 소속 엠블럼 | 이름, 준비하기 / 준비 취소.
//   마스토돈 메뉴는 왼쪽에 아이콘만 남는다 (body.layout-game-stage, styles/mastodon/_game_stage.scss).
//   화면 아래에는 채팅 입력창, 그 위로 채팅이 말풍선으로 (호버하면 스크롤바).
//   모두 준비하면 검은 오버레이와 카운트다운, 누구든 [취소]하면 다시 준비하기 화면.
//   운영진은 모든 캐릭터의 준비·준비 취소를 바꿀 수 있다.
import { useCallback, useEffect, useLayoutEffect, useMemo, useRef, useState } from 'react';

import { defineMessages, FormattedMessage, useIntl } from 'react-intl';

import { createPortal } from 'react-dom';

import { apiRequestPost } from 'mastodon/api';

import { TokenAvatar, TokenName } from './game_token';

export interface LobbyPlayer {
  account_id: string;
  acct: string;
  name: string;
  avatar: string;
  house: { name: string; color: string } | null;
  ready: boolean;
}

export interface LobbyData {
  min: number;
  max: number;
  countdown_seconds: number;
  start_at: string | null;
  now: string;
  can_manage: boolean;
  me: string | null;
  players: LobbyPlayer[];
}

export interface LobbyMessage {
  id: string;
  chat?: boolean;
  mine: boolean;
  name: string;
  avatar: string;
  text: string;
  created_at: string;
}

const messages = defineMessages({
  placeholder: { id: 'lobby.placeholder', defaultMessage: 'Say something to the room' },
  send: { id: 'lobby.send', defaultMessage: 'Send' },
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

const PlayerCard: React.FC<{
  player: LobbyPlayer;
  mine: boolean;
  canToggle: boolean;
  busy: boolean;
  onToggle: (player: LobbyPlayer) => void;
}> = ({ player, mine, canToggle, busy, onToggle }) => (
  <li className={['game-stage__player', player.ready && 'game-stage__player--ready', mine && 'game-stage__player--me'].filter(Boolean).join(' ')}>
    <span className='game-stage__avatar'>
      <TokenAvatar accountId={player.account_id} avatar={player.avatar} size={88} />
      {player.ready && <span className='game-stage__check' aria-hidden>✓</span>}
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
  const [text, setText] = useState('');
  const [busy, setBusy] = useState(false);
  const logRef = useRef<HTMLUListElement>(null);
  const lastId = useRef<string | null>(null);
  const remaining = useRemaining(lobby);
  const counting = remaining !== null;
  const readyCount = lobby.players.filter((player) => player.ready).length;
  const participant = lobby.me !== null;

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
      apiRequestPost(`v1/system/sessions/${sessionId}/${action}`, params)
        .then(() => {
          onChanged();
          return true;
        })
        .catch(() => {
          onChanged();
        })
        .finally(() => {
          setBusy(false);
        });
    },
    [sessionId, onChanged],
  );

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
        <small className='game-stage__eyebrow'><FormattedMessage id='lobby.title' defaultMessage='Waiting room' /></small>
        <h1>{name}</h1>
        <p>
          <FormattedMessage id='lobby.status' defaultMessage='{ready} of {total} ready · {min}–{max} players' values={{ ready: readyCount, total: lobby.players.length, min: lobby.min, max: lobby.max }} />
        </p>
      </header>

      <ul className='game-stage__players'>
        {lobby.players.map((player) => (
          <PlayerCard
            key={player.account_id}
            player={player}
            mine={player.account_id === lobby.me}
            canToggle={player.account_id === lobby.me || lobby.can_manage}
            busy={busy || counting}
            onToggle={toggle}
          />
        ))}
      </ul>

      <section className='game-stage__chat'>
        <ul className='game-stage__log' ref={logRef}>
          {log.map((message) => (
            message.chat ? (
              <li key={message.id} className={message.mine ? 'game-stage__bubble game-stage__bubble--mine' : 'game-stage__bubble'}>
                {!message.mine && <img src={message.avatar} alt='' />}
                <span className='game-stage__bubble-body'>
                  {!message.mine && <strong>{message.name}</strong>}
                  <span className='game-stage__bubble-text'>{message.text}</span>
                </span>
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
          <strong className='game-stage__count'>{remaining}</strong>
          {(participant || lobby.can_manage) && (
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
