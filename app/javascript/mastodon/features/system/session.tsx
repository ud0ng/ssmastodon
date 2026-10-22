// 컨텐츠 방 (/system/sessions/:id): DM 채팅방과 같은 짜임.
//   맨 위에 지금 상태(아바타 | 소속 | 이름 vs …, 가운데 진행 상황)를 고정, 맨 아래에 입력창을 고정하고 가운데 메시지만 스크롤.
//   시스템 계정 메시지는 가운데 사회자 창(진행 문구), 참가자 메시지는 말풍선(내 것은 오른쪽).
//   내 차례면 입력창이 강조되고 그 위에 할 일 버튼이 뜬다. 참가하지 않은 사람은 관전 (입력창 없음).
//   미로·도둑 지도는 맨 위에 전용 진행판.
import { Fragment, useCallback, useEffect, useLayoutEffect, useRef, useState } from 'react';

import { defineMessages, FormattedMessage, useIntl } from 'react-intl';

import { useHistory, useParams } from 'react-router-dom';

import LockIcon from '@/material-icons/400-24px/lock.svg?react';
import StarIcon from '@/styles/bird-theme-svg/star.svg?react';
import { openModal } from 'mastodon/actions/modal';
import { apiRequestGet } from 'mastodon/api';
import { Column } from 'mastodon/components/column';
import { ColumnHeader } from 'mastodon/components/column_header';
import type { TextPerson } from 'mastodon/components/command_text';
import { CommandText, isCommandOnly } from 'mastodon/components/command_text';
import type { CardAction, GameCard } from 'mastodon/components/content_card';
import { ContentCardView, myActions } from 'mastodon/components/content_card';
import { Countdown } from 'mastodon/components/countdown';
import { Icon } from 'mastodon/components/icon';
import { LoadingIndicator } from 'mastodon/components/loading_indicator';
import { RelativeTimestamp } from 'mastodon/components/relative_timestamp';
import { Composer } from 'mastodon/features/messages/components/composer';
import { DateDivider } from 'mastodon/features/messages/components/date_divider';

import { useAppDispatch } from 'mastodon/store';

import { sendCommand } from './board';
import type { FlyChatMessage } from './flying';
import { FlyingStage } from './flying';
import type { LobbyData, LobbyMessage } from './lobby';
import { LobbyStage } from './lobby';
import { StageFrame } from './stage_page';
import { StageTutorial } from './stage_tutorial';
import { MaraudersMapPlay } from './marauders_map';
import { MazePlay } from './maze';
import { ChamberPlay } from './secret_chamber';

// 무대 화면으로만 보이는 이벤트 (옛 채팅방 화면 없음)
const EVENT_KINDS = ['flying', 'maze', 'marauders_map', 'secret_chamber'];

const messages = defineMessages({
  title: { id: 'system.session.title', defaultMessage: 'Game' },
  cancelledTitle: { id: 'system.session.cancelled_title', defaultMessage: 'The event was cancelled' },
  ok: { id: 'system.session.ok', defaultMessage: 'OK' },
  placeholder: { id: 'system.room.placeholder', defaultMessage: 'Message or [command], e.g. [eat]' },
  withCommand: { id: 'system.room.with_command', defaultMessage: 'Add a line (optional)' },
  removeCommand: { id: 'system.room.remove_command', defaultMessage: 'Remove command' },
});

const REFRESH_MS = 5_000;
// 대기방은 준비·채팅·카운트다운이 빨리 보이게 자주 읽는다
const LOBBY_REFRESH_MS = 1_500;
// 툿을 올리고 시스템이 처리할 때까지 잠깐 기다렸다 다시 읽는다
const AFTER_SEND_MS = [1_200, 3_500];

interface RoomMessage {
  id: string;
  system: boolean;
  mine: boolean;
  secret: boolean;
  chat?: boolean;
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
  // 인원 부족으로 이벤트가 취소됐을 때 모달에 보여 줄 문구
  cancel_reason?: string | null;
  system_acct: string;
  player: boolean;
  staff?: boolean;
  // 모집이 끝난 뒤 대기방 (status 'lobby')
  lobby: LobbyData | null;
  messages: RoomMessage[];
}

