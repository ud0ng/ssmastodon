// 툿 본문의 [대괄호] (봇 명령어 등)와 (소괄호) 대사를 span 으로 감싼다.
// 색·크기는 커뮤니티 테마(서버 설정 > 디자인)가 정한다. 다른 테마에서는 모양이 바뀌지 않는다.
//
//   <span class="dialogue dialogue--bracket">[주사위]</span>
//   <span class="dialogue dialogue--paren">(작게 말한다)</span>
//
// 문단(<p>) 안에서 괄호가 멘션 링크 등을 사이에 두고 이어져도 한 덩어리로 묶는다.
// 줄바꿈이나 문단 끝까지 닫히지 않은 괄호는 묶지 않는다.

type DialogueType = 'bracket' | 'paren';

const OPENERS: Record<string, DialogueType> = {
  '[': 'bracket',
  '［': 'bracket',
  '(': 'paren',
  '（': 'paren',
};

const CLOSERS: Record<DialogueType, string[]> = {
  bracket: [']', '］'],
  paren: [')', '）'],
};

const SKIP_TAGS = new Set(['CODE', 'PRE', 'SCRIPT', 'STYLE']);
// 감싼 뒤의 내용. 그대로면 다시 감싸지 않는다 (React 가 새 내용을 넣으면 달라진다)
const decorated = new WeakMap<HTMLElement, string>();

const unwrap = (span: HTMLElement) => {
  const parent = span.parentNode;
  if (!parent) return;
  while (span.firstChild) parent.insertBefore(span.firstChild, span);
  span.remove();
};

const decorateBlock = (block: Element) => {
  let wrapper: HTMLElement | null = null;
  let type: DialogueType | null = null;
  let depth = 0;

  const close = (keep: boolean) => {
    if (wrapper && !keep) unwrap(wrapper);
    wrapper = null;
    type = null;
    depth = 0;
  };

  Array.from(block.childNodes).forEach((node) => {
    if (node.nodeType === Node.TEXT_NODE) {
      const text = node.textContent ?? '';
      const parent = node.parentNode;
      if (!parent) return;

      let outside = '';
      const fragment = document.createDocumentFragment();

      for (const char of text) {
        if (!wrapper) {
          const opened = OPENERS[char];
          if (opened) {
            if (outside) fragment.append(outside);
            outside = '';
            wrapper = document.createElement('span');
            wrapper.className = `dialogue dialogue--${opened}`;
            wrapper.append(char);
            fragment.append(wrapper);
            type = opened;
            depth = 1;
          } else {
            outside += char;
          }
          continue;
        }

        wrapper.append(char);
        if (type && OPENERS[char] === type) depth += 1;
        else if (type && CLOSERS[type].includes(char)) {
          depth -= 1;
          if (depth === 0) close(true);
        }
      }

      if (outside) fragment.append(outside);
      parent.replaceChild(fragment, node);
      return;
    }

    if (!(node instanceof HTMLElement)) return;

    // 줄바꿈에서 끊긴 괄호는 묶지 않는다
    if (node.tagName === 'BR') {
      close(false);
      return;
    }

    // 링크·멘션·강조 등은 통째로 괄호 안에 넣는다
    if (wrapper && !SKIP_TAGS.has(node.tagName)) {
      wrapper.append(node);
    }
  });

  // 문단 끝까지 닫히지 않았으면 원래대로
  close(false);
};

export const decorateDialogue = (root: HTMLElement | null) => {
  if (!root || decorated.get(root) === root.innerHTML) return;

  const blocks = root.querySelectorAll('p');
  if (blocks.length > 0) blocks.forEach(decorateBlock);
  else decorateBlock(root);

  decorated.set(root, root.innerHTML);
};
