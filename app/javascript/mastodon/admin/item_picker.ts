// 아이템 고르기 (admin/ui/_item_picker) 공통 동작: 카드 붙이기·읽기·검색.
// admin.tsx 가 목록에서 고르기·검색을, game_config_editor.ts 가 컨텐츠 승리 아이템 칸의 카드 ↔ 글(아이템|개수|확률) 맞추기를 쓴다.

export interface PickedItem {
  name: string;
  count: number;
  chance: string;
}

const cardsOf = (picker: HTMLElement) =>
  Array.from(picker.querySelectorAll<HTMLElement>('.ui-item-picker__card'));

const nameOf = (card: HTMLElement) => card.querySelector<HTMLInputElement>('input[type="hidden"]')?.value ?? '';

// 카드 하나 붙이기. 이미 있는 아이템이면 개수만 더한다 (merge). 그림은 목록(팝오버)의 같은 아이템에서 가져온다.
export const addItemCard = (picker: HTMLElement, name: string, count = 1, chance = '', merge = true) => {
  const template = picker.querySelector('template');
  const add = picker.querySelector<HTMLDetailsElement>('.ui-item-picker__add');
  if (!template || !add || !name) return;

  const existing = merge ? cardsOf(picker).find((card) => nameOf(card) === name) : undefined;
  if (existing) {
    const field = existing.querySelector<HTMLInputElement>('.ui-item-picker__count');
    if (field) field.value = String((parseInt(field.value, 10) || 0) + count);
    return;
  }

  const card = (template.content.firstElementChild as HTMLElement | null)?.cloneNode(true);
  if (!(card instanceof HTMLElement)) return;

  const option = Array.from(picker.querySelectorAll<HTMLElement>('[data-item-pick]')).find((each) => each.dataset.itemPick === name);
  const thumb = option?.querySelector('.game-item-thumb')?.cloneNode(true);
  if (thumb) card.querySelector('.ui-item-picker__thumb')?.replaceWith(thumb);
  const label = card.querySelector('.game-inventory__name');
  if (label) label.textContent = name;
  const hidden = card.querySelector<HTMLInputElement>('input[type="hidden"]');
  if (hidden) hidden.value = name;
  const countField = card.querySelector<HTMLInputElement>('.ui-item-picker__count');
  if (countField) countField.value = String(count);
  const chanceField = card.querySelector<HTMLInputElement>('.ui-item-picker__chance');
  if (chanceField) chanceField.value = chance;
  add.before(card);
};

export const clearItemCards = (picker: HTMLElement) => {
  cardsOf(picker).forEach((card) => {
    card.remove();
  });
};

export const readItemCards = (picker: HTMLElement): PickedItem[] =>
  cardsOf(picker)
    .map((card) => ({
      name: nameOf(card),
      count: Math.max(parseInt(card.querySelector<HTMLInputElement>('.ui-item-picker__count')?.value ?? '1', 10) || 1, 1),
      chance: card.querySelector<HTMLInputElement>('.ui-item-picker__chance')?.value.trim() ?? '',
    }))
    .filter((item) => item.name);

// 목록 위 검색칸: 이름에 들어 있는 글자로 거른다
export const filterItemOptions = (input: HTMLInputElement) => {
  const query = input.value.trim().toLowerCase();
  const popover = input.closest('.ui-popover');
  let shown = 0;
  popover?.querySelectorAll<HTMLElement>('.ui-popover__option').forEach((option) => {
    const match = !query || (option.dataset.itemPick ?? option.textContent ?? '').toLowerCase().includes(query);
    option.hidden = !match;
    if (match) shown += 1;
  });
  const empty = popover?.querySelector<HTMLElement>('.ui-popover__empty');
  if (empty) empty.hidden = shown > 0;
};
