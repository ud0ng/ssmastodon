// 웹 컨텐츠 진행 화면 (/system/sessions/:id): 한 판의 시스템 툿 카드를 위에서부터 차례로.
// 스레드를 따라가지 않아도 한 화면에서 흐름을 보고, 내 차례면 맨 아래 카드의 버튼으로 바로 답한다.
import { useCallback, useEffect, useState } from 'react';

import { defineMessages, FormattedMessage, useIntl } from 'react-intl';

import { Link, useParams } from 'react-router-dom';

import StarIcon from '@/styles/bird-theme-svg/star.svg?react';
import {
  changeCompose,
  changeComposeVisibility,
  focusCompose,
  replyComposeById,
  resetCompose,
} from 'mastodon/actions/compose';
import { importFetchedStatus } from 'mastodon/actions/importer';
import { apiRequestGet } from 'mastodon/api';
import api from 'mastodon/api';
import { Column } from 'mastodon/components/column';
import { ColumnHeader } from 'mastodon/components/column_header';
import type { CardAction, GameCard } from 'mastodon/components/content_card';
import { ContentCardView } from 'mastodon/components/content_card';
import { LoadingIndicator } from 'mastodon/components/loading_indicator';
import { RelativeTimestamp } from 'mastodon/components/relative_timestamp';
import { useAppDispatch } from 'mastodon/store';

import { MazePlay } from './maze';

const messages = defineMessages({
  title: { id: 'system.session.title', defaultMessage: 'Game' },
});

const REFRESH_MS = 20_000;

interface SessionEvent {
  id: string;
  status_id: string;
  created_at: string;
  text: string;
  card: GameCard;
}

interface Session {
  id: string;
  kind: string;
  name: string;
  status: GameCard['phase'];
  system_acct: string;
  root_status_id: string | null;
  events: SessionEvent[];
}

const SystemSession: React.FC<{ multiColumn?: boolean }> = ({ multiColumn }) => {
  const intl = useIntl();
  const dispatch = useAppDispatch();
  const { id } = useParams<{ id: string }>();
  const [data, setData] = useState<Session | null>(null);
  const [failed, setFailed] = useState(false);

  const load = useCallback(() => {
    apiRequestGet<Session>(`v1/system/sessions/${id}`)
      .then((session) => {
        setData(session);
        setFailed(false);
        return session;
      })
      .catch(() => {
        setFailed(true);
      });
  }, [id]);

  useEffect(() => {
    load();
    const timer = window.setInterval(load, REFRESH_MS);
    return () => {
      window.clearInterval(timer);
    };
  }, [load]);

  // 버튼: 공개 진행이면 그 툿에 답장, 비밀 선택이면 시스템 계정에게 DM
  const handleAction = useCallback(
    (event: SessionEvent, action: CardAction) => {
      if (!data) return;
      const text = `@${data.system_acct} [${action.command}]${action.mention ? ` @${action.mention}` : ''}`;

      if (action.dm) {
        dispatch(resetCompose());
        dispatch(changeComposeVisibility('direct'));
        dispatch(changeCompose(text));
        dispatch(focusCompose());
        return;
      }

      void api()
        .get(`/api/v1/statuses/${event.status_id}`)
        .then((response) => {
          dispatch(importFetchedStatus(response.data));
          dispatch(replyComposeById(event.status_id));
          dispatch(changeCompose(text));
          return response;
        });
    },
    [data, dispatch],
  );

  const title = data?.name ?? intl.formatMessage(messages.title);

  return (
    <Column bindToDocument={!multiColumn} label={title}>
      <ColumnHeader icon='system' iconComponent={StarIcon} title={title} multiColumn={multiColumn} showBackButton />

      <div className='system-page system-session scrollable'>
        {!data && !failed && <LoadingIndicator />}
        {failed && !data && (
          <p className='system-page__empty'>
            <FormattedMessage id='system.load_failed' defaultMessage='Could not load. Try again in a moment.' />
          </p>
        )}

        {data?.kind === 'maze' && data.status === 'active' && <MazePlay sessionId={data.id} onMoved={load} />}

        {data && (
          <ol className='system-session__events'>
            {data.events.map((event) => (
              <li key={event.id} className='system-session__event'>
                <div className='system-session__meta'>
                  <RelativeTimestamp timestamp={event.created_at} />
                  <Link to={`/@${data.system_acct}/${event.status_id}`}>
                    <FormattedMessage id='system.session.toot' defaultMessage='Toot' />
                  </Link>
                </div>
                <ContentCardView card={event.card} onAction={(action) => { handleAction(event, action); }} />
                {event.text && <p className='system-session__text'>{event.text}</p>}
              </li>
            ))}
          </ol>
        )}
      </div>
    </Column>
  );
};

// eslint-disable-next-line import/no-default-export
export default SystemSession;
