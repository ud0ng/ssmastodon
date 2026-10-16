// 컨텐츠 판의 지금 상태 카드 (서버 Game::Card, 시스템 툿마다 GameEvent 에 저장).
// 툿에는 카드를 그리지 않는다 (컨텐츠 툿은 웹 타임라인에서 숨긴다). 게임 화면(features/system)에서 판 전체(ContentCardView).
// 버튼은 서버원 대신 '@시스템 [명령어]' 툿을 올린다 (features/system/board.tsx).
import { FormattedMessage } from 'react-intl';

import { Link } from 'react-router-dom';

import DiamondIcon from '@/material-icons/400-24px/diamond.svg?react';
import { Countdown } from 'mastodon/components/countdown';
import { GameIcon, stripEmoji } from 'mastodon/components/game_icons';
import { Icon } from 'mastodon/components/icon';
import { me } from 'mastodon/initial_state';

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
  // 버튼 줄 (필살기처럼 일반 기술 다음 줄에 둘 때 2)
  row?: number;
}

type Data = Record<string, unknown>;

export interface GameCard {
  session_id?: string;
  kind: string;
  name: string;
  mode: 'event' | null;
  phase: 'pending' | 'active' | 'finished' | 'cancelled';
  turn: number;
  // 최대 라운드(턴) 수 — 방 맨 위에 '1라운드 / 10라운드' (없으면 현재 라운드만)
  max_turns?: number | null;
  deadline_at: string | null;
  players: CardPlayer[];
  data: Data;
  actions: CardAction[];
  live: boolean;
  tournament?: { name: string; round: string; number: number } | null;
  awards?: { house: House | null; amount: number; account_id?: string | null }[];
  rewards?: {
    name: string;
    account_id?: string;
    money: number;
    currency: string;
    items: string[];
    item_list?: { name: string; count: number; image: string | null }[];
  }[];
}

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
        <GameIcon name={index < left ? 'heart-fill' : 'heart'} />
      </span>
    ))}
  </span>
);

// 플레이어 옆에 붙는 한 줄 (점수·체력·시도 수)
const PlayerStat: React.FC<{ card: GameCard; player: CardPlayer }> = ({ card, player }) => {
  const seat = String(player.seat);
  const { data } = card;
  if (card.phase === 'pending') return null;

  switch (card.kind) {
    case 'gobstones':
    case 'quidditch':
    case 'flying':
      return <span className='content-card__score'>{num(bySeat(data.scores)[seat])}</span>;
    case 'duel':
      return <Hearts left={num(bySeat(data.hp)[seat])} full={num(data.max_hp)} />;
    case 'potion': {
      // 아이템 소지 개수: 방어권·재시도권 아이콘 + 남은/처음 (0/1)
      const owned = bySeat(bySeat(data.items)[seat]);
      const max = bySeat(data.item_max);
      return (
        <span className='content-card__items'>
          {(['shield', 'retry'] as const).map((key) => (
            <span key={key} className={num(owned[key]) > 0 ? 'content-card__item' : 'content-card__item content-card__item--empty'}>
              <GameIcon name={key} />
              {num(owned[key])}/{num(max[key])}
            </span>
          ))}
        </span>
      );
    }
    default:
      return null;
  }
};

