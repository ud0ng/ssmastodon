// 여럿이 하는 컨텐츠가 시작된 뒤 처음 한 번 뜨는 안내 창 (TUTORIAL 1 / n): 목표 · 규칙 · 역할 · 진행 방법을 한 장씩.
// 내용은 컨텐츠 소개(Game::Guide)를 그대로 쓴다. 한 번 보면(또는 건너뛰면) 같은 컨텐츠에서는 다시 안 뜬다 (브라우저에 기억).
import { useCallback, useEffect, useMemo, useState } from 'react';

import { FormattedMessage } from 'react-intl';

import { createPortal } from 'react-dom';

import { apiRequestGet } from 'mastodon/api';

interface Guide {
  name: string;
  summary: string;
  rules_text: { icon?: string; title: string; text: string }[];
  roles: { name?: string; win: string }[];
  steps: string[];
}

interface Page {
  key: string;
  title: React.ReactNode;
  body: React.ReactNode;
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
    const list: Page[] = [];

    if (guide.summary || guide.roles.length > 0) {
      list.push({
        key: 'goal',
        title: <FormattedMessage id='tutorial.goal' defaultMessage='Goal' />,
        body: (
          <>
            {guide.summary && <p className='stage-tutorial__lead'>{guide.summary}</p>}
            {guide.roles.map((role) => (
              <p key={`${role.name ?? ''}${role.win}`}>{role.name ? <strong>{role.name} </strong> : null}{role.win}</p>
            ))}
          </>
        ),
      });
    }

    if (guide.rules_text.length > 0) {
      list.push({
        key: 'rules',
        title: <FormattedMessage id='tutorial.rules' defaultMessage='Rules' />,
        body: (
          <ul className='stage-tutorial__list'>
            {guide.rules_text.map((rule) => (
              <li key={rule.title}><strong>{rule.title}</strong> {rule.text}</li>
            ))}
          </ul>
        ),
      });
    }

    if (guide.steps.length > 0) {
      list.push({
        key: 'how',
        title: <FormattedMessage id='tutorial.how' defaultMessage='How to play' />,
        body: (
          <ol className='stage-tutorial__list'>
            {guide.steps.map((step) => <li key={step}>{step}</li>)}
          </ol>
        ),
      });
    }

    return list;
  }, [guide]);

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
        <h2>{page.title}</h2>
        <div className='stage-tutorial__body'>{page.body}</div>
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
