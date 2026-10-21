// 여럿이 하는 컨텐츠의 목록(허브)·소개 화면 (웹게임 느낌): 전체 화면 어두운 스포트라이트 + 금빛.
//   왼쪽에는 큰 제목과 메뉴, 오른쪽에는 고른 메뉴의 내용. 마스토돈 메뉴는 대기방처럼 왼쪽에 아이콘만 남는다.
//   (styles/mastodon/_game_stage.scss — .game-stage--page)
import { FormattedMessage } from 'react-intl';

import { Link } from 'react-router-dom';

import { createPortal } from 'react-dom';

import { useStageLayout } from './lobby';

export interface StageTab {
  key: string;
  label: React.ReactNode;
  count?: number;
}

// 공통 틀: 스포트라이트 배경 + 위쪽 [← 돌아가기]
export const StageFrame: React.FC<{ back: string; label: string; children: React.ReactNode }> = ({ back, label, children }) => {
  useStageLayout(true);

  return createPortal(
    <div className='game-stage game-stage--page' role='region' aria-label={label}>
      <div className='game-stage__spot' aria-hidden />
      <Link to={back} className='stage-back'>
        <FormattedMessage id='stage.back' defaultMessage='← Back' />
      </Link>
      {children}
    </div>,
    document.body,
  );
};

// 소개 화면: 왼쪽 (CONTENTS / 큰 제목 / 소개 / 전적 / 시작 버튼 / 메뉴) | 오른쪽 내용
export const StageIntro: React.FC<{
  name: string;
  summary: string;
  record?: { win: number; lose: number; draw: number };
  action: React.ReactNode;
  notice?: React.ReactNode;
  tabs: StageTab[];
  tab: string;
  onTab: (key: string) => void;
  children: React.ReactNode;
}> = ({ name, summary, record, action, notice, tabs, tab, onTab, children }) => (
  <StageFrame back='/system/group' label={name}>
    <div className='stage-intro'>
      <aside className='stage-intro__side'>
        <small className='game-stage__eyebrow'><FormattedMessage id='stage.contents' defaultMessage='Contents' /></small>
        <h1>{name}</h1>
        <p className='stage-intro__summary'>{summary}</p>
        {record && (
          <p className='stage-intro__record'>
            <span><strong>{record.win}</strong> <FormattedMessage id='system.record_win' defaultMessage='W' /></span>
            <span><strong>{record.lose}</strong> <FormattedMessage id='system.record_lose' defaultMessage='L' /></span>
            <span><strong>{record.draw}</strong> <FormattedMessage id='system.record_draw' defaultMessage='D' /></span>
          </p>
        )}
        <div className='stage-intro__action'>{action}</div>
        {notice}
        <nav className='stage-menu' aria-label={name}>
          {tabs.map((each) => (
            <button key={each.key} type='button' className={each.key === tab ? 'is-on' : undefined} onClick={() => { onTab(each.key); }}>
              <span>{each.label}</span>
              {each.count ? <em>{each.count}</em> : null}
            </button>
          ))}
        </nav>
      </aside>
      <section className='stage-intro__panel'>{children}</section>
    </div>
  </StageFrame>
);

export interface HubGame {
  key: string;
  name: string;
  summary: string;
  open: number;
  recruiting?: number;
  running?: number;
  mine: boolean;
  enabled?: boolean;
}

// 목록 화면: 컨텐츠마다 카드 하나 (진행 중 판 수 · 내가 하는 중 · 꺼짐 배지)
export const StageHub: React.FC<{ games: HubGame[] }> = ({ games }) => (
  <StageFrame back='/home' label='Events'>
    <div className='stage-hub'>
      <header className='game-stage__head'>
        <small className='game-stage__eyebrow'><FormattedMessage id='stage.contents' defaultMessage='Contents' /></small>
        <h1><FormattedMessage id='stage.hub_title' defaultMessage='Events' /></h1>
        <p><FormattedMessage id='stage.hub_hint' defaultMessage='Special events everyone plays together. You can join when the staff hosts one.' /></p>
      </header>
      <ul className='stage-hub__list'>
        {games.map((game, index) => (
          <li key={game.key}>
            <Link to={`/system/games/${game.key}`} className={['stage-card', game.mine && 'stage-card--mine', (game.recruiting ?? 0) > 0 && 'stage-card--recruiting', game.enabled === false && 'stage-card--off'].filter(Boolean).join(' ')}>
              <span className='stage-card__no'>{String(index + 1).padStart(2, '0')}</span>
              <strong className='stage-card__name'>{game.name}</strong>
              <span className='stage-card__summary'>{game.summary}</span>
              <span className='stage-card__meta'>
                {game.enabled === false && <span className='stage-card__badge'><FormattedMessage id='system.tile.off' defaultMessage='Off (staff only)' /></span>}
                {game.mine && <span className='stage-card__badge stage-card__badge--on'><FormattedMessage id='system.tile.mine' defaultMessage='Playing' /></span>}
                {(game.recruiting ?? 0) > 0 && <span className='stage-card__badge stage-card__badge--recruit'><FormattedMessage id='stage.badge_recruiting' defaultMessage='Recruiting {count}' values={{ count: game.recruiting }} /></span>}
                {(game.running ?? 0) > 0 && <span className='stage-card__badge stage-card__badge--run'><FormattedMessage id='stage.badge_running' defaultMessage='In progress {count}' values={{ count: game.running }} /></span>}
              </span>
            </Link>
          </li>
        ))}
      </ul>
    </div>
  </StageFrame>
);
