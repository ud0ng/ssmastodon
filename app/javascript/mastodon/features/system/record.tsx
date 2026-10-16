// 웹 성적 화면 (/system/record, 글쓰기 패널 아래 [전적]에서 들어온다). 재화 화면과 같은 짜임:
//   맨 위 카드 (소속 문장 · 캐릭터 이름 / 전적 / 스탯) → 전체·승리·패배·무승부 탭 → 컨텐츠 기록 (날짜별, 더 보기)
// 데이터: GET /api/v1/system (캐릭터·스탯·전적), GET /api/v1/system/history?filter= (끝낸 판, max_id 로 다음 쪽)
import { useCallback, useEffect, useMemo, useState } from 'react';

import { defineMessages, FormattedDate, FormattedMessage, FormattedTime, useIntl } from 'react-intl';

import { Helmet } from 'react-helmet';
import { Link } from 'react-router-dom';

import FlagIcon from '@/material-icons/400-24px/flag.svg?react';
import { apiRequestGet } from 'mastodon/api';
import { Column } from 'mastodon/components/column';
import { ColumnHeader } from 'mastodon/components/column_header';
import { ICONS } from 'mastodon/components/content_card';
import { LoadMore } from 'mastodon/components/load_more';
import { LoadingIndicator } from 'mastodon/components/loading_indicator';

import { Crest } from './crest';
import type { Overview } from './index';

const messages = defineMessages({
  title: { id: 'record.title', defaultMessage: 'Record' },
  summary: { id: 'wallet.record_summary', defaultMessage: '{win}W {lose}L {draw}D' },
  win: { id: 'system.result.win', defaultMessage: 'Win' },
  lose: { id: 'system.result.lose', defaultMessage: 'Loss' },
  draw: { id: 'system.result.draw', defaultMessage: 'Draw' },
});

type Result = 'win' | 'lose' | 'draw';
type Filter = 'all' | Result;

const FILTERS: Filter[] = ['all', 'win', 'lose', 'draw'];

interface HistoryGame {
  id: string;
  session_id: string;
  kind: string;
  name: string;
  result: Result | null;
  opponents: string[];
  finished_at: string;
  points: number;
  money: number;
  items: { name: string; count: number }[];
}

const RESULT_LABELS: Record<Filter, React.ReactNode> = {
  all: <FormattedMessage id='wallet.filter.all' defaultMessage='All' />,
  win: <FormattedMessage id='system.result.win' defaultMessage='Win' />,
  lose: <FormattedMessage id='system.result.lose' defaultMessage='Loss' />,
  draw: <FormattedMessage id='system.result.draw' defaultMessage='Draw' />,
};

// 결과마다 줄 색: 승리 = 포인트색(재화 획득처럼), 패배·무승부 = 회색
const ROW_TONES: Record<Result, string> = { win: 'gain', lose: 'item', draw: 'item' };

const dayKey = (value: string | Date) => {
  const date = new Date(value);
  return `${date.getFullYear()}-${date.getMonth()}-${date.getDate()}`;
};

const signed = (value: number) => (value > 0 ? `+${value.toLocaleString()}` : value.toLocaleString());

// 날짜 묶음 제목: 오늘 / 어제 / 10월 14일 (화) — 재화 기록과 같다
const DayTitle: React.FC<{ iso: string }> = ({ iso }) => {
  const now = new Date();
  if (dayKey(iso) === dayKey(now)) return <FormattedMessage id='wallet.today' defaultMessage='Today' />;
  if (dayKey(iso) === dayKey(new Date(now.getTime() - 86_400_000))) return <FormattedMessage id='wallet.yesterday' defaultMessage='Yesterday' />;
  return <FormattedDate value={iso} month='long' day='numeric' weekday='short' />;
};

// 기록 한 줄 (재화 기록 줄과 같은 모양): [컨텐츠 아이콘] 컨텐츠 / 함께한 사람 · 시각 / 받은 점수·재화·아이템 … 오른쪽에 결과
const RecordRow: React.FC<{ game: HistoryGame; currency: string }> = ({ game, currency }) => {
  const intl = useIntl();
  return (
    <li>
      <Link to={`/system/sessions/${game.session_id}`} className={`wallet-record wallet-record--${game.result ? ROW_TONES[game.result] : 'item'} record-row`}>
        <span className='wallet-record__icon record-row__icon' aria-hidden>{ICONS[game.kind] ?? '📜'}</span>
        <div className='wallet-record__main'>
          <span className='wallet-record__title'>{game.name}</span>
          <span className='wallet-record__meta'>
            {game.opponents.length > 0 && (
              <>
                <FormattedMessage id='record.with' defaultMessage='with {names}' values={{ names: game.opponents.join(', ') }} />
                {' · '}
              </>
            )}
            <FormattedTime value={game.finished_at} hour='2-digit' minute='2-digit' />
          </span>
          {(game.points !== 0 || game.money !== 0 || game.items.length > 0) && (
            <span className='wallet-record__items'>
              {game.points !== 0 && (
                <span className='wallet-record__item'>
                  <FormattedMessage id='record.points' defaultMessage='{points} pts' values={{ points: signed(game.points) }} />
                </span>
              )}
              {game.money !== 0 && <span className='wallet-record__item'>{signed(game.money)} {currency}</span>}
              {game.items.map((item) => (
                <span key={item.name} className='wallet-record__item'>{item.name} +{item.count}</span>
              ))}
            </span>
          )}
        </div>
        <span className='wallet-record__amount record-row__result'>
          <strong>{game.result ? intl.formatMessage(messages[game.result]) : '—'}</strong>
        </span>
      </Link>
    </li>
  );
};

