// 웹 '시스템' 메뉴
//   /system         컨텐츠 고르기 (묶음별 타일) + 내 캐릭터·소속 점수 짧은 줄 + 내가 하는 판
//   /system/me      내 캐릭터·스탯·돈·인벤토리·성적표·최근 판
//   /system/houses  소속 점수 모래시계·토너먼트
// 컨텐츠를 고르면 게임 화면(game.tsx). 진행은 시스템 계정에게 보내는 툿이라 앱에서는 멘션 알림으로 한다.
import { useCallback, useEffect, useState } from 'react';

import { defineMessages, FormattedMessage, useIntl } from 'react-intl';

import { Helmet } from 'react-helmet';
import { Link, useParams } from 'react-router-dom';

import StarIcon from '@/styles/bird-theme-svg/star.svg?react';
import { apiRequestGet } from 'mastodon/api';
import { Column } from 'mastodon/components/column';
import { ColumnHeader } from 'mastodon/components/column_header';
import { ICONS } from 'mastodon/components/content_card';
import { LoadingIndicator } from 'mastodon/components/loading_indicator';
import { RelativeTimestamp } from 'mastodon/components/relative_timestamp';

const messages = defineMessages({
  title: { id: 'column.system', defaultMessage: 'System' },
  win: { id: 'system.result.win', defaultMessage: 'Win' },
  lose: { id: 'system.result.lose', defaultMessage: 'Loss' },
  draw: { id: 'system.result.draw', defaultMessage: 'Draw' },
});

const REFRESH_MS = 30_000;

const GROUP_TITLES: Record<string, React.ReactNode> = {
  duel: <FormattedMessage id='system.group.duel' defaultMessage='1:1 duels' />,
  group: <FormattedMessage id='system.group.group' defaultMessage='Group games' />,
  lesson: <FormattedMessage id='system.group.lesson' defaultMessage='Lessons' />,
  event: <FormattedMessage id='system.group.event' defaultMessage='Server events' />,
};

interface House {
  id: string;
  name: string;
  emoji: string;
  color: string;
  total: number;
}

interface Game {
  id: string;
  kind: string;
  name: string;
  status: 'pending' | 'active' | 'finished' | 'cancelled';
  result: 'win' | 'lose' | 'draw' | null;
  turn: number;
  deadline_at: string | null;
  finished_at: string | null;
  opponents: { name: string; acct: string }[];
  status_id: string | null;
}

interface TournamentMatch {
  id: string;
  status: 'waiting' | 'ready' | 'playing' | 'judging' | 'done';
  kind_name: string | null;
  scheduled_at: string | null;
  winner_acct: string | null;
  status_id: string | null;
  session_id?: string | null;
  players: { acct: string; name: string; house_id: string | null }[];
}

interface Tournament {
  id: string;
  name: string;
  status: 'running' | 'finished';
  reward: number;
  winner_house_id: string | null;
  wins: { house_id: string; wins: number }[];
  rounds: { name: string; matches: TournamentMatch[] }[];
}

interface Overview {
  system_acct: string;
  house_term: string;
  scoring_mode: 'points' | 'tournament';
  tournament: Tournament | null;
  houses: House[];
  character: {
    name: string;
    house_id: string | null;
    grade: number | null;
    profile: { name: string; value: string; color: string | null }[];
    stats: { name: string; value: string }[];
    money: number;
    currency: string;
    inventory: { name: string; count: number; note: string }[];
  };
  record: { win: number; lose: number; draw: number };
  active: Game[];
  recent: Game[];
  games: { key: string; name: string; command: string; max_opponents: number }[];
  lessons: { key: string; name: string; modes: 'both' | 'study' | 'class' }[];
  lesson_commands: Record<'study' | 'class' | 'join' | 'report', string>;
  report: {
    subjects: { key: string; name: string; best: string | null; count: number }[];
    spells: { name: string; level: number }[];
    patronus: string | null;
    points: number;
  };
  commands: Record<'accept' | 'decline' | 'forfeit' | 'points' | 'record', string>;
  catalog: { key: string; games: { key: string; name: string; summary: string; open: number; mine: boolean }[] }[];
}

