// 시스템 계정의 컨텐츠 툿을 PC 웹에서 카드로 보여 준다 (툿의 game_card, 서버 Game::Card).
// 카드 아래에는 툿 본문(진행 문구)이 그대로 이어진다. 앱은 game_card 를 모르니 지금처럼 텍스트로 보인다.
//
// 아직 진행 중인 판의 가장 최근 툿(live)이고 내 차례면 행동 버튼이 나온다.
// 누르면 '@시스템 [명령어]' 를 쓰는 창이 열린다 (비밀 선택은 DM 으로). 게시는 직접 누른다.
import { useCallback } from 'react';

import { FormattedMessage } from 'react-intl';

import type { Map as ImmutableMap } from 'immutable';

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

interface CardAction {
  label: string;
  command: string;
  seats: number[] | 'others';
  dm: boolean;
  style: 'primary' | 'secondary';
}

type Data = Record<string, unknown>;

export interface GameCard {
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
  if (card.phase === 'pending' && !card.lesson) return null;
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

export const ContentCard: React.FC<{
  status: ImmutableMap<string, unknown>;
}> = ({ status }) => {
  const dispatch = useAppDispatch();
  const raw = status.get('game_card') as { toJS?: () => GameCard } | undefined;
  const card = raw?.toJS ? raw.toJS() : (raw as unknown as GameCard | undefined);
  const system = status.get('account') as ImmutableMap<string, unknown> | undefined;

  const mySeat = card?.players.find((player) => player.account_id === me)?.seat;
  const available = (card?.live ? card.actions : []).filter((action) =>
    action.seats === 'others' ? mySeat === undefined && !!me : mySeat !== undefined && action.seats.includes(mySeat),
  );

  const handleAction = useCallback(
    (action: CardAction) => {
      if (!system) return;
      const text = `@${String(system.get('acct'))} [${action.command}]`;
      if (action.dm) dispatch(directCompose(system));
      else dispatch(replyCompose(status));
      dispatch(changeCompose(text));
    },
    [dispatch, status, system],
  );

  if (!card || card.players === undefined) return null;

  return (
    <div className={`content-card content-card--${card.phase} content-card--${card.kind}`}>
      <div className='content-card__head'>
        <span className='content-card__icon' aria-hidden>{ICONS[card.kind] ?? '📜'}</span>
        <span className='content-card__name'>{card.name}</span>
        <span className='content-card__phase'><PhaseBadge card={card} /></span>
        {card.live && card.deadline_at && (
          <span className='content-card__deadline'>
            <FormattedMessage
              id='content_card.deadline'
              defaultMessage='⏳ {time}'
              values={{ time: <RelativeTimestamp timestamp={card.deadline_at} futureDate /> }}
            />
          </span>
        )}
      </div>

      <Players card={card} />
      <Board card={card} />

      {available.length > 0 && (
        <div className='content-card__actions'>
          {available.map((action) => (
            <button
              key={action.command}
              type='button'
              className={action.style === 'primary' ? 'content-card__action' : 'content-card__action content-card__action--secondary'}
              onClick={() => { handleAction(action); }}
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
