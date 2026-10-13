// 웹 게임판: 한 판의 지금 상태(마지막 카드)와 버튼. 버튼은 서버원 대신 '@시스템 [명령어]' 툿을 올린다
// (POST /api/v1/system/commands, 진행은 툿으로 하던 그대로라 앱에서도 멘션 알림으로 보인다).
// 미로·도둑 지도는 전용 진행판, 나머지는 카드 + 버튼 + 직접 명령 칸 + 진행 기록.
import { useCallback, useEffect, useRef, useState } from 'react';

import { FormattedMessage, useIntl, defineMessages } from 'react-intl';

import { Link } from 'react-router-dom';

import { apiRequestGet, apiRequestPost } from 'mastodon/api';
import type { CardAction, GameCard } from 'mastodon/components/content_card';
import { ContentCardView } from 'mastodon/components/content_card';
import { LoadingIndicator } from 'mastodon/components/loading_indicator';
import { RelativeTimestamp } from 'mastodon/components/relative_timestamp';

import { MaraudersMapPlay } from './marauders_map';
import { MazePlay } from './maze';

const messages = defineMessages({
  commandPlaceholder: { id: 'system.board.command_placeholder', defaultMessage: 'Command, e.g. brew/dragon blood bat wing' },
});

const REFRESH_MS = 5_000;
// 툿을 올리고 시스템이 처리할 때까지 잠깐 기다렸다 다시 읽는다
const AFTER_SEND_MS = [1_500, 4_000];

export interface SessionEvent {
  id: string;
  status_id: string;
  created_at: string;
  text: string;
  card: GameCard;
}

export interface SessionData {
  id: string;
  kind: string;
  name: string;
  status: GameCard['phase'];
  system_acct: string;
  root_status_id: string | null;
  events: SessionEvent[];
}

export const sendCommand = (params: Record<string, unknown>) =>
  apiRequestPost<{ status_id: string }>('v1/system/commands', params);

export const GameBoard: React.FC<{ sessionId: string; onChanged?: () => void; showLog?: boolean }> = ({ sessionId, onChanged, showLog = true }) => {
  const intl = useIntl();
  const [data, setData] = useState<SessionData | null>(null);
  const [busy, setBusy] = useState(false);
  const [sent, setSent] = useState<string | null>(null);
  const [command, setCommand] = useState('');
  const [dm, setDm] = useState(false);
  const timers = useRef<number[]>([]);

  const load = useCallback(() => {
    apiRequestGet<SessionData>(`v1/system/sessions/${sessionId}`)
      .then((session) => {
        setData(session);
        return session;
      })
      .catch(() => {
        setData(null);
      });
  }, [sessionId]);

  useEffect(() => {
    load();
    const timer = window.setInterval(load, REFRESH_MS);
    const pending = timers.current;
    return () => {
      window.clearInterval(timer);
      pending.forEach((id) => { window.clearTimeout(id); });
    };
  }, [load]);

  const send = useCallback(
    (params: Record<string, unknown>, label: string) => {
      setBusy(true);
      sendCommand({ session_id: sessionId, ...params })
        .then((response) => {
          setSent(label);
          AFTER_SEND_MS.forEach((delay) => {
            timers.current.push(window.setTimeout(() => {
              load();
              onChanged?.();
            }, delay));
          });
          return response;
        })
        .catch(() => {
          setSent(null);
        })
        .finally(() => {
          setBusy(false);
        });
    },
    [sessionId, load, onChanged],
  );

  const handleAction = useCallback(
    (action: CardAction) => {
      send({ command: action.command, dm: action.dm, target: action.mention }, action.label);
    },
    [send],
  );

  const handleCommand = useCallback(
    (event: React.FormEvent) => {
      event.preventDefault();
      const [name, ...rest] = command.replace(/[[\]]/g, '').split('/');
      if (!name?.trim()) return;
      send({ command: name.trim(), args: rest.join('/').trim() || undefined, dm }, command);
      setCommand('');
    },
    [command, dm, send],
  );

  if (!data) return <LoadingIndicator />;

  const last = data.events[data.events.length - 1];
  const open = data.status === 'pending' || data.status === 'active';

  return (
    <div className='system-board'>
      {data.kind === 'maze' && data.status === 'active' && <MazePlay sessionId={data.id} onMoved={load} />}
      {data.kind === 'marauders_map' && data.status === 'active' && <MaraudersMapPlay sessionId={data.id} onMoved={load} />}

      {last && <ContentCardView card={last.card} onAction={busy ? undefined : handleAction} />}

      {sent && open && (
        <p className='system-board__sent'>
          <FormattedMessage id='system.board.sent' defaultMessage='Sent [{command}]. The system will answer in a moment.' values={{ command: sent }} />
        </p>
      )}

      {open && (
        <form className='system-board__command' onSubmit={handleCommand}>
          <input
            type='text'
            value={command}
            onChange={(event) => { setCommand(event.target.value); }}
            placeholder={intl.formatMessage(messages.commandPlaceholder)}
            aria-label={intl.formatMessage(messages.commandPlaceholder)}
          />
          <label className='system-board__dm'>
            <input type='checkbox' checked={dm} onChange={(event) => { setDm(event.target.checked); }} />
            <FormattedMessage id='system.board.secret' defaultMessage='Secret (DM)' />
          </label>
          <button type='submit' className='content-card__action' disabled={busy || !command.trim()}>
            <FormattedMessage id='system.board.send' defaultMessage='Send' />
          </button>
        </form>
      )}

      {showLog && data.events.length > 0 && (
        <details className='system-board__log'>
          <summary>
            <FormattedMessage id='system.board.log' defaultMessage='Game log ({count})' values={{ count: data.events.length }} />
          </summary>
          <ol>
            {[...data.events].reverse().map((event) => (
              <li key={event.id}>
                <span className='system-board__log-time'>
                  <RelativeTimestamp timestamp={event.created_at} />
                  {' · '}
                  <Link to={`/@${data.system_acct}/${event.status_id}`}>
                    <FormattedMessage id='system.session.toot' defaultMessage='Toot' />
                  </Link>
                </span>
                <p>{event.text}</p>
              </li>
            ))}
          </ol>
        </details>
      )}
    </div>
  );
};
