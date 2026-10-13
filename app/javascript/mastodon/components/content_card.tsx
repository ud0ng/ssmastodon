// 시스템 계정의 컨텐츠 툿을 PC 웹에서 카드로 보여 준다 (툿의 game_card, 서버 Game::Card).
// 카드 아래에는 툿 본문(진행 문구)이 그대로 이어진다. 앱은 game_card 를 모르니 지금처럼 텍스트로 보인다.
//
// 아직 진행 중인 판의 가장 최근 툿(live)이고 내 차례면 행동 버튼이 나온다.
// 누르면 '@시스템 [명령어]' 를 쓰는 창이 열린다 (비밀 선택은 DM 으로). 게시는 직접 누른다.
import { useCallback } from 'react';

import { FormattedMessage } from 'react-intl';

import type { Map as ImmutableMap } from 'immutable';

import { Link } from 'react-router-dom';

import {
  changeCompose,
  directCompose,
  replyCompose,
} from 'mastodon/actions/compose';
import { RelativeTimestamp } from 'mastodon/components/relative_timestamp';
import { me } from 'mastodon/initial_state';
import { useAppDispatch } from 'mastodon/store';

interface House {
  name: string;
  color: string;
  emoji: string;
}

interface CardPlayer {
  seat: number;
  account_id: string;
  acct: string;
  name: string;
  avatar?: string;
  house: House | null;
  result: 'win' | 'lose' | 'draw' | null;
  accepted: boolean;
}

export interface CardAction {
  label: string;
  command: string;
  mention?: string;
  seats: number[] | 'others';
  dm: boolean;
  style: 'primary' | 'secondary';
}

type Data = Record<string, unknown>;

export interface GameCard {
  session_id?: string;
  kind: string;
  name: string;
  lesson: boolean;
  mode: 'study' | 'class' | null;
  phase: 'pending' | 'active' | 'finished' | 'cancelled';
  turn: number;
  deadline_at: string | null;
  players: CardPlayer[];
  data: Data;
  actions: CardAction[];
  live: boolean;
  tournament?: { name: string; round: string; number: number } | null;
  awards?: { house: House | null; amount: number }[];
  rewards?: { name: string; money: number; currency: string; items: string[] }[];
}

const ICONS: Record<string, string> = {
  jellybean: '🍬',
  gobstones: '🔮',
  duel: '⚡',
  potion: '⚗️',
  quidditch: '🧹',
  levitation: '🪶',
  flying: '🧹',
  transfiguration: '🐈',
  practice: '✨',
  tournament: '🏆',
  secret_chamber: '🐍',
  maze: '🏆',
  marauders_map: '🗺️',
  weekly: '📜',
  term: '🏰',
};

const num = (value: unknown) => (typeof value === 'number' ? value : 0);
const bySeat = (value: unknown) =>
  (value && typeof value === 'object' ? value : {}) as Record<string, unknown>;

// 소속 문장 (시스템 화면과 같은 방패)
const Crest: React.FC<{ house: House | null }> = ({ house }) => (
  <span
    className='system-crest'
    style={{ '--house-color': house?.color || '#6b5b3e' } as React.CSSProperties}
    title={house?.name}
    aria-hidden
  >
    <span className='system-crest__inner'>
      {house ? Array.from(house.name)[0] : '?'}
    </span>
  </span>
);

const Hearts: React.FC<{ left: number; full: number }> = ({ left, full }) => (
  <span className='content-card__hearts' aria-label={`${left}/${full}`}>
    {Array.from({ length: Math.max(full, left) }, (_, index) => (
      <span
        key={index}
        className={index < left ? 'content-card__heart' : 'content-card__heart content-card__heart--lost'}
      >
        ♥
      </span>
    ))}
  </span>
);

