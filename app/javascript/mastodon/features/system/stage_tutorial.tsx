// 여럿이 하는 컨텐츠가 시작된 뒤 처음 한 번 뜨는 안내 창 (TUTORIAL 1 / n): 게임 방법만 한 단계씩, 실제 화면의 버튼·칸을 그대로 넣어 보여 준다.
// 목표·규칙은 이벤트 정보(룰 탭)에 있으니 여기에는 넣지 않는다. 한 번 보면(또는 건너뛰면) 같은 컨텐츠에서는 다시 안 뜬다 (브라우저에 기억).
import { useCallback, useEffect, useMemo, useState } from 'react';

import { FormattedMessage } from 'react-intl';

import { createPortal } from 'react-dom';

import { apiRequestGet } from 'mastodon/api';

import { Broom, HpBadge } from './flying';

interface Guide {
  name: string;
  steps: string[];
  durability?: number;
}

interface Page {
  key: string;
  text: string;
  demo: React.ReactNode;
}

const seenKey = (kind: string) => `ssm:stage-tutorial:${kind}`;

const wasSeen = (kind: string) => {
  try {
    return window.localStorage.getItem(seenKey(kind)) === '1';
  } catch {
    return false;
  }
};

const markSeen = (kind: string) => {
  try {
    window.localStorage.setItem(seenKey(kind), '1');
  } catch {
    // 저장이 막힌 브라우저에서는 이번 방문 동안만
  }
};

// 단계마다 실제 화면의 모양을 그대로 보여 준다 (누를 수는 없다)
const NOOP = () => undefined;

const DEMOS: Record<string, ((guide: Guide) => React.ReactNode)[]> = {
  flying: [
    () => (
      <button type='button' className='game-stage__join' tabIndex={-1} onClick={NOOP}>
        <FormattedMessage id='lobby.accept' defaultMessage='Accept' />
      </button>
    ),
    () => (
      <button type='button' className='game-stage__button' tabIndex={-1} onClick={NOOP}>
        <FormattedMessage id='lobby.ready' defaultMessage='Ready' />
      </button>
    ),
    () => (
      <div className='stage-tutorial__lanes'>
        {[1, 2, 3].map((lane) => (
          <span key={lane} className={['fl-lane', 'is-open', lane === 2 && 'is-ring'].filter(Boolean).join(' ')} style={{ left: `${6 + ((lane - 1) * 32)}%`, width: '28%', '--fl-i': lane } as React.CSSProperties}>
            <b>{lane}</b>
            {lane === 2 && <em className='fl-lane__tag'><FormattedMessage id='flying.ring' defaultMessage='Golden ring +1' /></em>}
          </span>
        ))}
      </div>
    ),
    (guide) => (
      <div className='stage-tutorial__token'>
        <Broom hp={guide.durability ?? 2} base={guide.durability ?? 2} wobble={false} size={64} />
        <HpBadge hp={Math.max((guide.durability ?? 2) - 1, 0)} base={guide.durability ?? 2} gained={false} />
      </div>
    ),
  ],
};

export const StageTutorial: React.FC<{ kind: string }> = ({ kind }) => {
  const [guide, setGuide] = useState<Guide | null>(null);
  const [index, setIndex] = useState(0);
  const [closed, setClosed] = useState(() => wasSeen(kind));

  useEffect(() => {
    if (closed) return;
    apiRequestGet<Guide>(`v1/system/games/${kind}`)
      .then(setGuide)
      .catch(() => {
        setClosed(true);
      });
  }, [kind, closed]);

  const pages = useMemo<Page[]>(() => {
    if (!guide) return [];
    const demos = DEMOS[kind] ?? [];
    return guide.steps.map((step, index) => ({ key: `step-${index}`, text: step, demo: demos[index]?.(guide) ?? null }));
  }, [guide, kind]);

  const close = useCallback(() => {
    markSeen(kind);
    setClosed(true);
  }, [kind]);

  if (closed || !guide || pages.length === 0) return null;

  const page = pages[Math.min(index, pages.length - 1)];
  if (!page) return null;
  const last = index >= pages.length - 1;

  return createPortal(
    <div className='stage-tutorial' role='dialog' aria-label={guide.name}>
      <div className='stage-tutorial__card'>
        <div className='stage-tutorial__top'>
          <small><FormattedMessage id='tutorial.label' defaultMessage='Tutorial' /></small>
          <small>{index + 1} / {pages.length}</small>
        </div>
        <h2><FormattedMessage id='tutorial.how' defaultMessage='How to play' /></h2>
        <div className='stage-tutorial__body'>
          <p className='stage-tutorial__step'><b>{index + 1}</b><span>{page.text}</span></p>
          {page.demo && <div className='stage-tutorial__demo' aria-hidden>{page.demo}</div>}
        </div>
        <div className='stage-tutorial__bottom'>
          <span className='stage-tutorial__dots' aria-hidden>
            {pages.map((each, position) => <i key={each.key} className={position === index ? 'is-on' : undefined} />)}
          </span>
          <span className='stage-tutorial__buttons'>
            {!last && (
              <button type='button' className='stage-tutorial__skip' onClick={close}>
                <FormattedMessage id='tutorial.skip' defaultMessage='Skip' />
              </button>
            )}
            <button type='button' className='stage-tutorial__next' onClick={() => { if (last) close(); else setIndex(index + 1); }}>
              {last ? <FormattedMessage id='tutorial.start' defaultMessage='Start' /> : <FormattedMessage id='tutorial.next' defaultMessage='Next' />}
            </button>
          </span>
        </div>
      </div>
    </div>,
    document.body,
  );
};