const Secret: React.FC = () => (
  <span className='game-room__secret'>
    <Icon id='lock' icon={LockIcon} />
    <FormattedMessage id='system.room.secret' defaultMessage='Secret' />
  </span>
);

// 시스템(사회자) 메시지: 전체 너비 박스, 진행 문구만 (이름·시간 없음. 지금 상태 카드는 맨 위에 고정)
const HostMessage: React.FC<{ message: RoomMessage; people: TextPerson[] }> = ({ message, people }) => (
  <div className={message.secret ? 'game-room__host game-room__host--secret' : 'game-room__host'}>
    {message.secret && <Secret />}
    {message.text && <p className='game-room__host-text'><CommandText text={message.text} people={people} noEmoji /></p>}
  </div>
);

// 참가자 메시지: DM 채팅 말풍선 그대로 (dm-message, 내 것은 오른쪽). 같은 사람이 이어 보내면 한 묶음.
// [명령어]만 보낸 말은 말풍선 없이 배지만. 시간은 'n분 전'
const PlayerMessage: React.FC<{ message: RoomMessage; first: boolean; last: boolean }> = ({ message, first, last }) => {
  const commandOnly = isCommandOnly(message.text);
  return (
    <div
      className={[
        'dm-message',
        message.mine ? 'dm-message--mine' : 'dm-message--theirs',
        first && 'dm-message--first',
        last && 'dm-message--last',
        first && 'dm-message--sender-changed',
      ].filter(Boolean).join(' ')}
    >
      {!message.mine && (
        <div className='dm-message__avatar' aria-hidden='true'>
          {first && <img className='game-room__avatar' src={message.avatar} alt='' />}
        </div>
      )}

      <div className='dm-message__body'>
        {first && !message.mine && <span className='dm-message__sender'>{message.name}</span>}
        {commandOnly ? (
          <div className='game-room__command'>
            {message.secret && <Secret />}
            <CommandText text={message.text} />
          </div>
        ) : (
          <div className='dm-message__bubble'>
            <div className='dm-message__bubble__text'>
              <p>
                {message.secret && <Secret />}
                <CommandText text={message.text} />
              </p>
            </div>
          </div>
        )}
      </div>

      <div className='dm-message__aside'>
        {last && (
          <div className='dm-message__meta'>
            <time className='dm-message__time' dateTime={message.created_at}>
              <RelativeTimestamp timestamp={message.created_at} />
            </time>
          </div>
        )}
      </div>
    </div>
  );
};

const dayOf = (value: string) => new Date(value).toDateString();

// 메시지 목록: 날짜가 바뀌면 DM 처럼 날짜 줄, 참가자 메시지는 같은 사람이 이어지면 묶는다
const RoomLog: React.FC<{ messages: RoomMessage[] }> = ({ messages: list }) => {
  const shown = list.filter((message) => !message.system || message.text);
  // 시스템 문구 안 캐릭터 이름 → 아바타 | 굵은 이름 (참가자는 마지막 카드에서)
  const players = [...list].reverse().find((message) => message.card)?.card?.players ?? [];
  const people: TextPerson[] = players.map((player) => ({ name: player.name, avatar: player.avatar, color: player.house?.color }));
  return (
    <>
      {shown.map((message, index) => {
        const prev = shown[index - 1];
        const next = shown[index + 1];
        const newDay = !prev || dayOf(prev.created_at) !== dayOf(message.created_at);
        const sameAsPrev = !newDay && prev && !prev.system && prev.acct === message.acct;
        const sameAsNext = next && !next.system && next.acct === message.acct && dayOf(next.created_at) === dayOf(message.created_at);
        return (
          <Fragment key={message.id}>
            {newDay && <DateDivider date={new Date(message.created_at)} />}
            {message.system ? (
              <HostMessage message={message} people={people} />
            ) : (
              <div className='dm-room__group'>
                <PlayerMessage message={message} first={!sameAsPrev} last={!sameAsNext} />
              </div>
            )}
          </Fragment>
        );
      })}
    </>
  );
};

// 방에 있는 동안 화면 높이를 고정한다 (DM 채팅처럼 위 상태·아래 입력창은 그대로, 가운데 메시지만 스크롤)
const ROOM_BODY_CLASS = 'layout-game-room';