// 플레이어 옆에 붙는 한 줄 (점수·체력·시도 수·등급)
const PlayerStat: React.FC<{ card: GameCard; player: CardPlayer }> = ({ card, player }) => {
  const seat = String(player.seat);
  const { data } = card;
  if (card.phase === 'pending') return null;

  switch (card.kind) {
    case 'gobstones':
    case 'quidditch':
      return <span className='content-card__score'>{num(bySeat(data.scores)[seat])}</span>;
    case 'duel':
      return <Hearts left={num(bySeat(data.hp)[seat])} full={num(data.max_hp)} />;
    case 'potion':
      return (
        <span className='content-card__chip'>
          <FormattedMessage
            id='content_card.tries'
            defaultMessage='{tries}/{max} tries'
            values={{ tries: num(bySeat(data.tries)[seat]), max: num(data.max_tries) }}
          />
        </span>
      );
    default: {
      if (!card.lesson) return null;
      const grade = bySeat(bySeat(data.grades)[seat]).grade as string | undefined;
      return grade ? (
        <span className={`content-card__grade content-card__grade--${grade}`} title={String(bySeat(data.grade_names)[grade] ?? '')}>
          {grade}
        </span>
      ) : null;
    }
  }
};

const Players: React.FC<{ card: GameCard }> = ({ card }) => {
  const current = card.data.current_seat;
  const chosen = Array.isArray(card.data.chosen) ? (card.data.chosen as string[]) : [];
  // 팀전 (퀴디치): 자리 → 팀 키, 팀 키 → 이름
  const teams = (card.data.teams ?? {}) as Record<string, string | undefined>;
  const teamNames = (card.data.team_names ?? {}) as Record<string, string | undefined>;

  return (
    <div className={card.players.length === 2 ? 'content-card__players content-card__players--versus' : 'content-card__players'}>
      {card.players.map((player, index) => {
        const isTurn = card.phase === 'active' && current === player.seat;
        return (
          <div
            key={player.seat}
            className={[
              'content-card__player',
              isTurn && 'content-card__player--turn',
              player.result && `content-card__player--${player.result}`,
              card.phase === 'pending' && !player.accepted && 'content-card__player--waiting',
            ].filter(Boolean).join(' ')}
            style={{ '--house-color': player.house?.color || '#6b5b3e', order: index * 2 } as React.CSSProperties}
          >
            {player.avatar && <img className='content-card__avatar' src={player.avatar} alt='' />}
            <div className='content-card__player-main'>
              <span className='content-card__player-name'>
                <Crest house={player.house} />
                {player.name}
              </span>
              <span className='content-card__player-sub'>
                {teams[String(player.seat)] && (
                  <span className={`content-card__badge content-card__badge--team-${teams[String(player.seat)]}`}>
                    {String(teamNames[teams[String(player.seat)] ?? ''] ?? teams[String(player.seat)])}
                  </span>
                )}
                <PlayerStat card={card} player={player} />
                {isTurn && (
                  <span className='content-card__badge content-card__badge--turn'>
                    <FormattedMessage id='content_card.turn' defaultMessage='Your move' />
                  </span>
                )}
                {card.phase === 'active' && chosen.includes(String(player.seat)) && (
                  <span className='content-card__badge'>
                    <FormattedMessage id='content_card.chosen' defaultMessage='Chosen' />
                  </span>
                )}
                {card.phase === 'pending' && !card.lesson && (
                  <span className='content-card__badge'>
                    {player.accepted ? (
                      <FormattedMessage id='content_card.accepted' defaultMessage='Ready' />
                    ) : (
                      <FormattedMessage id='content_card.waiting' defaultMessage='Waiting' />
                    )}
                  </span>
                )}
                {player.result && (
                  <span className={`content-card__badge content-card__badge--${player.result}`}>
                    {player.result === 'win' && <FormattedMessage id='system.result.win' defaultMessage='Win' />}
                    {player.result === 'lose' && <FormattedMessage id='system.result.lose' defaultMessage='Loss' />}
                    {player.result === 'draw' && <FormattedMessage id='system.result.draw' defaultMessage='Draw' />}
                  </span>
                )}
              </span>
            </div>
          </div>
        );
      })}
      {card.players.length === 2 && <span className='content-card__versus' style={{ order: 1 }}>VS</span>}
    </div>
  );
};

