// 커뮤니티 테마의 관리자·환경설정 화면: 드롭다운(<select>)을 펼치면 브라우저 기본 목록 대신
// 사용자 화면 검색창 드롭다운(.search__popout)처럼 생긴 목록을 띄운다.
// 값은 원래 <select> 에 넣고 change 이벤트를 보내니 저장·필터 등은 그대로 동작한다.
// 터치 기기는 기기 기본 선택 화면이 더 편해서 건드리지 않는다.

const POPOUT_CLASS = 'ct-select-popout';

let current: { select: HTMLSelectElement; popout: HTMLElement } | null = null;

const close = (refocus = false) => {
  if (!current) return;
  const { select, popout } = current;
  current = null;
  popout.remove();
  select.removeAttribute('aria-expanded');
  if (refocus) select.focus();
};

const choose = (select: HTMLSelectElement, index: number) => {
  if (select.selectedIndex !== index) {
    select.selectedIndex = index;
    select.dispatchEvent(new Event('input', { bubbles: true }));
    select.dispatchEvent(new Event('change', { bubbles: true }));
  }
  close(true);
};

const items = (popout: HTMLElement) =>
  Array.from(
    popout.querySelectorAll<HTMLElement>(
      '[role="option"]:not([aria-disabled="true"])',
    ),
  );

const moveFocus = (popout: HTMLElement, step: number | 'first' | 'last') => {
  const list = items(popout);
  if (list.length === 0) return;
  const at = list.indexOf(document.activeElement as HTMLElement);
  const next =
    step === 'first'
      ? 0
      : step === 'last'
        ? list.length - 1
        : Math.min(Math.max(at + step, 0), list.length - 1);
  list[next]?.focus();
};

const buildOption = (select: HTMLSelectElement, option: HTMLOptionElement) => {
  const item = document.createElement('div');
  item.className = `${POPOUT_CLASS}__item`;
  item.setAttribute('role', 'option');
  item.tabIndex = -1;
  item.textContent = option.label || option.text;
  if (option.selected) item.setAttribute('aria-selected', 'true');
  if (option.disabled) item.setAttribute('aria-disabled', 'true');

  item.addEventListener('click', () => {
    if (!option.disabled) choose(select, option.index);
  });
  item.addEventListener('mousemove', () => {
    if (!option.disabled && document.activeElement !== item) item.focus();
  });
  return item;
};

const open = (select: HTMLSelectElement) => {
  close();

  const popout = document.createElement('div');
  popout.className = POPOUT_CLASS;
  popout.setAttribute('role', 'listbox');
  const label = select.labels?.[0]?.textContent?.trim();
  if (label) popout.setAttribute('aria-label', label);

  Array.from(select.children).forEach((child) => {
    if (child instanceof HTMLOptGroupElement) {
      const heading = document.createElement('h4');
      heading.textContent = child.label;
      popout.append(heading);
      Array.from(child.children).forEach((option) => {
        if (option instanceof HTMLOptionElement)
          popout.append(buildOption(select, option));
      });
    } else if (child instanceof HTMLOptionElement) {
      popout.append(buildOption(select, child));
    }
  });

  popout.addEventListener('keydown', (event) => {
    switch (event.key) {
      case 'ArrowDown':
        moveFocus(popout, 1);
        break;
      case 'ArrowUp':
        moveFocus(popout, -1);
        break;
      case 'Home':
        moveFocus(popout, 'first');
        break;
      case 'End':
        moveFocus(popout, 'last');
        break;
      case 'Enter':
      case ' ':
        (document.activeElement as HTMLElement | null)?.click();
        break;
      case 'Escape':
      case 'Tab':
        close(true);
        break;
      default:
        return;
    }
    event.preventDefault();
  });

  // 모달(<dialog>) 안의 칸이면 목록도 그 모달 안에 붙인다. body 에 붙이면 모달(맨 위 층) 뒤에 가려진다.
  // 모달 안에서는 화면 기준 고정 위치로 띄운다.
  const dialog = select.closest('dialog');
  (dialog ?? document.body).append(popout);
  if (dialog) popout.style.position = 'fixed';

  // 칸 바로 아래 (아래 공간이 모자라면 위)
  const rect = select.getBoundingClientRect();
  popout.style.minWidth = `${rect.width}px`;
  const below = window.innerHeight - rect.bottom;
  const height = popout.offsetHeight;
  const top =
    below < height + 8 && rect.top > below
      ? rect.top - height - 4
      : rect.bottom + 4;
  popout.style.top = `${dialog ? top : top + window.scrollY}px`;
  popout.style.left = `${dialog ? rect.left : rect.left + window.scrollX}px`;

  current = { select, popout };
  select.setAttribute('aria-expanded', 'true');

  const selected =
    popout.querySelector<HTMLElement>('[aria-selected="true"]') ??
    items(popout)[0];
  selected?.scrollIntoView({ block: 'nearest' });
  selected?.focus({ preventScroll: true });
};

const enhanceable = (target: EventTarget | null): target is HTMLSelectElement =>
  target instanceof HTMLSelectElement &&
  !target.multiple &&
  target.size <= 1 &&
  !target.disabled;

export const setupCommunitySelect = () => {
  if (!document.body.classList.contains('community-theme')) return;
  if (window.matchMedia('(pointer: coarse)').matches) return;

  document.addEventListener('mousedown', (event) => {
    if (current?.popout.contains(event.target as Node)) return;

    if (enhanceable(event.target) && event.button === 0) {
      event.preventDefault();
      if (current?.select === event.target) close(true);
      else {
        event.target.focus();
        open(event.target);
      }
      return;
    }
    close();
  });

  document.addEventListener('keydown', (event) => {
    if (!enhanceable(event.target)) return;
    const opensNative =
      event.key === ' ' ||
      event.key === 'Enter' ||
      event.key === 'F4' ||
      (event.altKey && (event.key === 'ArrowDown' || event.key === 'ArrowUp'));
    if (!opensNative) return;
    event.preventDefault();
    open(event.target);
  });

  window.addEventListener('resize', () => {
    close();
  });
};
