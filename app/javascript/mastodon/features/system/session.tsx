// 컨텐츠 방 (/system/sessions/:id): DM 채팅방처럼 메시지로.
//   시스템 계정 메시지는 가운데 사회자 창(진행 문구 + 그때의 컨텐츠 카드), 참가자 메시지는 말풍선(내 것은 오른쪽).
//   참가자는 맨 아래 칸에서 명령어를 보낸다 (마지막 카드의 버튼으로도). 참가하지 않은 사람은 관전 (스레드만 보인다).
//   미로·도둑 지도는 위에 전용 진행판.
import { useCallback, useEffect, useLayoutEffect, useRef, useState } from 'react';

import { defineMessages, FormattedMessage, FormattedTime, useIntl } from 'react-intl';

import { Link, useParams } from 'react-router-dom';

import LockIcon from '@/material-icons/400-24px/lock.svg?react';
import StarIcon from '@/styles/bird-theme-svg/star.svg?react';
import { apiRequestGet } from 'mastodon/api';
import { Column } from 'mastodon/components/column';
import { ColumnHeader } from 'mastodon/components/column_header';
import type { CardAction, GameCard } from 'mastodon/components/content_card';
import { ContentCardView } from 'mastodon/components/content_card';
import { Icon } from 'mastodon/components/icon';
import { LoadingIndicator } from 'mastodon/components/loading_indicator';

import { sendCommand } from './board';
import { MaraudersMapPlay } from './marauders_map';
import { MazePlay } from './maze';

const messages = defineMessages({
  title: { id: 'system.session.title', defaultMessage: 'Game' },
  placeholder: { id: 'system.room.placeholder', defaultMessage: 'Command, e.g. eat or brew/dragon blood' },
});

const REFRESH_MS = 5_000;
// 툿을 올리고 시스템이 처리할 때까지 잠깐 기다렸다 다시 읽는다
const AFTER_SEND_MS = [1_200, 3_500];

interface RoomMessage {
  id: string;
  system: boolean;
  mine: boolean;
  secret: boolean;
  name: string;
  acct: string;
  avatar: string;
  text: string;
  created_at: string;
  card: GameCard | null;
}

interface RoomData {
  id: string;
  kind: string;
  name: string;
  status: GameCard['phase'];
  system_acct: string;
  player: boolean;
  messages: RoomMessage[];
}

const Secret: React.FC = () => (
  <span className='game-room__secret'>
    <Icon id='lock' icon={LockIcon} />
    <FormattedMessage id='system.room.secret' defaultMessage='Secret' />
  </span>
);

// 시스템(사회자) 메시지: 가운데 창
const HostMessage: React.FC<{ message: RoomMessage; onAction?: (action: CardAction) => void }> = ({ message, onAction }) => (
  <li className='game-room__host'>
    <div className='game-room__host-box'>
      <div className='game-room__host-head'>
        <img src={message.avatar} alt='' />
        <span>{message.name}</span>
        {message.secret && <Secret />}
        <FormattedTime value={message.created_at} hour='2-digit' minute='2-digit' />
      </div>
      {message.text && <p className='game-room__host-text'>{message.text}</p>}
      {message.card && <ContentCardView card={message.card} onAction={onAction} />}
    </div>
  </li>
);

// 참가자 메시지: 말풍선 (내 것은 오른쪽)
const PlayerMessage: React.FC<{ message: RoomMessage }> = ({ message }) => (
  <li className={message.mine ? 'game-room__msg game-room__msg--mine' : 'game-room__msg'}>
    {!message.mine && <img className='game-room__avatar' src={message.avatar} alt='' />}
    <div className='game-room__msg-body'>
      {!message.mine && <span className='game-room__msg-name'>{message.name}</span>}
      <div className='game-room__bubble'>
        {message.secret && <Secret />}
        {message.text}
      </div>
      <span className='game-room__msg-time'>
        <FormattedTime value={message.created_at} hour='2-digit' minute='2-digit' />
      </span>
    </div>
  </li>
);