// 컨텐츠별 가운데 판
const Board: React.FC<{ card: GameCard }> = ({ card }) => {
  const { data } = card;
  // 신청·모집 중에는 아직 판이 없다
  if (card.phase === 'pending' && !card.lesson && card.kind !== 'secret_chamber') return null;
  const names = Object.fromEntries(card.players.map((player) => [String(player.seat), player.name]));

  switch (card.kind) {
    case 'jellybean': {
      const total = num(data.total);
      const remaining = num(data.remaining);
      const last = bySeat(data.last_eaten);
      const beans = Array.isArray(last.beans) ? (last.beans as { flavor: string; worst: boolean }[]) : [];
      return (
        <div className='content-card__board'>
          <div className='content-card__beans' aria-label={`${remaining}/${total}`}>
            {Array.from({ length: total }, (_, index) => (
              <span key={index} className={index < total - remaining ? 'content-card__bean content-card__bean--eaten' : 'content-card__bean'} style={{ '--bean-hue': `${(index * 47) % 360}` } as React.CSSProperties} />
            ))}
          </div>
          <div className='content-card__line'>
            <FormattedMessage id='content_card.beans_left' defaultMessage='{remaining} of {total} left · {worst} worst' values={{ remaining, total, worst: num(data.worst_total) }} />
          </div>
          {beans.length > 0 && (
            <div className='content-card__chips'>
              <span className='content-card__chips-label'>{names[String(last.seat)]}</span>
              {beans.map((bean, index) => (
                <span key={index} className={bean.worst ? 'content-card__chip content-card__chip--bad' : 'content-card__chip'}>{bean.flavor}</span>
              ))}
            </div>
          )}
        </div>
      );
    }

    case 'gobstones': {
      const rounds = num(data.rounds);
      const throws = num(data.throws);
      const total = rounds * card.players.length;
      const last = data.last_throw ? bySeat(data.last_throw) : null;
      return (
        <div className='content-card__board'>
          <div className='content-card__progress'>
            <span style={{ width: `${total ? (throws / total) * 100 : 0}%` }} />
          </div>
          <div className='content-card__line'>
            <FormattedMessage id='content_card.throws' defaultMessage='{throws}/{total} throws' values={{ throws, total }} />
          </div>
          {last && (
            <div className='content-card__chips'>
              <span className='content-card__chips-label'>{names[String(last.seat)]}</span>
              {last.strength ? <span className='content-card__chip'>{String(last.strength)}</span> : null}
              <span className={last.hit ? 'content-card__chip content-card__chip--good' : num(last.score) < 0 ? 'content-card__chip content-card__chip--bad' : 'content-card__chip'}>
                {last.hit ? `+${num(last.score)}` : num(last.score) < 0 ? `${num(last.score)}` : '0'}
              </span>
            </div>
          )}
        </div>
      );
    }

    case 'duel':
    case 'quidditch': {
      const last = data.last_round ? bySeat(data.last_round) : null;
      const choices = last ? bySeat(last.choices) : {};
      const winner = last?.winner_seat;
      const caught = Array.isArray(last?.caught) ? (last.caught as number[]) : [];
      return (
        <div className='content-card__board'>
          {last ? (
            <div className='content-card__clash'>
              {card.players.map((player) => (
                <span
                  key={player.seat}
                  className={[
                    'content-card__spell',
                    winner === player.seat && 'content-card__spell--win',
                    caught.includes(player.seat) && 'content-card__spell--win',
                  ].filter(Boolean).join(' ')}
                >
                  {String(choices[String(player.seat)] ?? '—')}
                </span>
              ))}
            </div>
          ) : null}
          <div className='content-card__line'>
            {card.kind === 'quidditch' ? (
              <FormattedMessage
                id='content_card.snitch'
                defaultMessage='Snitch chance {rates} · up to {turns} turns'
                values={{
                  rates: card.players.map((player) => `${player.name} ${num(bySeat(data.seek)[String(player.seat)])}%`).join(' · '),
                  turns: num(data.max_turns),
                }}
              />
            ) : (
              <FormattedMessage id='content_card.max_turns' defaultMessage='Up to {turns} turns' values={{ turns: num(data.max_turns) }} />
            )}
          </div>
        </div>
      );
    }

    case 'potion': {
      const ingredients = Array.isArray(data.ingredients) ? (data.ingredients as string[]) : [];
      const answer = Array.isArray(data.answer) ? (data.answer as string[]) : null;
      const guesses = bySeat(data.guesses);
      return (
        <div className='content-card__board'>
          <div className='content-card__line content-card__line--title'>
            {String(data.potion ?? '')}
            <span className='content-card__dim'>
              <FormattedMessage id='content_card.answer_size' defaultMessage='{size} ingredients in order' values={{ size: num(data.answer_size) }} />
            </span>
          </div>
          <div className='content-card__chips'>
            {ingredients.map((name, index) => (
              <span key={name} className={answer?.includes(name) ? 'content-card__chip content-card__chip--good' : 'content-card__chip'}>
                {index + 1}. {name}
              </span>
            ))}
          </div>
          {Object.keys(guesses).length > 0 && (
            <div className='content-card__guesses'>
              {card.players.map((player) => {
                const result = bySeat(guesses[String(player.seat)]);
                const strike = num(result.strike);
                const ball = num(result.ball);
                return (
                  <span key={player.seat} className='content-card__guess'>
                    {player.name}
                    <span className='content-card__dots'>
                      {Array.from({ length: strike }, (_, i) => <span key={`s${i}`} className='content-card__dot content-card__dot--strike' />)}
                      {Array.from({ length: ball }, (_, i) => <span key={`b${i}`} className='content-card__dot' />)}
                    </span>
                  </span>
                );
              })}
            </div>
          )}
          {answer && (
            <div className='content-card__line'>
              <FormattedMessage id='content_card.answer' defaultMessage='Answer: {answer}' values={{ answer: answer.join(' → ') }} />
            </div>
          )}
        </div>
      );
    }

    case 'secret_chamber': {
      const alive = Array.isArray(data.alive) ? (data.alive as number[]) : [];
      const out = Array.isArray(data.out) ? (data.out as { seat: number; role_name: string; faction: string; by: string; day: number }[]) : [];
      const votes = bySeat(data.votes);
      const roles = data.roles ? bySeat(data.roles) : null;
      const bySeatPlayer = Object.fromEntries(card.players.map((player) => [String(player.seat), player]));
      const phase = String(data.phase ?? '');
      return (
        <div className='content-card__board'>
          <div className='content-card__line content-card__line--title'>
            {phase === 'day' && <FormattedMessage id='content_card.chamber.day' defaultMessage='☀️ Day {day}' values={{ day: num(data.day) }} />}
            {phase === 'night' && <FormattedMessage id='content_card.chamber.night' defaultMessage='🌙 Night {day}' values={{ day: num(data.day) }} />}
            {data.winner ? (
              <FormattedMessage id='content_card.chamber.winner' defaultMessage='{faction} wins' values={{ faction: String(data.winner === 'dark' ? data.faction_dark : data.faction_light) }} />
            ) : null}
            {card.phase === 'pending' ? (
              <FormattedMessage id='content_card.chamber.joined' defaultMessage='{count} joined' values={{ count: card.players.length }} />
            ) : (
            <span className='content-card__dim'>
              <FormattedMessage id='content_card.chamber.counts' defaultMessage='{alive} left · {traitors} {traitor}' values={{ alive: alive.length, traitors: num(data.traitors), traitor: String(data.traitor_name ?? '') }} />
            </span>
            )}
          </div>
          <div className='content-card__roster'>
            {card.players.map((player) => {
              const isOut = !alive.includes(player.seat) && phase !== 'recruit' && card.phase !== 'pending';
              const voteCount = num(votes[String(player.seat)]);
              return (
                <span key={player.seat} className={isOut ? 'content-card__member content-card__member--out' : 'content-card__member'} style={{ '--house-color': player.house?.color || '#6b5b3e' } as React.CSSProperties}>
                  <Crest house={player.house} />
                  {player.name}
                  {roles && <span className='content-card__role'>{String(roles[String(player.seat)] ?? '')}</span>}
                  {voteCount > 0 && <span className='content-card__votes'>{voteCount}</span>}
                </span>
              );
            })}
          </div>
          {out.length > 0 && (
            <div className='content-card__chips'>
              {out.map((entry) => (
                <span key={entry.seat} className={entry.faction === data.faction_dark ? 'content-card__chip content-card__chip--bad' : 'content-card__chip'}>
                  {bySeatPlayer[String(entry.seat)]?.name} · {entry.role_name}
                </span>
              ))}
            </div>
          )}
        </div>
      );
    }

    case 'marauders_map': {
      const targets = Array.isArray(data.targets) ? (data.targets as { room: string; visited: boolean }[]) : [];
      const log = Array.isArray(data.log) ? (data.log as string[]) : [];
      return (
        <div className='content-card__board'>
          <div className='content-card__chips'>
            {targets.map((target) => (
              <span key={target.room} className={target.visited ? 'content-card__chip content-card__chip--good' : 'content-card__chip'}>{target.visited ? '✅' : '⭐'} {target.room}</span>
            ))}
          </div>
          {log.length > 0 && (
            <ul className='content-card__log'>
              {log.map((line, index) => <li key={index}>{line}</li>)}
            </ul>
          )}
          {card.live && card.session_id && (
            <Link className='content-card__action' to={`/system/sessions/${card.session_id}`}>
              <FormattedMessage id='content_card.play_web' defaultMessage='Play on the web' />
            </Link>
          )}
        </div>
      );
    }

    case 'maze': {
      const log = Array.isArray(data.log) ? (data.log as string[]) : [];
      const status = bySeat(data.status);
      return (
        <div className='content-card__board'>
          <div className='content-card__chips'>
            {card.players.map((player) => {
              const flags = bySeat(status[String(player.seat)]);
              const marks = [num(flags.stunned) > 0 && '💫', flags.hostile && '⚔️', flags.boost && '🤝', num(flags.lumos) > 0 && '💡'].filter(Boolean).join('');
              return marks ? <span key={player.seat} className='content-card__chip'>{player.name} {marks}</span> : null;
            })}
          </div>
          {log.length > 0 && (
            <ul className='content-card__log'>
              {log.map((line, index) => <li key={index}>{line}</li>)}
            </ul>
          )}
          {card.live && card.session_id && (
            <Link className='content-card__action' to={`/system/sessions/${card.session_id}`}>
              <FormattedMessage id='content_card.play_web' defaultMessage='Play on the web' />
            </Link>
          )}
        </div>
      );
    }

    case 'weekly':
    case 'term': {
      const rows = Array.isArray(data.houses) ? (data.houses as { house: House | null; gained?: number; total: number }[]) : [];
      const weekly = card.kind === 'weekly';
      const most = Math.max(1, ...rows.map((row) => Math.abs(weekly ? num(row.gained) : num(row.total))));
      const toppers = Array.isArray(data.toppers) ? (data.toppers as { subject: string; name: string; best: string }[]) : [];
      const champion = data.champion as House | null | undefined;
      return (
        <div className='content-card__board content-card__board--champion'>
          {weekly && <div className='content-card__line'>{String(data.range ?? '')}</div>}
          {champion && (
            <div className='content-card__champion'>
              <Crest house={champion} />
              <span>{champion.name}</span>
            </div>
          )}
          <div className='content-card__tally'>
            {rows.map((row) => (
              <div key={row.house?.name ?? '?'} className='content-card__tally-row' style={{ '--house-color': row.house?.color || '#6b5b3e' } as React.CSSProperties}>
                <span className='content-card__tally-name'>{row.house?.name}</span>
                <span className='content-card__tally-bar'><span style={{ width: `${(Math.abs(weekly ? num(row.gained) : num(row.total)) / most) * 100}%` }} /></span>
                <span>{weekly ? `+${num(row.gained)} / ${num(row.total)}` : num(row.total)}</span>
              </div>
            ))}
          </div>
          {weekly && (
            <div className='content-card__line'>
              <FormattedMessage
                id='content_card.weekly'
                defaultMessage='{games} games · most wins: {winners}'
                values={{ games: num(data.games), winners: Array.isArray(data.winners) && data.winners.length > 0 ? `${(data.winners as string[]).join(', ')} (${num(data.best)})` : '-' }}
              />
            </div>
          )}
          {toppers.length > 0 && (
            <div className='content-card__chips'>
              {toppers.map((row) => (
                <span key={row.subject} className='content-card__chip'>{row.subject}: {row.name} ({row.best})</span>
              ))}
            </div>
          )}
        </div>
      );
    }

    case 'tournament': {
      const champion = data.champion as House | null;
      const tally = Array.isArray(data.tally) ? (data.tally as { house: House | null; wins: number }[]) : [];
      const most = Math.max(1, ...tally.map((row) => row.wins));
      return (
        <div className='content-card__board content-card__board--champion'>
          {champion && (
            <div className='content-card__champion' style={{ '--house-color': champion.color || '#6b5b3e' } as React.CSSProperties}>
              <Crest house={champion} />
              <span>{champion.name}</span>
              {num(data.reward) > 0 && <span className='content-card__award-amount'>+{num(data.reward)}</span>}
            </div>
          )}
          <div className='content-card__tally'>
            {tally.map((row) => (
              <div key={row.house?.name ?? '?'} className='content-card__tally-row' style={{ '--house-color': row.house?.color || '#6b5b3e' } as React.CSSProperties}>
                <span className='content-card__tally-name'>{row.house?.name}</span>
                <span className='content-card__tally-bar'><span style={{ width: `${(row.wins / most) * 100}%` }} /></span>
                <FormattedMessage id='content_card.wins' defaultMessage='{wins} wins' values={{ wins: row.wins }} />
              </div>
            ))}
          </div>
        </div>
      );
    }

    default:
      if (card.lesson)
        return (
          <div className='content-card__board'>
            <div className='content-card__line'>
              {String(data.subject ?? card.name)} · {String(data.mode_name ?? '')}
            </div>
          </div>
        );
      return null;
  }
};