// 웹 전용 컨텐츠(미로·도둑 지도)는 메뉴·작성 패널을 잠시 숨기고 지도 | 메시지 두 칸으로 쓴다
const SPLIT_BODY_CLASS = 'layout-game-split';

const useRoomLayout = (split: boolean) => {
  useEffect(() => {
    document.body.classList.add(ROOM_BODY_CLASS);
    return () => {
      document.body.classList.remove(ROOM_BODY_CLASS);
    };
  }, []);

  useEffect(() => {
    if (!split) return undefined;
    document.body.classList.add(SPLIT_BODY_CLASS);
    return () => {
      document.body.classList.remove(SPLIT_BODY_CLASS);
    };
  }, [split]);
};

// 맨 아래 입력창 위: 내 차례면 할 일(버튼·안내), 아니면 누구를 기다리는지
// 버튼 줄: action.row 별로 나눈다 (결투 필살기·아이템은 일반 기술 다음 줄, 신청 취소·항복은 맨 아래 줄)
const ActionRows: React.FC<{
  actions: CardAction[];
  busy: boolean;
  picked: CardAction | null;
  onAction: (action: CardAction) => void;
}> = ({ actions, busy, picked, onAction }) => (
  <>
    {[...new Set(actions.map((action) => action.row ?? 1))].sort((x, y) => x - y).map((row) => (
      <div key={row} className='game-room__turn-actions'>
        {actions.filter((action) => (action.row ?? 1) === row).map((action) => (
          <button
            key={`${action.command}${action.mention ?? ''}`}
            type='button'
            className={[
              'game-room__action',
              action.style === 'secondary' && 'game-room__action--secondary',
              action.style === 'danger' && 'game-room__action--danger',
              picked?.command === action.command && picked.mention === action.mention && 'game-room__action--picked',
            ].filter(Boolean).join(' ')}
            disabled={busy}
            onClick={() => { onAction(action); }}
            title={action.hint ?? (action.dm ? `DM: [${action.command}]` : `[${action.command}]`)}
          >
            {action.label}
            {action.dm && <span className='game-room__action-dm'>DM</span>}
          </button>
        ))}
      </div>
    ))}
  </>
);

// 맨 아래 입력창 위: 내 차례면 할 일(버튼), 아니면 누구를 기다리는지. 신청 취소·항복(meta)은 차례와 상관없이 맨 아래 줄에 둔다.
const TurnPanel: React.FC<{
  card: GameCard | null;
  actions: CardAction[];
  busy: boolean;
  picked: CardAction | null;
  onAction: (action: CardAction) => void;
}> = ({ card, actions, busy, picked, onAction }) => {
  if (!card || !card.live) return null;

  const turnActions = actions.filter((action) => !action.meta);
  const metaActions = actions.filter((action) => action.meta);

  if (turnActions.length > 0) {
    return (
      <div className='game-room__turn'>
        <div className='game-room__turn-head'>
          <strong>
            <FormattedMessage id='system.room.turn' defaultMessage='Your move' />
          </strong>
          {card.deadline_at && <Countdown until={card.deadline_at} className='game-room__turn-time' />}
        </div>
        {card.kind === 'potion' && card.phase === 'active' && (
          <p className='game-room__turn-hint'>
            <FormattedMessage id='content_card.potion_hint2' defaultMessage='Press the button, then type the ingredient numbers in order, e.g. 1 5 3' />
          </p>
        )}
        <ActionRows actions={actions} busy={busy} picked={picked} onAction={onAction} />
      </div>
    );
  }

  if (card.phase !== 'active' && card.phase !== 'pending') return null;

  const current = card.players.find((player) => player.seat === card.data.current_seat);
  return (
    <div className='game-room__turn game-room__turn--waiting'>
      <p>
        {card.phase === 'pending' ? (
          <FormattedMessage id='system.room.waiting_accept' defaultMessage='Waiting for them to accept…' />
        ) : current ? (
          <FormattedMessage id='system.room.waiting' defaultMessage='Waiting for {name}…' values={{ name: current.name }} />
        ) : (
          <FormattedMessage id='system.room.waiting_others' defaultMessage='Waiting for the others…' />
        )}
      </p>
      {metaActions.length > 0 && <ActionRows actions={metaActions} busy={busy} picked={picked} onAction={onAction} />}
    </div>
  );
};