const RecordPage: React.FC<{ multiColumn: boolean }> = ({ multiColumn }) => {
  const intl = useIntl();
  const [data, setData] = useState<Overview | null>(null);
  const [filter, setFilter] = useState<Filter>('all');
  const [games, setGames] = useState<HistoryGame[] | null>(null);
  const [nextMaxId, setNextMaxId] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);

  useEffect(() => {
    apiRequestGet<Overview>('v1/system')
      .then((overview) => {
        setData(overview);
        return overview;
      })
      .catch(() => {
        setData(null);
      });
  }, []);

  const loadGames = useCallback((maxId?: string | null) => {
    setLoading(true);
    const params: Record<string, string> = {};
    if (maxId) params.max_id = maxId;
    if (filter !== 'all') params.filter = filter;
    apiRequestGet<{ games: HistoryGame[]; next_max_id: string | null }>('v1/system/history', params)
      .then((page) => {
        setGames((current) => (maxId ? [...(current ?? []), ...page.games] : page.games));
        setNextMaxId(page.next_max_id);
        return page;
      })
      .catch(() => {
        setGames((current) => current ?? []);
      })
      .finally(() => {
        setLoading(false);
      });
  }, [filter]);

  useEffect(() => {
    setGames(null);
    loadGames();
  }, [loadGames]);

  const handleMore = useCallback(() => {
    loadGames(nextMaxId);
  }, [loadGames, nextMaxId]);

  // 기록을 날짜별로 묶는다 (최신순)
  const groups = useMemo(
    () =>
      (games ?? []).reduce<{ key: string; iso: string; games: HistoryGame[] }[]>((list, game) => {
        const key = dayKey(game.finished_at);
        const last = list[list.length - 1];
        if (last?.key === key) last.games.push(game);
        else list.push({ key, iso: game.finished_at, games: [game] });
        return list;
      }, []),
    [games],
  );

  const title = intl.formatMessage(messages.title);
  const myHouse = data?.houses.find((house) => house.id === data.character.house_id);

  return (
    <Column bindToDocument={!multiColumn} label={title}>
      <ColumnHeader icon='flag' iconComponent={FlagIcon} title={title} multiColumn={multiColumn} showBackButton />

      <div className='scrollable wallet-page wallet-page--money record-page'>
        {!data ? (
          <LoadingIndicator />
        ) : (
          <>
            <div className='wallet-page__padded'>
              <div className='wallet-card record-card'>
                <span className='wallet-card__top'>
                  <span className='wallet-card__label record-card__who'>
                    {myHouse && <Crest house={myHouse} />}
                    {myHouse && <span>{myHouse.name}</span>}
                    {myHouse && <span aria-hidden>|</span>}
                    <span>{data.character.name}</span>
                  </span>
                </span>
                <span className='wallet-card__balance record-card__record'>
                  {/* 글자로 넣는다 (FormattedMessage 의 span 은 카드의 단위 글자 모양을 받는다) */}
                  <strong>{intl.formatMessage(messages.summary, data.record)}</strong>
                </span>
                {data.character.stats.length > 0 && (
                  <span className='wallet-card__stats record-card__stats'>
                    {data.character.stats.map((stat) => (
                      <span key={stat.name}>
                        {stat.name}
                        <strong>{stat.value}</strong>
                      </span>
                    ))}
                  </span>
                )}
              </div>
            </div>

            <div className='notification__filter-bar wallet-page__filter'>
              {FILTERS.map((key) => (
                <button key={key} type='button' className={filter === key ? 'active' : undefined} onClick={() => { setFilter(key); }}>
                  {RESULT_LABELS[key]}
                </button>
              ))}
            </div>

            {games === null ? (
              <LoadingIndicator />
            ) : groups.length === 0 ? (
              <p className='wallet-page__empty'>
                <FormattedMessage id='record.no_history' defaultMessage='No finished games yet.' />
              </p>
            ) : (
              <>
                {groups.map((group) => (
                  <section key={group.key} className='wallet-page__day'>
                    <h3 className='wallet-page__day-title'>
                      <DayTitle iso={group.iso} />
                    </h3>
                    <ul className='wallet-page__records'>
                      {group.games.map((game) => <RecordRow key={game.id} game={game} currency={data.character.currency} />)}
                    </ul>
                  </section>
                ))}
                {nextMaxId && <LoadMore onClick={handleMore} loading={loading} />}
              </>
            )}
          </>
        )}
      </div>

      <Helmet>
        <title>{title}</title>
        <meta name='robots' content='noindex' />
      </Helmet>
    </Column>
  );
};

// eslint-disable-next-line import/no-default-export
export default RecordPage;