// 소속 문장: 소속 색 방패에 이름 첫 글자 (이모지 대신)
const Crest: React.FC<{ house?: House; large?: boolean }> = ({ house, large }) => (
  <span
    className={large ? 'system-crest system-crest--large' : 'system-crest'}
    style={{ '--house-color': house?.color || '#6b5b3e' } as React.CSSProperties}
    title={house?.name}
    aria-hidden
  >
    <span className='system-crest__inner'>{house ? Array.from(house.name)[0] : '?'}</span>
  </span>
);

const Hourglass: React.FC<{ house: House; max: number; mine: boolean }> = ({ house, max, mine }) => {
  const level = max > 0 ? Math.max(house.total, 0) / max : 0;

  return (
    <div className={mine ? 'system-hourglass system-hourglass--mine' : 'system-hourglass'} style={{ '--house-color': house.color || '#6b5b3e' } as React.CSSProperties}>
      <div className='system-hourglass__glass' aria-hidden>
        <div className='system-hourglass__vial'>
          <div className='system-hourglass__top' style={{ height: `${(1 - level) * 50}%` }} />
          <div className='system-hourglass__bottom' style={{ height: `${level * 50}%` }} />
        </div>
      </div>
      <div className='system-hourglass__name'><Crest house={house} />{house.name}</div>
      <div className='system-hourglass__total'>
        <FormattedMessage id='system.points' defaultMessage='{points} points' values={{ points: house.total }} />
      </div>
    </div>
  );
};

// 대진표 (사람). 경기마다 이긴 사람의 소속이 1승, 승수가 가장 많은 소속이 우승
const Bracket: React.FC<{ tournament: Tournament; houses: House[]; systemAcct: string }> = ({ tournament, houses, systemAcct }) => {
  const houseById = new Map(houses.map((house) => [house.id, house]));
  const champion = tournament.winner_house_id ? houseById.get(tournament.winner_house_id) : undefined;

  return (
    <div className='system-tournament'>
      <div className='system-tournament__head'>
        <strong>{tournament.name}</strong>
        {champion ? (
          <span className='system-tournament__champion'>
            <FormattedMessage id='system.tournament.champion' defaultMessage='Champion: {house}' values={{ house: champion.name }} />
          </span>
        ) : (
          <FormattedMessage id='system.tournament.reward' defaultMessage='Champion gets {points} points' values={{ points: tournament.reward }} />
        )}
      </div>

      {tournament.wins.length > 0 && (
        <div className='system-tournament__tally'>
          {[...tournament.wins].sort((a, b) => b.wins - a.wins).map(({ house_id, wins }) => {
            const house = houseById.get(house_id);
            return house ? (
              <span key={house_id}>
                <Crest house={house} />
                <FormattedMessage id='system.tournament.wins' defaultMessage='{house} {wins} wins' values={{ house: house.name, wins: <b>{wins}</b> }} />
              </span>
            ) : null;
          })}
        </div>
      )}

      <div className='system-bracket'>
        {tournament.rounds.map((round) => (
          <div className='system-bracket__round' key={round.name}>
            <div className='system-bracket__round-name'>{round.name}</div>
            {round.matches.map((match) => {
              const body = (
                <>
                  <div className='system-bracket__meta'>
                    {match.kind_name ?? '—'}
                    {match.scheduled_at && match.status !== 'done' && (
                      <> · {new Date(match.scheduled_at).toLocaleString(undefined, { month: 'numeric', day: 'numeric', hour: '2-digit', minute: '2-digit' })}</>
                    )}
                  </div>
                  {[0, 1].map((index) => {
                    const player = match.players[index];
                    const house = player?.house_id ? houseById.get(player.house_id) : undefined;
                    const won = player && match.winner_acct === player.acct;
                    return (
                      <div key={index} className={won ? 'system-bracket__player system-bracket__player--winner' : 'system-bracket__player'}>
                        <Crest house={house} />
                        <span className='system-bracket__name'>{player?.name ?? '?'}</span>
                      </div>
                    );
                  })}
                </>
              );
              const className = `system-bracket__match system-bracket__match--${match.status}`;
              return match.status_id ? (
                <Link key={match.id} className={className} to={match.session_id ? `/system/sessions/${match.session_id}` : `/@${systemAcct}/${match.status_id}`}>{body}</Link>
              ) : (
                <div key={match.id} className={className}>{body}</div>
              );
            })}
          </div>
        ))}
      </div>
    </div>
  );
};

