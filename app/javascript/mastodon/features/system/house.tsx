// 웹 소속 점수 화면 (글쓰기 패널 아래 소속 점수 카드를 누르면): /system/houses/:id
//   현재 소속 점수 · 가장 많이 획득한 사람 / 가장 많이 깎은 사람 · 내역 (전체/획득/차감 탭, 날짜별, 더 보기)
// 데이터: GET /api/v1/system/houses/:id?filter=gain|loss&max_id=
import { useCallback, useEffect, useMemo, useState } from 'react';

import { defineMessages, FormattedDate, FormattedMessage, FormattedTime, useIntl } from 'react-intl';

import { Helmet } from 'react-helmet';
import { useParams } from 'react-router-dom';

import StarIcon from '@/styles/bird-theme-svg/star.svg?react';
import { apiRequestGet } from 'mastodon/api';
import { Column } from 'mastodon/components/column';
import { ColumnHeader } from 'mastodon/components/column_header';
import { LoadMore } from 'mastodon/components/load_more';
import { LoadingIndicator } from 'mastodon/components/loading_indicator';

import { Crest } from './crest';

interface Person { name: string; acct: string; avatar: string; points: number }

interface PointRecord {
  id: string;
  amount: number;
  reason: string;
  created_at: string;
  character: Person | null;
}

interface HouseData {
  house: { id: string; name: string; color: string; total: number; term: string };
  top_gain: Person | null;
  top_loss: Person | null;
  records: PointRecord[];
  next_max_id: string | null;
}

type Filter = 'all' | 'gain' | 'loss';

const FILTERS: Filter[] = ['all', 'gain', 'loss'];

const messages = defineMessages({
  title: { id: 'house.title', defaultMessage: 'House points' },
});

const signed = (value: number) => (value > 0 ? `+${value.toLocaleString()}` : value.toLocaleString());

const dayKey = (value: string | Date) => {
  const date = new Date(value);
  return `${date.getFullYear()}-${date.getMonth()}-${date.getDate()}`;
};

const DayTitle: React.FC<{ iso: string }> = ({ iso }) => {
  const now = new Date();
  if (dayKey(iso) === dayKey(now)) return <FormattedMessage id='wallet.today' defaultMessage='Today' />;
  if (dayKey(iso) === dayKey(new Date(now.getTime() - 86_400_000))) return <FormattedMessage id='wallet.yesterday' defaultMessage='Yesterday' />;
  return <FormattedDate value={iso} month='long' day='numeric' weekday='short' />;
};

const FilterLabel: React.FC<{ filter: Filter }> = ({ filter }) => {
  switch (filter) {
  case 'gain':
    return <FormattedMessage id='house.filter.gain' defaultMessage='Gained' />;
  case 'loss':
    return <FormattedMessage id='house.filter.loss' defaultMessage='Lost' />;
  default:
    return <FormattedMessage id='house.filter.all' defaultMessage='All' />;
  }
};

const Points: React.FC<{ value: number; signedValue?: boolean }> = ({ value, signedValue = false }) => (
  <FormattedMessage id='house.points' defaultMessage='{points} pts' values={{ points: signedValue ? signed(value) : value.toLocaleString() }} />
);

// 재화 카드의 '누적 획득 / 누적 사용' 칸처럼 점선 칸막이로 나뉜 한 칸: 이름표 + 아바타 | 이름 | n점
const TopCell: React.FC<{ kind: 'gain' | 'loss'; person: Person | null }> = ({ kind, person }) => (
  <span className={`house-page__cell house-page__cell--${kind}`}>
    {kind === 'gain'
      ? <FormattedMessage id='house.top_gain' defaultMessage='Top earner' />
      : <FormattedMessage id='house.top_loss' defaultMessage='Top loser' />}
    {person ? (
      <span className='house-page__person'>
        <img src={person.avatar} alt='' className='house-page__avatar' />
        <span className='house-page__person-name'>{person.name}</span>
        <strong><Points value={person.points} signedValue /></strong>
      </span>
    ) : (
      <strong>—</strong>
    )}
  </span>
);