const SystemSession: React.FC<{ multiColumn?: boolean }> = ({ multiColumn }) => {
  const intl = useIntl();
  const dispatch = useAppDispatch();
  const history = useHistory();
  const lastStatus = useRef<string | null>(null);
  const { id } = useParams<{ id: string }>();
  const [data, setData] = useState<RoomData | null>(null);
  const [failed, setFailed] = useState(false);
  const [busy, setBusy] = useState(false);
  const [command, setCommand] = useState('');
  const [dm, setDm] = useState(false);
  const [picked, setPicked] = useState<CardAction | null>(null);
  const timers = useRef<number[]>([]);
  const scrollRef = useRef<HTMLDivElement>(null);
  const dockRef = useRef<HTMLDivElement>(null);
  const lastId = useRef<string | null>(null);
  const wasMyTurn = useRef(false);

  // 대기방은 전체 화면이라 판 화면용 두 칸 배치는 쓰지 않는다
  useRoomLayout(['maze', 'marauders_map', 'secret_chamber'].includes(data?.kind ?? '') && data?.status !== 'lobby');

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

  // 방에 있는 동안 모집이 인원 부족으로 취소되면 모달로 알리고, 확인하면 이벤트 메인 화면으로
  useEffect(() => {
    if (!data) return;
    if (lastStatus.current && lastStatus.current !== 'cancelled' && data.status === 'cancelled' && data.cancel_reason) {
      dispatch(openModal({
        modalType: 'CONFIRM',
        modalProps: {
          title: intl.formatMessage(messages.cancelledTitle),
          message: data.cancel_reason,
          confirm: intl.formatMessage(messages.ok),
          hideCancel: true,
          onConfirm: () => { history.push('/system/group'); },
        },
      }));
    }
    lastStatus.current = data.status;
  }, [data, dispatch, history, intl]);

  const inLobby = data?.status === 'lobby' || Boolean(data?.lobby?.recruiting);
  // 비행 대결 게임방은 라운드·채팅이 빨리 보이게 대기방처럼 자주 읽는다
  const flyingRoom = data?.kind === 'flying' && ['active', 'finished'].includes(data.status);

  useEffect(() => {
    load();
    const timer = window.setInterval(load, inLobby || flyingRoom ? LOBBY_REFRESH_MS : REFRESH_MS);
    const pending = timers.current;
    return () => {
      window.clearInterval(timer);
      pending.forEach((each) => { window.clearTimeout(each); });
    };
  }, [load, inLobby, flyingRoom]);

  // 새 메시지가 오면 메시지 칸만 맨 아래로
  useLayoutEffect(() => {
    const newest = data?.messages[data.messages.length - 1]?.id ?? null;
    if (newest && newest !== lastId.current && scrollRef.current) {
      scrollRef.current.scrollTop = scrollRef.current.scrollHeight;
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

  // 버튼: 바로 보내지 않고 입력창 앞에 [명령어] 배지로 붙인다 → 대사·말을 덧붙여 보낸다
  const handleAction = useCallback((action: CardAction) => {
    setPicked(action);
    dockRef.current?.querySelector<HTMLTextAreaElement>('textarea')?.focus();
  }, []);

  const clearPicked = useCallback(() => {
    setPicked(null);
  }, []);

  // 보내기: 고른 버튼이 있으면 '[명령어] 덧붙인 말'.
  // 아니면 [명령어]가 들어 있으면 그대로, 지금 판의 명령어 이름(예: 먹기, 먹기/2)이면 명령어로,
  // 그 밖의 말은 그냥 메시지 (시스템은 답하지 않고, 다음 명령어가 오면 다시 진행한다)
  const handleSubmit = useCallback(() => {
    const raw = command.trim();

    if (picked) {
      send({ text: `[${picked.command}] ${raw}`.trim(), dm: picked.dm || dm, target: picked.mention });
      setPicked(null);
      setCommand('');
      return;
    }

    if (!raw) return;

    const last = data ? [...data.messages].reverse().find((message) => message.card)?.card : null;
    const known = new Set((last?.actions ?? []).map((action) => action.command.split('/')[0]));
    const [name = '', ...rest] = raw.split('/');

    if (/\[[^\]\n]+\]/.test(raw) || !known.has(name.trim())) {
      send({ text: raw, dm });
    } else {
      send({ command: name.trim(), args: rest.join('/').trim() || undefined, dm });
    }
    setCommand('');
  }, [command, data, dm, picked, send]);

  // 판(지도·미로·원탁)을 보여 줄 때: 진행 중이거나 끝난 미로·도둑 지도(누구나), 비밀의 방(참가자)
  const boardShown = Boolean(data) && (
    (['maze', 'marauders_map'].includes(data?.kind ?? '') && ['active', 'finished'].includes(data?.status ?? ''))
    || (data?.kind === 'secret_chamber' && data.player && data.status !== 'cancelled')
  );
  const title = data?.name ?? intl.formatMessage(messages.title);
  const open = data ? ['pending', 'lobby', 'active'].includes(data.status) : false;
  // 맨 위에 고정하는 지금 상태: 마지막 카드
  const current = data ? [...data.messages].reverse().find((message) => message.card)?.card ?? null : null;
  const actions = data?.player && open && current ? myActions(current) : [];
  // 내 차례 강조·알림은 신청 취소·항복(meta)이 아닌 버튼이 있을 때만
  const myTurn = actions.some((action) => !action.meta);
  // 항복은 맨 위 헤더 오른쪽 끝에 둔다 (입력창 위 버튼 줄에는 넣지 않는다)
  const forfeitAction = actions.find((action) => action.style === 'danger');
  const panelActions = actions.filter((action) => action.style !== 'danger');

  // 고른 버튼이 더는 없으면 (차례가 넘어감 등) 배지도 뺀다
  useEffect(() => {
    if (picked && !actions.some((action) => action.command === picked.command && action.mention === picked.mention)) {
      setPicked(null);
    }
  }, [actions, picked]);

  // 내 차례가 되면 입력창으로 포커스 (효과는 .game-room__dock--turn)
  useEffect(() => {
    if (myTurn && !wasMyTurn.current) {
      dockRef.current?.querySelector<HTMLTextAreaElement>('textarea')?.focus({ preventScroll: true });
    }
    wasMyTurn.current = myTurn;
  }, [myTurn]);

  // 이벤트(여럿이 하는 컨텐츠) 방은 옛 채팅방 화면 없이 무대 화면(대기방·게임방)만 보인다. 읽는 동안·취소된 방도 어두운 무대 화면으로.
  // 비행 대결 말고는 게임방을 새로 만드는 중이라, 카운트다운이 끝나면 '준비중' 화면을 보여 준다
  if (!data || EVENT_KINDS.includes(data.kind)) {
    return (
      <>
        {data?.status === 'active' && data.player && data.kind === 'flying' && <StageTutorial kind={data.kind} />}
        {data && flyingRoom && (
          <FlyingStage
            sessionId={data.id}
            name={data.name}
            chat={data.messages.filter((message) => message.chat).map((message): FlyChatMessage => ({ id: message.id, mine: message.mine, name: message.name, acct: message.acct, avatar: message.avatar, text: message.text }))}
            staff={Boolean(data.staff)}
            isPlayer={data.player}
            onChanged={load}
          />
        )}
        {data?.lobby && (
          <LobbyStage
            sessionId={data.id}
            name={data.name}
            lobby={data.lobby}
            messages={data.messages.filter((message) => message.id.startsWith('m') && !message.secret && message.text) as LobbyMessage[]}
            onChanged={load}
          />
        )}
        {(!data || (!flyingRoom && !data.lobby)) && (
          <StageFrame back='/system/group' label={title}>
            {(data || failed) && (
              <p className='stage-notice'>
                {failed && !data
                  ? <FormattedMessage id='system.load_failed' defaultMessage='Could not load. Try again in a moment.' />
                  : data && data.kind !== 'flying' && ['active', 'finished'].includes(data.status)
                    ? <FormattedMessage id='stage.preparing' defaultMessage='The game room is being prepared.' />
                    : <FormattedMessage id='stage.closed' defaultMessage='This event has ended or was cancelled.' />}
              </p>
            )}
          </StageFrame>
        )}
      </>
    );
  }

  return (
    <Column bindToDocument={!multiColumn} label={title}>
      {data?.status === 'active' && data.player && ['maze', 'marauders_map', 'secret_chamber', 'flying'].includes(data.kind) && <StageTutorial kind={data.kind} />}
      {data && flyingRoom && (
        <FlyingStage
          sessionId={data.id}
          name={data.name}
          chat={data.messages.filter((message) => message.chat).map((message): FlyChatMessage => ({ id: message.id, mine: message.mine, name: message.name, acct: message.acct, avatar: message.avatar, text: message.text }))}
          staff={Boolean(data.staff)}
          isPlayer={data.player}
          onChanged={load}
        />
      )}
      {data?.lobby && (
        <LobbyStage
          sessionId={data.id}
          name={data.name}
          lobby={data.lobby}
          messages={data.messages.filter((message) => message.id.startsWith('m') && !message.secret && message.text) as LobbyMessage[]}
          onChanged={load}
        />
      )}
      <ColumnHeader
        icon='system'
        iconComponent={StarIcon}
        title={title}
        multiColumn={multiColumn}
        showBackButton
        extraButton={forfeitAction && (
          <button
            type='button'
            className={picked?.command === forfeitAction.command ? 'game-room__forfeit game-room__forfeit--picked' : 'game-room__forfeit'}
            disabled={busy}
            onClick={() => { handleAction(forfeitAction); }}
            title={`[${forfeitAction.command}]`}
          >
            {forfeitAction.label}
          </button>
        )}
      />

      {/* 지금 상태 (맨 위 고정): 아바타 | 소속 | 이름 vs …, 가운데 진행 상황. 웹 전용 컨텐츠는 판(지도·원탁)이 대신한다 (참가자가 아니어도 미로·도둑 지도는 실시간으로 볼 수 있다) */}
      {data && (current || boardShown) && (
        <div className={['maze', 'secret_chamber'].includes(data.kind) ? 'system-page game-room__status game-room__status--maze' : 'system-page game-room__status'}>
          {current && !boardShown && <ContentCardView card={current} variant='room' />}
          {boardShown && data.kind === 'secret_chamber' && <ChamberPlay sessionId={data.id} onMoved={load} />}
          {boardShown && data.kind === 'maze' && <MazePlay sessionId={data.id} onMoved={load} />}
          {boardShown && data.kind === 'marauders_map' && <MaraudersMapPlay sessionId={data.id} onMoved={load} />}
        </div>
      )}

      {/* 메시지 (여기만 스크롤) */}
      <div className='dm-room__scroll game-room' ref={scrollRef}>
        {!data && !failed && <LoadingIndicator />}
        {failed && !data && (
          <p className='dm-room__empty'>
            <FormattedMessage id='system.load_failed' defaultMessage='Could not load. Try again in a moment.' />
          </p>
        )}

        {data && <RoomLog messages={data.messages} />}
      </div>

      {/* 입력창 (맨 아래 고정): 내 차례면 강조 + 할 일 버튼, DM 채팅과 같은 입력칸·보내기 버튼 */}
      {data?.player && open && (
        <div ref={dockRef} className={myTurn ? 'game-room__dock game-room__dock--turn' : 'game-room__dock'}>
          <TurnPanel card={current} actions={panelActions} busy={busy} picked={picked} onAction={handleAction} />
          <div className='game-room__dock-row'>
            <label className='game-room__dm' title={intl.formatMessage({ id: 'system.board.secret', defaultMessage: 'Secret (DM)' })}>
              <input type='checkbox' checked={dm} onChange={(event) => { setDm(event.target.checked); }} />
              <Icon id='lock' icon={LockIcon} />
            </label>
            <Composer
              value={command}
              onChange={setCommand}
              onSubmit={handleSubmit}
              isSending={busy}
              placeholder={intl.formatMessage(picked ? messages.withCommand : messages.placeholder)}
              hasPrefixContent={Boolean(picked)}
              prefix={picked && (
                <span className='game-room__picked'>
                  <kbd className='command-badge'>{picked.label}</kbd>
                  {(picked.dm || dm) && <span className='game-room__action-dm'>DM</span>}
                  <button type='button' className='game-room__picked-remove' onClick={clearPicked} aria-label={intl.formatMessage(messages.removeCommand)}>×</button>
                </span>
              )}
            />
          </div>
        </div>
      )}
    </Column>
  );
};

// eslint-disable-next-line import/no-default-export
export default SystemSession;