// 컨텐츠 방 맨 위 (고정, 박스 없음):
//   아바타 | 소속 배지 · 이름          VS          이름 · 소속 배지 | 아바타
//          | 상태 (차례·대기·승리…)   라운드·남은 시간   상태 |
//   끝난 판은 상태 아래에 받은 보상 (재화 · 아이템 그림 ×개수 · 소속 점수) 가벼운 배지
const RoomRewards: React.FC<{ card: GameCard; player: CardPlayer }> = ({ card, player }) => {
  const reward = card.rewards?.find((each) => each.account_id === player.account_id);
  const awards = (card.awards ?? []).filter((award) =>
    award.account_id ? award.account_id === player.account_id : award.house?.name === player.house?.name,
  );
  const items = reward?.item_list ?? reward?.items.map((label) => ({ name: label, count: 1, image: null })) ?? [];
  if (!reward?.money && items.length === 0 && awards.length === 0) return null;

  return (
    <span className='room-head__rewards'>
      {reward && reward.money !== 0 && (
        <span className='room-head__reward'>
          <Icon id='diamond' icon={DiamondIcon} />
          {reward.money} {reward.currency}
        </span>
      )}
      {items.map((item) => (
        <span key={item.name} className='room-head__reward'>
          {item.image && <img src={item.image} alt='' />}
          {item.name}
          {item.count > 1 && <span className='room-head__reward-count'>×{item.count}</span>}
        </span>
      ))}
      {awards.map((award, index) => (
        // eslint-disable-next-line react/no-array-index-key
        <span key={index} className='room-head__reward'>
          <Crest house={award.house} />
          {award.amount >= 0 ? `+${award.amount}` : award.amount}
        </span>
      ))}
    </span>
  );
};

// 곱스톤: 캐릭터 아래에 점수만 ('n점')
const RoomScore: React.FC<{ card: GameCard; player: CardPlayer }> = ({ card, player }) => (
  <span className='room-head__score'>
    <FormattedMessage id='system.game.points_value' defaultMessage='{points} pts' values={{ points: num(bySeat(card.data.scores)[String(player.seat)]) }} />
  </span>
);

const RoomPlayerState: React.FC<{ card: GameCard; player: CardPlayer }> = ({ card, player }) => {
  if (player.result) {
    return (
      <span className={`room-head__state room-head__state--${player.result}`}>
        {player.result === 'win' && <FormattedMessage id='system.result.win' defaultMessage='Win' />}
        {player.result === 'lose' && <FormattedMessage id='system.result.lose' defaultMessage='Loss' />}
        {player.result === 'draw' && <FormattedMessage id='system.result.draw' defaultMessage='Draw' />}
      </span>
    );
  }

  if (card.phase === 'pending') {
    if (card.mode === 'event') return null;
    return (
      <span className={player.accepted ? 'room-head__state' : 'room-head__state room-head__state--wait'}>
        {player.accepted ? (
          <FormattedMessage id='content_card.accepted' defaultMessage='Ready' />
        ) : (
          <FormattedMessage id='content_card.waiting' defaultMessage='Waiting' />
        )}
      </span>
    );
  }

  if (card.phase !== 'active' || card.data.current_seat === undefined || card.data.current_seat === null) return null;

  return card.data.current_seat === player.seat ? (
    <span className='room-head__state room-head__state--turn'>
      <FormattedMessage id='content_card.room_turn' defaultMessage='Their move' />
    </span>
  ) : (
    <span className='room-head__state room-head__state--wait'>
      <FormattedMessage id='content_card.room_wait' defaultMessage='Waiting' />
    </span>
  );
};

const RoomPlayer: React.FC<{ card: GameCard; player: CardPlayer; side: 'left' | 'right' }> = ({ card, player, side }) => {
  const isTurn = card.phase === 'active' && card.data.current_seat === player.seat;
  const done = card.phase === 'finished' || card.phase === 'cancelled';
  return (
    <div
      className={[
        'room-head__player',
        `room-head__player--${side}`,
        isTurn && 'room-head__player--turn',
        player.result && `room-head__player--${player.result}`,
      ].filter(Boolean).join(' ')}
      style={{ '--house-color': player.house?.color || '#6b5b3e' } as React.CSSProperties}
    >
      {player.avatar && <img className='room-head__avatar' src={player.avatar} alt='' />}
      <div className='room-head__who'>
        {/* 1줄: 소속 배지(문장만) | 이름 | 끝난 판이면 결과 */}
        <span className='room-head__name-line'>
          {player.house && (
            <span className='room-head__house' title={player.house.name}>
              <Crest house={player.house} />
            </span>
          )}
          <span className='room-head__name'>{player.name}</span>
          {done && player.result && <RoomPlayerState card={card} player={player} />}
        </span>
        {/* 2줄: 상태 · 점수, 끝난 판이면 받은 보상 */}
        {done ? (
          <>
            {card.kind === 'gobstones' && <span className='room-head__stat'><RoomScore card={card} player={player} /></span>}
            <RoomRewards card={card} player={player} />
          </>
        ) : (
          <span className='room-head__stat'>
            <RoomPlayerState card={card} player={player} />
            {card.kind === 'gobstones' ? <RoomScore card={card} player={player} /> : <PlayerStat card={card} player={player} />}
          </span>
        )}
      </div>
    </div>
  );
};

