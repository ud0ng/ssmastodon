// 표 안의 드롭다운(<select data-inline-save="주소" data-kind="…">): 고르는 즉시 그 자리에서 저장한다 (캐릭터 명단의 소속·진영).
// 저장에 실패하면 원래 값으로 되돌리고 알린다. 드롭다운 모양은 community_select.ts 가 그린다.

const csrfToken = () => document.querySelector<HTMLMetaElement>('meta[name="csrf-token"]')?.content ?? '';

const save = async (select: HTMLSelectElement, previous: string) => {
  const body = new FormData();
  body.append('kind', select.dataset.kind ?? '');
  body.append('value', select.value);

  select.disabled = true;
  try {
    const response = await fetch(select.dataset.inlineSave ?? '', {
      method: 'PATCH',
      body,
      headers: { 'X-CSRF-Token': csrfToken(), Accept: 'application/json' },
      credentials: 'same-origin',
    });
    if (!response.ok) throw new Error(String(response.status));

    select.dataset.saved = select.value;
    select.classList.add('game-inline-select--saved');
    window.setTimeout(() => { select.classList.remove('game-inline-select--saved'); }, 1200);
  } catch {
    select.value = previous;
    select.classList.add('game-inline-select--failed');
    window.setTimeout(() => { select.classList.remove('game-inline-select--failed'); }, 1800);
  } finally {
    select.disabled = false;
  }
};

export const setupInlineSelects = () => {
  document.querySelectorAll<HTMLSelectElement>('select[data-inline-save]').forEach((select) => {
    select.dataset.saved = select.value;
    select.addEventListener('change', () => {
      void save(select, select.dataset.saved ?? '');
    });
  });
};