// 성적표 (양피지): 과목별 가장 좋은 등급, 주문 숙련, 수호령, 이번 학기 기여
const ReportCard: React.FC<{ report: Overview['report'] }> = ({ report }) => (
  <div className='system-report'>
    <dl className='system-report__grades'>
      {report.subjects.map((subject) => (
        <div key={subject.key} className='system-report__row'>
          <dt>{subject.name}</dt>
          <dd className={subject.best ? `system-report__grade system-report__grade--${subject.best}` : 'system-report__grade'}>{subject.best ?? '—'}</dd>
        </div>
      ))}
    </dl>
    {(report.spells.length > 0 || report.patronus) && (
      <div className='system-report__extra'>
        {report.spells.length > 0 && (
          <div>
            <FormattedMessage id='system.report.spells' defaultMessage='Spells' />
            {': '}
            {report.spells.map((spell) => `${spell.name} Lv.${spell.level}`).join(' · ')}
          </div>
        )}
        {report.patronus && (
          <div>
            <FormattedMessage id='system.report.patronus' defaultMessage='Patronus: {patronus}' values={{ patronus: report.patronus }} />
          </div>
        )}
      </div>
    )}
    <div className='system-report__points'>
      <FormattedMessage id='system.report.points' defaultMessage='Contribution this term: {points}' values={{ points: report.points }} />
    </div>
  </div>
);

const GameRow: React.FC<{ game: Game; systemAcct: string }> = ({ game, systemAcct }) => {
  const intl = useIntl();
  const opponents = game.opponents.map((opponent) => opponent.name).join(', ');

  let state;
  if (game.status === 'pending') {
    state = <FormattedMessage id='system.game.pending' defaultMessage='Waiting for accept' />;
  } else if (game.status === 'active') {
    state = <FormattedMessage id='system.game.turn' defaultMessage='Turn {turn}' values={{ turn: game.turn }} />;
  } else if (game.result) {
    state = (
      <span className={`system-game__result system-game__result--${game.result}`}>
        {intl.formatMessage(messages[game.result])}
      </span>
    );
  }

  const time = game.status === 'finished' ? game.finished_at : game.deadline_at;
  const body = (
    <>
      <div className='system-game__main'>
        <strong className='system-game__name'>{game.name}</strong>
        {opponents && (
          <span className='system-game__opponents'>
            <FormattedMessage id='system.game.vs' defaultMessage='vs {names}' values={{ names: opponents }} />
          </span>
        )}
      </div>
      <div className='system-game__meta'>
        {state}
        {time && (
          <span className='system-game__time'>
            {game.status === 'finished' ? (
              <RelativeTimestamp timestamp={time} />
            ) : (
              <FormattedMessage id='system.game.until' defaultMessage='{time}' values={{ time: <RelativeTimestamp timestamp={time} futureDate /> }} />
            )}
          </span>
        )}
      </div>
    </>
  );

  return game.status_id ? (
    <Link className='system-game' to={`/system/sessions/${game.id}`}>{body}</Link>
  ) : (
    <div className='system-game'>{body}</div>
  );
};

