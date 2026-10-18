// 커뮤니티 테마의 관리자 화면: 글자 칸(<input list="…">)을 누르면 사용자 화면 검색창 드롭다운(.search__popout)처럼 생긴 목록을 띄운다.
// 목록은 칸에 연결된 <datalist> 의 항목 (value 가 칸에 들어가는 값, label 은 오른쪽에 흐리게 보이는 보조 글자).
// 글자를 쓰면 이름·보조 글자 어디에 들어 있든 좁혀지고, 고르면 칸에 값이 들어간다. 모양은 community_select.ts 의 드롭다운(.ct-select-popout)과 같다.
// 터치 기기와 커뮤니티 테마가 아닐 때는 브라우저 기본 목록(datalist)을 그대로 둔다.

const POPOUT_CLASS = 'ct-select-popout';
const MAX_ITEMS = 60;

interface Choice { value: string; label: string }

const choicesOf = new WeakMap<HTMLInputElement, Choice[]>();
let current: { input: HTMLInputElement; popout: HTMLElement } | null = null;

const close = () => {
  if (!current) return;
  current.popout.remove();
  current.input.removeAttribute('aria-expanded');
  current = null;
};

const items = (popout: HTMLElement) => Array.from(popout.querySelectorAll<HTMLElement>('[role="option"]'));

const choose = (input: HTMLInputElement, value: string) => {
  input.value = value;
  input.dispatchEvent(new Event('input', { bubbles: true }));
  input.dispatchEvent(new Event('change', { bubbles: true }));
  close();
  input.focus();
};

const buildItem = (input: HTMLInputElement, choice: Choice) => {
  const item = document.createElement('div');
  item.className = `${POPOUT_CLASS}__item`;
  item.setAttribute('role', 'option');
  item.tabIndex = -1;
  item.textContent = choice.value;
  if (choice.label) {
    const sub = document.createElement('span');
    sub.className = `${POPOUT_CLASS}__sub`;
    sub.textContent = choice.label;
    item.append(' ', sub);
  }
  item.addEventListener('mousedown', (event) => {
    event.preventDefault();
    choose(input, choice.value);
  });
  item.addEventListener('mousemove', () => {
    if (document.activeElement !== item) item.focus({ preventScroll: true });
  });
  return item;
};

const matches = (choice: Choice, query: string) => {
  if (!query) return true;
  const needle = query.toLowerCase();
  return choice.value.toLowerCase().includes(needle) || choice.label.toLowerCase().includes(needle);
};

// 칸 바로 아래 (아래 공간이 모자라면 위)
const place = (input: HTMLInputElement, popout: HTMLElement) => {
  const rect = input.getBoundingClientRect();
  popout.style.minWidth = `${rect.width}px`;
  const below = window.innerHeight - rect.bottom;
  const height = popout.offsetHeight;
  const top = below < height + 8 && rect.top > below ? rect.top - height - 4 : rect.bottom + 4;
  popout.style.top = `${top + window.scrollY}px`;
  popout.style.left = `${rect.left + window.scrollX}px`;
};

const show = (input: HTMLInputElement) => {
  const all = choicesOf.get(input) ?? [];
  const shown = all.filter((choice) => matches(choice, input.value.trim())).slice(0, MAX_ITEMS);
  close();
  if (shown.length === 0) return;

  const popout = document.createElement('div');
  popout.className = POPOUT_CLASS;
  popout.setAttribute('role', 'listbox');
  shown.forEach((choice) => { popout.append(buildItem(input, choice)); });
  popout.addEventListener('keydown', (event) => {
    const list = items(popout);
    const at = list.indexOf(document.activeElement as HTMLElement);
    if (event.key === 'ArrowDown') list[Math.min(at + 1, list.length - 1)]?.focus();
    else if (event.key === 'ArrowUp') {
      if (at <= 0) input.focus();
      else list[at - 1]?.focus();
    } else if (event.key === 'Enter') (document.activeElement as HTMLElement | null)?.dispatchEvent(new MouseEvent('mousedown', { bubbles: true, cancelable: true }));
    else if (event.key === 'Escape') { close(); input.focus(); }
    else return;
    event.preventDefault();
  });

  document.body.append(popout);
  place(input, popout);
  current = { input, popout };
  input.setAttribute('aria-expanded', 'true');
};

export const setupCommunityCombobox = () => {
  if (!document.body.classList.contains('community-theme')) return;
  if (window.matchMedia('(pointer: coarse)').matches) return;

  document.querySelectorAll<HTMLInputElement>('input[list]').forEach((input) => {
    const list = document.getElementById(input.getAttribute('list') ?? '');
    if (!(list instanceof HTMLDataListElement)) return;

    choicesOf.set(input, Array.from(list.options).map((option) => ({ value: option.value, label: option.label && option.label !== option.value ? option.label : '' })));
    input.removeAttribute('list'); // 기본 목록과 겹치지 않게
    input.setAttribute('role', 'combobox');
    input.setAttribute('aria-autocomplete', 'list');
    input.autocomplete = 'off';

    input.addEventListener('focus', () => { show(input); });
    input.addEventListener('click', () => { show(input); });
    input.addEventListener('input', () => { show(input); });
    input.addEventListener('keydown', (event) => {
      if (event.key === 'ArrowDown') {
        if (!current || current.input !== input) show(input);
        current?.popout.querySelector<HTMLElement>('[role="option"]')?.focus();
        event.preventDefault();
      } else if (event.key === 'Escape') close();
    });
  });

  document.addEventListener('mousedown', (event) => {
    if (!current) return;
    const target = event.target as Node;
    if (current.popout.contains(target) || current.input === target) return;
    close();
  });
  window.addEventListener('resize', close);
};