const PhaseBadge: React.FC<{ card: GameCard }> = ({ card }) => {
  switch (card.phase) {
    case 'pending':
      return card.mode === 'class' ? (
        <FormattedMessage id='content_card.phase.recruiting' defaultMessage='Recruiting' />
      ) : (
        <FormattedMessage id='content_card.phase.invite' defaultMessage='Challenge' />
      );
    case 'active':
      return card.turn > 0 ? (
        <FormattedMessage id='content_card.phase.turn' defaultMessage='Turn {turn}' values={{ turn: card.turn }} />
      ) : (
        <FormattedMessage id='content_card.phase.active' defaultMessage='In progress' />
      );
    case 'finished':
      return <FormattedMessage id='content_card.phase.finished' defaultMessage='Result' />;
    default:
      return <FormattedMessage id='content_card.phase.cancelled' defaultMessage='Cancelled' />;
  }
};

// 카드 한 장 (진행 화면에서도 쓴다). onAction 이 없으면 버튼을 그리지 않는다.
export const ContentCardView: React.FC<{
  card: GameCard;
  onAction?: (action: CardAction) => void;
  sessionLink?: boolean;
}> = ({ card, onAction, sessionLink }) => {
  const mySeat = card.players.find((player) => player.account_id === me)?.seat;
  const available = (card.live && onAction ? card.actions : []).filter((action) =>
    action.seats === 'others' ? mySeat === undefined && !!me : mySeat !== undefined && action.seats.includes(mySeat),
  );

  return (
    <div className={`content-card content-card--${card.phase} content-card--${card.kind}`}>
      <div className='content-card__head'>
        <span className='content-card__icon' aria-hidden>{ICONS[card.kind] ?? '📜'}</span>
        <span className='content-card__name'>{card.name}</span>
        {!['weekly', 'term', 'tournament'].includes(card.kind) && <span className='content-card__phase'><PhaseBadge card={card} /></span>}
        {card.tournament && (
          <span className='content-card__tournament'>
            🏆 {card.tournament.name} · {card.tournament.round} {card.tournament.number}
          </span>
        )}
        {card.live && card.deadline_at && (
          <span className='content-card__deadline'>
            <FormattedMessage
              id='content_card.deadline'
              defaultMessage='⏳ {time}'
              values={{ time: <RelativeTimestamp timestamp={card.deadline_at} futureDate /> }}
            />
          </span>
        )}
        {sessionLink && card.session_id && (
          <Link className='content-card__open' to={`/system/sessions/${card.session_id}`}>
            <FormattedMessage id='content_card.open' defaultMessage='Whole game' />
          </Link>
        )}
      </div>

      {card.kind !== 'secret_chamber' && <Players card={card} />}
      <Board card={card} />

      {card.awards && card.awards.length > 0 && (
        <div className='content-card__awards'>
          {card.awards.map((award, index) => (
            <span key={index} className='content-card__award' style={{ '--house-color': award.house?.color || '#6b5b3e' } as React.CSSProperties}>
              <Crest house={award.house} />
              {award.house?.name}
              <span className='content-card__award-amount'>{award.amount >= 0 ? `+${award.amount}` : award.amount}</span>
            </span>
          ))}
        </div>
      )}

      {card.rewards && card.rewards.length > 0 && (
        <ul className='content-card__rewards'>
          {card.rewards.map((reward, index) => (
            // eslint-disable-next-line react/no-array-index-key
            <li key={index}>
              <span className='content-card__reward-name'>{reward.name}</span>
              {reward.money > 0 && <span className='content-card__reward-money'>💰 {reward.money} {reward.currency}</span>}
              {reward.items.map((item) => (
                <span key={item} className='content-card__reward-item'>🎁 {item}</span>
              ))}
            </li>
          ))}
        </ul>
      )}

      {available.length > 0 && (
        <div className='content-card__actions'>
          {available.map((action) => (
            <button
              key={`${action.command}${action.mention ?? ''}`}
              type='button'
              className={action.style === 'primary' ? 'content-card__action' : 'content-card__action content-card__action--secondary'}
              onClick={() => { onAction?.(action); }}
              title={action.dm ? `DM: [${action.command}]` : `[${action.command}]`}
            >
              {action.label}
              {action.dm && <span className='content-card__action-dm'>DM</span>}
            </button>
          ))}
        </div>
      )}
      {card.live && mySeat !== undefined && card.kind === 'potion' && card.phase === 'active' && (
        <div className='content-card__hint'>
          <FormattedMessage id='content_card.potion_hint' defaultMessage='Send [{brew}] with your ingredients by DM, e.g. [{brew}] 1 5 3' values={{ brew: String(card.data.brew ?? '') }} />
        </div>
      )}
    </div>
  );
};

// 툿 안의 카드 (status.game_card). 버튼은 그 툿에 답장하거나 시스템 계정에 DM.
export const ContentCard: React.FC<{
  status: ImmutableMap<string, unknown>;
}> = ({ status }) => {
  const dispatch = useAppDispatch();
  const raw = status.get('game_card') as { toJS?: () => GameCard } | undefined;
  const card = raw?.toJS ? raw.toJS() : (raw as unknown as GameCard | undefined);
  const system = status.get('account') as ImmutableMap<string, unknown> | undefined;

  const handleAction = useCallback(
    (action: CardAction) => {
      if (!system) return;
      const text = `@${String(system.get('acct'))} [${action.command}]${action.mention ? ` @${action.mention}` : ''}`;
      if (action.dm) dispatch(directCompose(system));
      else dispatch(replyCompose(status));
      dispatch(changeCompose(text));
    },
    [dispatch, status, system],
  );

  if (!card || card.players === undefined) return null;

  return <ContentCardView card={card} onAction={handleAction} sessionLink />;
};