const RecordRow: React.FC<{ record: PointRecord }> = ({ record }) => (
  <li className={record.amount < 0 ? 'wallet-record wallet-record--spend' : 'wallet-record wallet-record--gain'}>
    <span className='wallet-record__icon house-page__icon'>
      {record.character ? <img src={record.character.avatar} alt='' /> : null}
    </span>
    <div className='wallet-record__main'>
      <span className='wallet-record__title'>{record.character?.name ?? record.reason}</span>
      <span className='wallet-record__meta'>
        {record.reason ? `${record.reason} · ` : ''}
        <FormattedTime value={record.created_at} hour='2-digit' minute='2-digit' />
      </span>
    </div>
    <span className='wallet-record__amount'>
      <strong>{signed(record.amount)}</strong>
      <span><FormattedMessage id='house.unit' defaultMessage='pts' /></span>
    </span>
  </li>
);

const HousePage: React.FC<{ multiColumn: boolean }> = ({ multiColumn }) => {
  const intl = useIntl();
  const { id } = useParams<{ id: string }>();
  const [filter, setFilter] = useState<Filter>('all');
  const [data, setData] = useState<HouseData | null>(null);
  const [records, setRecords] = useState<PointRecord[] | null>(null);
  const [next, setNext] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);
  const [failed, setFailed] = useState(false);

  const fetchPage = useCallback(
    (maxId: string | null) => {
      setLoading(true);
      apiRequestGet<HouseData>(`v1/system/houses/${id}`, { ...(filter === 'all' ? {} : { filter }), ...(maxId ? { max_id: maxId } : {}) })
        .then((response) => {
          setData(response);
          setRecords((current) => (maxId && current ? [...current, ...response.records] : response.records));
          setNext(response.next_max_id);
          setFailed(false);
          return response;
        })
        .catch(() => {
          setFailed(true);
          setRecords((current) => current ?? []);
        })
        .finally(() => {
          setLoading(false);
        });
    },
    [id, filter],
  );

  useEffect(() => {
    setRecords(null);
    fetchPage(null);
  }, [fetchPage]);

  const groups = useMemo(
    () =>
      (records ?? []).reduce<{ key: string; iso: string; records: PointRecord[] }[]>((list, record) => {
        const key = dayKey(record.created_at);
        const last = list[list.length - 1];
        if (last?.key === key) last.records.push(record);
        else list.push({ key, iso: record.created_at, records: [record] });
        return list;
      }, []),
    [records],
  );

  const title = intl.formatMessage(messages.title);

  return (
    <Column bindToDocument={!multiColumn} label={title}>
      <ColumnHeader icon='star' iconComponent={StarIcon} title={title} multiColumn={multiColumn} showBackButton />

      <div className='scrollable wallet-page house-page'>
        {!data && !failed && <LoadingIndicator />}
        {failed && !data && (
          <p className='wallet-page__empty'>
            <FormattedMessage id='system.load_failed' defaultMessage='Could not load. Try again in a moment.' />
          </p>
        )}

        {data && (
          <>
            <div className='wallet-page__padded'>
              <div className='wallet-card house-page__total'>
                <span className='wallet-card__top'>
                  <span className='wallet-card__label'>
                    <FormattedMessage id='house.current' defaultMessage='Current {term} points' values={{ term: data.house.term }} />
                  </span>
                  <span className='wallet-card__gift house-page__name'>{data.house.name}</span>
                </span>
                <span className='wallet-card__balance'>
                  <Crest house={{ ...data.house, emoji: '' }} large />
                  <strong>{data.house.total.toLocaleString()}</strong>
                  <span><FormattedMessage id='house.unit' defaultMessage='pts' /></span>
                </span>
                <span className='wallet-card__stats'>
                  <TopCell kind='gain' person={data.top_gain} />
                  <TopCell kind='loss' person={data.top_loss} />
                </span>
              </div>
            </div>

            <div className='notification__filter-bar wallet-page__filter'>
              {FILTERS.map((key) => (
                <button key={key} type='button' className={filter === key ? 'active' : undefined} onClick={() => { setFilter(key); }}>
                  <FilterLabel filter={key} />
                </button>
              ))}
            </div>

            {records === null ? (
              <LoadingIndicator />
            ) : groups.length === 0 ? (
              <p className='wallet-page__empty'>
                <FormattedMessage id='house.no_records' defaultMessage='No point history yet.' />
              </p>
            ) : (
              <>
                {groups.map((group) => (
                  <section key={group.key} className='wallet-page__day'>
                    <h3 className='wallet-page__day-title'>
                      <DayTitle iso={group.iso} />
                    </h3>
                    <ul className='wallet-page__records'>
                      {group.records.map((record) => <RecordRow key={record.id} record={record} />)}
                    </ul>
                  </section>
                ))}
                {next && <LoadMore onClick={() => { fetchPage(next); }} loading={loading} />}
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
export default HousePage;