const System: React.FC<{ multiColumn: boolean }> = ({ multiColumn }) => {
  const intl = useIntl();
  const [data, setData] = useState<Overview | null>(null);
  const [failed, setFailed] = useState(false);
  const { section } = useParams<{ section?: 'me' | 'houses' }>();

  const load = useCallback(() => {
    apiRequestGet<Overview>('v1/system')
      .then((overview) => {
        setData(overview);
        setFailed(false);
        return overview;
      })
      .catch(() => {
        setFailed(true);
      });
  }, []);

  useEffect(() => {
    load();
    const timer = window.setInterval(load, REFRESH_MS);
    return () => {
      window.clearInterval(timer);
    };
  }, [load]);

  const title = intl.formatMessage(messages.title);
  const max = data ? Math.max(...data.houses.map((house) => house.total), 0) : 0;
  const myHouse = data?.houses.find((house) => house.id === data.character.house_id);

  return (
    <Column bindToDocument={!multiColumn} label={title}>
      <ColumnHeader icon='system' iconComponent={StarIcon} title={title} multiColumn={multiColumn} showBackButton={!!section} />

      <div className='system-page scrollable'>
        {!data && !failed && <LoadingIndicator />}
        {failed && !data && (
          <p className='system-page__empty'>
            <FormattedMessage id='system.load_failed' defaultMessage='Could not load. Try again in a moment.' />
          </p>
        )}

        {data && !section && (
          <>
            {/* 위: 내 캐릭터 · 소속 점수 짧게 (누르면 각 화면) */}
            <div className='system-strips'>
              <Link className='system-strip' to='/system/me'>
                <Crest house={myHouse} />
                <span className='system-strip__main'>
                  <strong>{data.character.name}</strong>
                  <span className='system-strip__sub'>
                    <FormattedMessage id='system.record' defaultMessage='{win} W · {lose} L · {draw} D' values={data.record} />
                    {' · 💰 '}{data.character.money.toLocaleString()} {data.character.currency}
                  </span>
                </span>
                <span className='system-strip__go'>
                  <FormattedMessage id='system.me' defaultMessage='My character' /> ›
                </span>
              </Link>
              <Link className='system-strip' to='/system/houses'>
                <span className='system-strip__houses'>
                  {[...data.houses].sort((a, b) => b.total - a.total).map((house) => (
                    <span key={house.id} className='system-strip__house' style={{ '--house-color': house.color || '#6b5b3e' } as React.CSSProperties}>
                      <Crest house={house} /> {house.total}
                    </span>
                  ))}
                </span>
                <span className='system-strip__go'>
                  {data.scoring_mode === 'tournament' && data.tournament ? (
                    <FormattedMessage id='system.tournament' defaultMessage='Tournament' />
                  ) : (
                    <FormattedMessage id='system.houses' defaultMessage='{term} points' values={{ term: data.house_term }} />
                  )} ›
                </span>
              </Link>
            </div>

            {data.active.length > 0 && (
              <section className='system-section'>
                <h2 className='system-section__title'>
                  <FormattedMessage id='system.active' defaultMessage='In progress' />
                </h2>
                {data.active.map((game) => <GameRow key={game.id} game={game} systemAcct={data.system_acct} />)}
              </section>
            )}

            {data.catalog.filter((group) => group.games.length > 0).map((group) => (
              <section className='system-section' key={group.key}>
                <h2 className='system-section__title'>{GROUP_TITLES[group.key]}</h2>
                <div className='system-tiles'>
                  {group.games.map((game) => (
                    <Link key={game.key} className={game.mine ? 'system-tile system-tile--mine' : 'system-tile'} to={`/system/games/${game.key}`}>
                      <span className='system-tile__icon' aria-hidden>{ICONS[game.key] ?? '📜'}</span>
                      <span className='system-tile__name'>{game.name}</span>
                      <span className='system-tile__summary'>{game.summary}</span>
                      <span className='system-tile__meta'>
                        {game.mine && <span className='system-tile__badge'><FormattedMessage id='system.tile.mine' defaultMessage='Playing' /></span>}
                        {game.open > 0 && <FormattedMessage id='system.tile.open' defaultMessage='{count} in progress' values={{ count: game.open }} />}
                      </span>
                    </Link>
                  ))}
                </div>
              </section>
            ))}
          </>
        )}

        {data && section === 'houses' && (
          <>
            {data.scoring_mode === 'tournament' && data.tournament && (
              <section className='system-section'>
                <h2 className='system-section__title'>
                  <FormattedMessage id='system.tournament' defaultMessage='Tournament' />
                </h2>
                <Bracket tournament={data.tournament} houses={data.houses} systemAcct={data.system_acct} />
              </section>
            )}

            <section className='system-section'>
              <h2 className='system-section__title'>
                <FormattedMessage id='system.houses' defaultMessage='{term} points' values={{ term: data.house_term }} />
              </h2>
              <div className='system-hourglasses'>
                {data.houses.map((house) => (
                  <Hourglass key={house.id} house={house} max={max} mine={house.id === data.character.house_id} />
                ))}
              </div>
            </section>
          </>
        )}

        {data && section === 'me' && (
          <>
            <section className='system-section'>
              <h2 className='system-section__title'>
                <FormattedMessage id='system.me' defaultMessage='My character' />
              </h2>
              <div className='system-card'>
                <Crest house={myHouse} large />
                <div className='system-card__body'>
                  <div className='system-card__name'>
                    {data.character.name}
                    {data.character.grade && (
                      <span className='system-card__grade'>
                        <FormattedMessage id='system.grade' defaultMessage='Year {grade}' values={{ grade: data.character.grade }} />
                      </span>
                    )}
                  </div>
                  <div className='system-card__house'>
                    {myHouse ? myHouse.name : <FormattedMessage id='system.no_house' defaultMessage='No {term} yet' values={{ term: data.house_term }} />}
                  </div>
                  {data.character.profile.length > 0 && (
                    <div className='system-card__tags'>
                      {data.character.profile.map((item) => (
                        <span key={item.name} className='system-card__tag' style={{ '--tag-color': item.color ?? 'var(--ct-point, #6b5b3e)' } as React.CSSProperties} title={item.name}>
                          {item.value}
                        </span>
                      ))}
                    </div>
                  )}
                  <div className='system-card__record'>
                    <FormattedMessage
                      id='system.record'
                      defaultMessage='{win} W · {lose} L · {draw} D'
                      values={data.record}
                    />
                  </div>
                </div>
              </div>

              <div className='system-sheet'>
                {data.character.stats.length > 0 && (
                  <div className='system-sheet__stats'>
                    {data.character.stats.map((stat) => (
                      <div key={stat.name} className='system-sheet__stat'>
                        <span>{stat.name}</span>
                        <strong>{stat.value}</strong>
                      </div>
                    ))}
                  </div>
                )}
                <div className='system-sheet__money'>
                  💰 <strong>{data.character.money.toLocaleString()}</strong> {data.character.currency}
                </div>
                <div className='system-sheet__inventory'>
                  <h3>
                    <FormattedMessage id='system.inventory' defaultMessage='Inventory' />
                  </h3>
                  {data.character.inventory.length > 0 ? (
                    <ul>
                      {data.character.inventory.map((item, index) => (
                        // eslint-disable-next-line react/no-array-index-key
                        <li key={index}>
                          <span className='system-sheet__item'>{item.name}</span>
                          <span className='system-sheet__count'>×{item.count}</span>
                          {item.note && <span className='system-sheet__note'>{item.note}</span>}
                        </li>
                      ))}
                    </ul>
                  ) : (
                    <p className='system-sheet__empty'>
                      <FormattedMessage id='system.inventory_empty' defaultMessage='No items yet.' />
                    </p>
                  )}
                </div>
              </div>
            </section>

            <section className='system-section'>
              <h2 className='system-section__title'>
                <FormattedMessage id='system.report' defaultMessage='Report card' />
              </h2>
              <ReportCard report={data.report} />
            </section>

            <section className='system-section'>
              <h2 className='system-section__title'>
                <FormattedMessage id='system.active' defaultMessage='In progress' />
              </h2>
              {data.active.length > 0 ? (
                data.active.map((game) => <GameRow key={game.id} game={game} systemAcct={data.system_acct} />)
              ) : (
                <p className='system-page__empty'>
                  <FormattedMessage id='system.active.empty' defaultMessage='No game in progress.' />
                </p>
              )}
            </section>

            {data.recent.length > 0 && (
              <section className='system-section'>
                <h2 className='system-section__title'>
                  <FormattedMessage id='system.recent' defaultMessage='Recent' />
                </h2>
                {data.recent.map((game) => <GameRow key={game.id} game={game} systemAcct={data.system_acct} />)}
              </section>
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
export default System;
