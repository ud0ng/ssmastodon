// 웹 컨텐츠 진행 화면 (/system/sessions/:id): 위에 지금 게임판(버튼으로 바로 진행), 아래에 지난 카드들.
import { useCallback, useEffect, useState } from 'react';

import { defineMessages, FormattedMessage, useIntl } from 'react-intl';

import { Link, useParams } from 'react-router-dom';

import StarIcon from '@/styles/bird-theme-svg/star.svg?react';
import { apiRequestGet } from 'mastodon/api';
import { Column } from 'mastodon/components/column';
import { ColumnHeader } from 'mastodon/components/column_header';
import { ContentCardView } from 'mastodon/components/content_card';
import { LoadingIndicator } from 'mastodon/components/loading_indicator';
import { RelativeTimestamp } from 'mastodon/components/relative_timestamp';

import type { SessionData } from './board';
import { GameBoard } from './board';

const messages = defineMessages({
  title: { id: 'system.session.title', defaultMessage: 'Game' },
});

const REFRESH_MS = 20_000;

const SystemSession: React.FC<{ multiColumn?: boolean }> = ({ multiColumn }) => {
  const intl = useIntl();
  const { id } = useParams<{ id: string }>();
  const [data, setData] = useState<SessionData | null>(null);
  const [failed, setFailed] = useState(false);

  const load = useCallback(() => {
    apiRequestGet<SessionData>(`v1/system/sessions/${id}`)
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

  const title = data?.name ?? intl.formatMessage(messages.title);
  const earlier = data ? data.events.slice(0, -1).reverse() : [];

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

        {data && (
          <>
            <Link className='system-game-page__more' to={`/system/games/${data.kind}`}>
              <FormattedMessage id='system.session.game_page' defaultMessage='{name} page' values={{ name: data.name }} />
            </Link>
            <GameBoard sessionId={data.id} onChanged={load} showLog={false} />

            {earlier.length > 0 && (
              <ol className='system-session__events'>
                {earlier.map((event) => (
                  <li key={event.id} className='system-session__event'>
                    <div className='system-session__meta'>
                      <RelativeTimestamp timestamp={event.created_at} />
                      <Link to={`/@${data.system_acct}/${event.status_id}`}>
                        <FormattedMessage id='system.session.toot' defaultMessage='Toot' />
                      </Link>
                    </div>
                    <ContentCardView card={event.card} />
                    {event.text && <p className='system-session__text'>{event.text}</p>}
                  </li>
                ))}
              </ol>
            )}
          </>
        )}
      </div>
    </Column>
  );
};

// eslint-disable-next-line import/no-default-export
export default SystemSession;
