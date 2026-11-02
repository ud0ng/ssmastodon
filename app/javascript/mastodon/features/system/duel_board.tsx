// 1:1 컨텐츠 방(웹)의 기록판: 두 사람의 라운드 기록을 나란히 쌓아 보여 준다 (숫자야구 기록지처럼).
//   서버: Game::Kinds::Base#board_for (각 컨텐츠가 채운다, GET /api/v1/system/sessions/:id/view)
//   한 줄 = 라운드 번호 · 칸(고른 것) · 칩(결과). 맨 아래는 사람마다 요약(정답·HP·점수 등).
//   남이 몰래 고른 것은 서버가 넣지 않는다.

import { useEffect, useState } from 'react';

import { apiRequestGet } from 'mastodon/api';
import type { GameCard } from 'mastodon/components/content_card';
import { orderPlayers } from 'mastodon/components/content_card';

// 색: good(초록) warn(주황) bad(빨강) dim(흐림) zero(빈 칩) note(글자만)
type Tone = 'good' | 'warn' | 'bad' | 'dim' | 'zero' | 'note' | null;
type Piece = [string, Tone];

interface BoardRow {
  round: number;
  cells: Piece[];
  chips: Piece[];
}

interface BoardColumn {
  rows: BoardRow[];
  pending: string | null;
  summary: { label: string; value: string; note: string | null; win: boolean };
}

interface BoardView {
  board: true;
  mine: string | null;
  legend?: [string, string][];
  key?: string;
  columns: Record<string, BoardColumn | undefined>;
}

// 서버가 기록판을 주는 컨텐츠 (session.tsx 가 PC 에서 왼쪽에 판을 둔다)
export const BOARD_KINDS = ['potion', 'broom_race', 'marbles', 'duel', 'gobstones', 'jellybean'];

const toneClass = (base: string, tone: Tone) => (tone ? `${base} ${base}--${tone}` : base);

const Row: React.FC<{ row: BoardRow }> = ({ row }) => (
  <div className='duel-board__row'>
    <span className='duel-board__round'>{row.round}</span>
    <span className='duel-board__cells'>
      {row.cells.map(([text, tone], index) => (
        <span key={index} className={toneClass(text.length <= 3 ? 'duel-board__cell duel-board__cell--big' : 'duel-board__cell', tone)}>{text}</span>
      ))}
    </span>
    {row.chips.map(([text, tone], index) => (
      <span key={index} className={toneClass('duel-board__chip', tone)}>{text}</span>
    ))}
  </div>
);

const Column: React.FC<{ column: BoardColumn; mine: boolean }> = ({ column, mine }) => (
  <div className={mine ? 'duel-board__column duel-board__column--mine' : 'duel-board__column'}>
    {column.rows.map((row, index) => <Row key={index} row={row} />)}

    {column.pending && (
      <div className='duel-board__row duel-board__row--pending'>
        <span className='duel-board__pending'>{column.pending}</span>
      </div>
    )}

    <div className={column.summary.win ? 'duel-board__summary duel-board__summary--win' : 'duel-board__summary'}>
      <span className='duel-board__summary-label'>{column.summary.label}</span>
      <span className='duel-board__summary-value'>{column.summary.value}</span>
      {column.summary.note && <span className='duel-board__summary-note'>{column.summary.note}</span>}
    </div>
  </div>
);

export const DuelBoard: React.FC<{ sessionId: string; card: GameCard; tick: number }> = ({ sessionId, card, tick }) => {
  const [view, setView] = useState<BoardView | null>(null);

  useEffect(() => {
    apiRequestGet<{ view: BoardView | null }>(`v1/system/sessions/${sessionId}/view`)
      .then((response) => {
        setView(response.view?.board ? response.view : null);
        return response;
      })
      .catch(() => {
        // 구경하는 사람은 판을 못 본다 (툿 기록만)
        setView(null);
      });
  }, [sessionId, tick]);

  if (!view) return null;

  // 방 맨 위 머리글과 같은 순서 (나는 오른쪽)
  const players = orderPlayers(card.players);

  return (
    <div className='duel-board'>
      {view.legend && view.legend.length > 0 && (
        <div className='duel-board__legend'>
          {view.legend.map(([mark, name], index) => (
            <span key={index} className='duel-board__legend-item'>
              <b>{mark}</b>
              {name}
            </span>
          ))}
        </div>
      )}

      <div className='duel-board__columns' style={{ gridTemplateColumns: `repeat(${players.length}, minmax(0, 1fr))` }}>
        {players.map((player) => {
          const column = view.columns[String(player.seat)];
          return column ? <Column key={player.seat} column={column} mine={String(player.seat) === view.mine} /> : <div key={player.seat} />;
        })}
      </div>

      {view.key && <p className='duel-board__key'>{view.key}</p>}
    </div>
  );
};