const SystemSession: React.FC<{ multiColumn?: boolean }> = ({ multiColumn }) => {
  const intl = useIntl();
  const { id } = useParams<{ id: string }>();
  const [data, setData] = useState<RoomData | null>(null);
  const [failed, setFailed] = useState(false);
  const [busy, setBusy] = useState(false);
  const [command, setCommand] = useState('');
  const [dm, setDm] = useState(false);
  const timers = useRef<number[]>([]);
  const logRef = useRef<HTMLOListElement>(null);
  const lastId = useRef<string | null>(null);

  const load = useCallback(() => {
    apiRequestGet<RoomData>(`v1/system/sessions/${id}`)
      .then((room) => {
        setData(room);
        setFailed(false);
        return room;
      })
      .catch(() => {
        setFailed(true);
      });
  }, [id]);

  useEffect(() => {
    load();
    const timer = window.setInterval(load, REFRESH_MS);
    const pending = timers.current;
    return () => {
      window.clearInterval(timer);
      pending.forEach((each) => { window.clearTimeout(each); });
    };
  }, [load]);

  // 새 메시지가 오면 맨 아래로
  useLayoutEffect(() => {
    const newest = data?.messages[data.messages.length - 1]?.id ?? null;
    if (newest && newest !== lastId.current && logRef.current) {
      logRef.current.lastElementChild?.scrollIntoView({ block: 'end' });
    }
    lastId.current = newest;
  }, [data]);

  const send = useCallback(
    (params: Record<string, unknown>) => {
      setBusy(true);
      sendCommand({ session_id: id, ...params })
        .then((response) => {
          AFTER_SEND_MS.forEach((delay) => {
            timers.current.push(window.setTimeout(load, delay));
          });
          return response;
        })
        .finally(() => {
          setBusy(false);
        });
    },
    [id, load],
  );

  const handleAction = useCallback(
    (action: CardAction) => {
      send({ command: action.command, dm: action.dm, target: action.mention });
    },
    [send],
  );

  const handleSubmit = useCallback(
    (event: React.FormEvent) => {
      event.preventDefault();
      const [name, ...rest] = command.replace(/[[\]]/g, '').split('/');
      if (!name?.trim()) return;
      send({ command: name.trim(), args: rest.join('/').trim() || undefined, dm });
      setCommand('');
    },
    [command, dm, send],
  );

  const title = data?.name ?? intl.formatMessage(messages.title);
  const open = data ? data.status === 'pending' || data.status === 'active' : false;
  // 버튼은 마지막 카드에만 (지금 상태)
  const lastCardId = data ? [...data.messages].reverse().find((message) => message.card)?.id : undefined;

  return (
    <Column bindToDocument={!multiColumn} label={title}>
      <ColumnHeader icon='system' iconComponent={StarIcon} title={title} multiColumn={multiColumn} showBackButton />

      <div className='system-page game-room scrollable'>
        {!data && !failed && <LoadingIndicator />}
        {failed && !data && (
          <p className='system-page__empty'>
            <FormattedMessage id='system.load_failed' defaultMessage='Could not load. Try again in a moment.' />
          </p>
        )}

        {data && (
          <>
            <div className='game-room__bar'>
              <Link to={`/system/games/${data.kind}`}>
                <FormattedMessage id='system.session.game_page' defaultMessage='{name} page' values={{ name: data.name }} />
              </Link>
              {!data.player && (
                <span className='system-rooms__tag'>
                  <FormattedMessage id='system.game.spectating' defaultMessage='Watching' />
                </span>
              )}
            </div>

            {data.player && data.kind === 'maze' && data.status === 'active' && <MazePlay sessionId={data.id} onMoved={load} />}
            {data.player && data.kind === 'marauders_map' && data.status === 'active' && <MaraudersMapPlay sessionId={data.id} onMoved={load} />}

            <ol className='game-room__log' ref={logRef}>
              {data.messages.map((message) =>
                message.system ? (
                  <HostMessage key={message.id} message={message} onAction={data.player && open && message.id === lastCardId && !busy ? handleAction : undefined} />
                ) : (
                  <PlayerMessage key={message.id} message={message} />
                ),
              )}
            </ol>
          </>
        )}
      </div>

      {data?.player && open && (
        <form className='game-room__composer' onSubmit={handleSubmit}>
          <label className='game-room__dm' title={intl.formatMessage({ id: 'system.board.secret', defaultMessage: 'Secret (DM)' })}>
            <input type='checkbox' checked={dm} onChange={(event) => { setDm(event.target.checked); }} />
            <Icon id='lock' icon={LockIcon} />
          </label>
          <input
            type='text'
            value={command}
            onChange={(event) => { setCommand(event.target.value); }}
            placeholder={intl.formatMessage(messages.placeholder)}
            aria-label={intl.formatMessage(messages.placeholder)}
          />
          <button type='submit' className='system-start' disabled={busy || !command.trim()}>
            <FormattedMessage id='system.board.send' defaultMessage='Send' />
          </button>
        </form>
      )}
    </Column>
  );
};

// eslint-disable-next-line import/no-default-export
export default SystemSession;