// VS 아래: 라운드 (끝난 판은 끝난 라운드), 남은 시간
const RoomMiddle: React.FC<{ card: GameCard }> = ({ card }) => (
  <div className='room-head__middle'>
    <span className='room-head__vs'>VS</span>
    {card.turn > 0 && (card.phase === 'active' || card.phase === 'finished') ? (
      <span className={card.phase === 'finished' ? 'room-head__phase room-head__phase--done' : 'room-head__phase'}>
        {card.phase === 'finished' ? (
          <FormattedMessage id='content_card.round_ended' defaultMessage='Ended in round {turn}' values={{ turn: card.turn }} />
        ) : (
          card.max_turns ? (
            <FormattedMessage id='content_card.round_of' defaultMessage='Round {turn} / {max}' values={{ turn: card.turn, max: card.max_turns }} />
          ) : (
            <FormattedMessage id='content_card.round' defaultMessage='Round {turn}' values={{ turn: card.turn }} />
          )
        )}
      </span>
    ) : (
      <span className='room-head__phase'><PhaseBadge card={card} /></span>
    )}
    {card.live && card.deadline_at && <Countdown until={card.deadline_at} className='room-head__time' />}
  </div>
);

const RoomHead: React.FC<{ card: GameCard }> = ({ card }) => {
  // 내 메시지가 오른쪽에 붙으니 내 캐릭터도 오른쪽에 둔다 (여럿이면 맨 뒤)
  const ordered = [...card.players].sort((a, b) => Number(a.account_id === me) - Number(b.account_id === me));
  if (ordered.length === 2) {
    const [left, right] = ordered as [CardPlayer, CardPlayer];
    return (
      <div className='room-head'>
        <RoomPlayer card={card} player={left} side='left' />
        <RoomMiddle card={card} />
        <RoomPlayer card={card} player={right} side='right' />
      </div>
    );
  }

  return (
    <div className='room-head room-head--many'>
      <RoomMiddle card={card} />
      <div className='room-head__many'>
        {ordered.map((player) => <RoomPlayer key={player.seat} card={card} player={player} side='left' />)}
      </div>
    </div>
  );
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
                {card.phase === 'pending' && card.mode !== 'event' && (
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
// room: 컨텐츠 방 맨 위 (글자 기록 줄은 줄이고, 점수는 캐릭터 아래에)
const Board: React.FC<{ card: GameCard; room?: boolean }> = ({ card, room = false }) => {
  const { data } = card;
  // 신청·모집 중에는 아직 판이 없다
  if (card.phase === 'pending' && card.kind !== 'secret_chamber') return null;
  const names = Object.fromEntries(card.players.map((player) => [String(player.seat), player.name]));

  switch (card.kind) {
    case 'jellybean': {
      const total = num(data.total);
      const remaining = num(data.remaining);
      // 먹은 순서대로 누가 먹었는지 (예전 판에는 없다 → 먹은 칸만 비운다)
      const eaten = Array.isArray(data.eaten) ? (data.eaten as { seat: number; worst: boolean; flavor?: string }[]) : [];
      const bySeatPlayer = Object.fromEntries(card.players.map((player) => [String(player.seat), player]));
      return (
        <div className='content-card__board'>
          <div className='content-card__beans' aria-label={`${remaining}/${total}`}>
            {Array.from({ length: total }, (_, index) => {
              const log = eaten[index];
              const done = index < total - remaining;
              const eater = log ? bySeatPlayer[String(log.seat)] : undefined;
              return (
                <span
                  key={index}
                  className={[
                    'content-card__bean',
                    done && 'content-card__bean--eaten',
                    log?.worst && 'content-card__bean--worst',
                  ].filter(Boolean).join(' ')}
                  style={{ '--bean-hue': `${(index * 47) % 360}`, '--house-color': eater?.house?.color || '#6b5b3e' } as React.CSSProperties}
                  data-tip={log ? [eater?.name, log.flavor].filter(Boolean).join(' · ') : undefined}
                >
                  {eater?.avatar && <img className='content-card__bean-seal' src={eater.avatar} alt={eater.name} />}
                  {log?.worst && <span className='content-card__bean-poop' aria-label='worst'>💩</span>}
                </span>
              );
            })}
          </div>
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
          {!room && (
            <div className='content-card__line'>
              <FormattedMessage id='content_card.throws' defaultMessage='{throws}/{total} throws' values={{ throws, total }} />
            </div>
          )}
          {!room && last && (
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

    case 'flying': {
      const round = num(data.round);
      const rounds = num(data.rounds);
      const routes = Array.isArray(data.routes) ? (data.routes as string[]) : [];
      const chosen = Array.isArray(data.chosen) ? data.chosen.length : 0;
      const last = bySeat(bySeat(data.last_round).choices);
      return (
        <div className='content-card__board'>
          <div className='content-card__progress'>
            <span style={{ width: `${rounds ? (Math.min(round, rounds) / rounds) * 100 : 0}%` }} />
          </div>
          <div className='content-card__line'>
            <FormattedMessage id='content_card.flying_round' defaultMessage='Round {round}/{rounds} · {chosen}/{total} chosen' values={{ round, rounds, chosen, total: card.players.length }} />
          </div>
          {card.phase === 'active' && routes.length > 0 && (
            <div className='content-card__chips'>
              {routes.map((route, index) => (
                <span key={route} className='content-card__chip'>{index + 1}. {route}</span>
              ))}
            </div>
          )}
          {Object.keys(last).length > 0 && (
            <div className='content-card__chips'>
              {Object.entries(last).map(([seat, route]) => (
                <span key={seat} className='content-card__chip'>{names[seat]} → {String(route)}</span>
              ))}
            </div>
          )}
        </div>
      );
    }

    case 'duel':
    case 'quidditch': {
      // 결투 방 맨 위는 HP 하트만 (고른 주문·최대 턴 줄 없음)
      if (room && card.kind === 'duel') return null;
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
      // 약 이름·재료 이름은 보여 주지 않는다: 재료 개수 배지만 (끝나면 정답 번호). 이번 라운드 시도 결과도 넣지 않는다.
      const numbers = Array.isArray(data.answer_numbers) ? (data.answer_numbers as number[]) : null;
      return (
        <div className='content-card__board content-card__board--potion'>
          <span className='content-card__potion-badge'>
            <FormattedMessage id='content_card.potion_size' defaultMessage='{size} ingredients' values={{ size: num(data.answer_size) }} />
          </span>
          {numbers && (
            <span className='content-card__potion-answer'>
              <FormattedMessage id='content_card.answer_label' defaultMessage='Answer' />
              {numbers.map((number, index) => <kbd key={index} className='command-badge'>{number}</kbd>)}
            </span>
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
            {phase === 'day' && <GameIcon name='sun' />}
            {phase === 'day' && <FormattedMessage id='content_card.chamber.day' defaultMessage='Day {day}' values={{ day: num(data.day) }} />}
            {phase === 'night' && <GameIcon name='moon' />}
            {phase === 'night' && <FormattedMessage id='content_card.chamber.night' defaultMessage='Night {day}' values={{ day: num(data.day) }} />}
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
              <span key={target.room} className={target.visited ? 'content-card__chip content-card__chip--good' : 'content-card__chip'}><GameIcon name={target.visited ? 'check' : 'star'} /> {target.room}</span>
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
              const marks = [num(flags.stunned) > 0 && 'stun', flags.hostile && 'sword', flags.boost && 'hands', num(flags.lumos) > 0 && 'bulb'].filter(Boolean) as string[];
              return marks.length > 0 ? (
                <span key={player.seat} className='content-card__chip'>
                  {player.name} {marks.map((mark) => <GameIcon key={mark} name={mark} />)}
                </span>
              ) : null;
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
      return null;
  }
};

const PhaseBadge: React.FC<{ card: GameCard }> = ({ card }) => {
  switch (card.phase) {
    case 'pending':
      return card.mode === 'event' ? (
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

// 지금 내가 누를 수 있는 버튼 (내 자리 버튼, 참가하지 않았으면 '다른 사람' 버튼)
export const myActions = (card: GameCard): CardAction[] => {
  const mySeat = card.players.find((player) => player.account_id === me)?.seat;
  return (card.live ? card.actions : []).filter((action) =>
    action.seats === 'others' ? mySeat === undefined && !!me : mySeat !== undefined && action.seats.includes(mySeat),
  );
};

// 카드 한 장 (진행 화면에서도 쓴다). onAction 이 없으면 버튼을 그리지 않는다.
export const ContentCardView: React.FC<{
  card: GameCard;
  onAction?: (action: CardAction) => void;
  sessionLink?: boolean;
  // room: 컨텐츠 방 맨 위에 고정하는 현재 상태 (아바타 | 소속 | 이름 vs …, 가운데 판). 버튼은 방 아래 입력창에서
  variant?: 'room';
}> = ({ card, onAction, sessionLink, variant }) => {
  const mySeat = card.players.find((player) => player.account_id === me)?.seat;
  const room = variant === 'room';
  const available = onAction && !room ? myActions(card) : [];

  return (
    <div className={`content-card content-card--${card.phase} content-card--${card.kind}${room ? ' content-card--room' : ''}`}>
      {room && card.kind !== 'secret_chamber' && <RoomHead card={card} />}
      <div className='content-card__head' hidden={room && card.kind !== 'secret_chamber'}>
        <span className='content-card__name'>{card.name}</span>
        {!['weekly', 'term', 'tournament'].includes(card.kind) && <span className='content-card__phase'><PhaseBadge card={card} /></span>}
        {card.tournament && (
          <span className='content-card__tournament'>
            <GameIcon name='tournament' /> {card.tournament.name} · {card.tournament.round} {card.tournament.number}
          </span>
        )}
        {card.live && card.deadline_at && (
          <span className='content-card__deadline'>
            <GameIcon name='hourglass' /> <Countdown until={card.deadline_at} />
          </span>
        )}
        {sessionLink && card.session_id && (
          <Link className='content-card__open' to={`/system/sessions/${card.session_id}`}>
            <FormattedMessage id='content_card.open' defaultMessage='Whole game' />
          </Link>
        )}
      </div>

      {!room && card.kind !== 'secret_chamber' && <Players card={card} />}
      <Board card={card} room={room} />

      {!room && card.awards && card.awards.length > 0 && (
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

      {!room && card.rewards && card.rewards.length > 0 && (
        <ul className='content-card__rewards'>
          {card.rewards.map((reward, index) => (
            // eslint-disable-next-line react/no-array-index-key
            <li key={index}>
              <span className='content-card__reward-name'>{reward.name}</span>
              {reward.money > 0 && <span className='content-card__reward-money'><GameIcon name='coin' /> {reward.money} {reward.currency}</span>}
              {reward.items.map((item) => (
                <span key={item} className='content-card__reward-item'><GameIcon name='gift' /> {item}</span>
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
      {!room && card.live && mySeat !== undefined && card.kind === 'potion' && card.phase === 'active' && (
        <div className='content-card__hint'>
          <FormattedMessage id='content_card.potion_hint' defaultMessage='Send [{brew}] with your ingredients by DM, e.g. [{brew}] 1 5 3' values={{ brew: String(card.data.brew ?? '') }} />
        </div>
      )}
    </div>
  );
};
