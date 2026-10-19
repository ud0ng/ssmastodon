// 상점 아이템 모달: 이미지 카드(admin/ui/_image_picker)와 효과 상자(admin/game_shops/_effect_box)
//   이미지: 카드를 누르면 파일 고르기 → 불러오는 동안 빙글 → 이미지 표시, 오른쪽 위 [x] 로 지우기 (remove_image=1)
//   효과: [효과 추가] 로 템플릿을 복사, 휴지통으로 지우기, 사용대상을 고르면 그 묶음 칸만 보이고 켜진다 (안 보이는 칸은 disabled 라 보내지 않음)
//         재화 종류가 아이템이면 아이템 고르기, 효과 종류(캐릭터/소속)에 맞는 효과만 고르기에 보인다. 보낼 때 상자 번호를 0부터 다시 매긴다.

const show = (element: HTMLElement | null, visible: boolean) => {
  if (element) element.hidden = !visible;
};

export const setupImagePickers = () => {
  document.addEventListener('change', (event) => {
    const input = event.target;
    if (!(input instanceof HTMLInputElement) || !input.classList.contains('ui-image-picker__input')) return;

    const picker = input.closest<HTMLElement>('[data-image-picker]');
    const file = input.files?.[0];
    if (!picker || !file) return;

    const image = picker.querySelector<HTMLImageElement>('.ui-image-picker__img');
    const empty = picker.querySelector<HTMLElement>('.ui-image-picker__empty');
    const loading = picker.querySelector<HTMLElement>('.ui-image-picker__loading');
    const remove = picker.querySelector<HTMLElement>('.ui-image-picker__remove');
    const removeValue = picker.querySelector<HTMLInputElement>('.ui-image-picker__remove-value');

    show(empty, false);
    show(image, false);
    show(loading, true);
    const reader = new FileReader();
    reader.addEventListener('load', () => {
      if (image) image.src = String(reader.result);
      show(loading, false);
      show(image, true);
      show(remove, true);
      picker.classList.add('ui-image-picker--filled');
      if (removeValue) removeValue.value = '0';
    });
    reader.readAsDataURL(file);
  });

  document.addEventListener('click', (event) => {
    const button = (event.target as HTMLElement | null)?.closest<HTMLElement>('.ui-image-picker__remove');
    const picker = button?.closest<HTMLElement>('[data-image-picker]');
    if (!button || !picker) return;

    event.preventDefault();
    const input = picker.querySelector<HTMLInputElement>('.ui-image-picker__input');
    const image = picker.querySelector<HTMLImageElement>('.ui-image-picker__img');
    if (input) input.value = '';
    if (image) image.removeAttribute('src');
    show(image, false);
    show(picker.querySelector<HTMLElement>('.ui-image-picker__empty'), true);
    show(button, false);
    picker.classList.remove('ui-image-picker--filled');
    const removeValue = picker.querySelector<HTMLInputElement>('.ui-image-picker__remove-value');
    if (removeValue) removeValue.value = '1';
  });
};

// 효과 고르기의 원래 목록 (효과 종류를 바꿀 때마다 거기서 골라 다시 채운다)
const allFxOptions = new WeakMap<HTMLSelectElement, HTMLOptionElement[]>();

// 상자 하나의 보이는 칸을 사용대상·재화 종류·효과 종류에 맞춘다
const syncBox = (box: HTMLElement) => {
  const type = box.querySelector<HTMLSelectElement>('[data-effect-type]')?.value ?? 'stat';
  box.querySelectorAll<HTMLElement>('[data-effect-group]').forEach((group) => {
    const active = group.dataset.effectGroup === type;
    group.hidden = !active;
    group.querySelectorAll<HTMLInputElement | HTMLSelectElement>('input, select').forEach((field) => {
      field.disabled = !active;
    });
  });

  // 특수 > 소문내기: 문구 칸은 종류가 소문내기일 때만
  const specialKind = box.querySelector<HTMLSelectElement>('[data-effect-special-kind]');
  const rumor = box.querySelector<HTMLInputElement>('[data-effect-rumor]');
  if (specialKind && rumor) {
    const rumorOn = type === 'special' && specialKind.value === 'rumor';
    rumor.hidden = !rumorOn;
    rumor.disabled = !rumorOn;
  }

  const currency = box.querySelector<HTMLSelectElement>('[data-effect-currency]');
  const item = box.querySelector<HTMLSelectElement>('[data-effect-item]');
  if (currency && item) {
    const isItem = type === 'currency' && currency.value === 'item';
    item.hidden = !isItem;
    item.disabled = !isItem;
  }

  const target = box.querySelector<HTMLSelectElement>('[data-effect-fx-target]');
  const fx = box.querySelector<HTMLSelectElement>('[data-effect-fx]');
  if (target && fx) {
    // 고르기 목록을 효과 종류에 맞는 것만으로 다시 채운다 (캐릭터: 칭호·데코, 소속: 소속 카드). 숨김(hidden)은 드롭다운에서 안 먹어서 지웠다 다시 넣는다
    const all = allFxOptions.get(fx) ?? Array.from(fx.options).map((option) => option.cloneNode(true) as HTMLOptionElement);
    allFxOptions.set(fx, all);
    const current = fx.value;
    fx.replaceChildren(...all.filter((option) => !option.dataset.fxKind || option.dataset.fxKind === target.value).map((option) => option.cloneNode(true) as HTMLOptionElement));
    fx.value = Array.from(fx.options).some((option) => option.value === current) ? current : '';
  }
};

let counter = 1000;

export const setupItemEffects = () => {
  document.querySelectorAll<HTMLElement>('[data-effect-box]').forEach(syncBox);

  document.addEventListener('change', (event) => {
    const field = event.target as HTMLElement | null;
    if (!field?.matches('[data-effect-type], [data-effect-currency], [data-effect-fx-target], [data-effect-special-kind]')) return;

    const box = field.closest<HTMLElement>('[data-effect-box]');
    if (box) syncBox(box);
  });

  document.addEventListener('click', (event) => {
    const target = event.target as HTMLElement | null;

    const add = target?.closest<HTMLElement>('[data-effect-add]');
    if (add) {
      event.preventDefault();
      const form = add.closest('form');
      const template = form?.querySelector<HTMLTemplateElement>('template[data-effect-template]');
      const list = form?.querySelector<HTMLElement>('[data-effect-list]');
      if (!template || !list) return;

      counter += 1;
      const holder = document.createElement('div');
      holder.innerHTML = template.innerHTML.replaceAll('__INDEX__', String(counter));
      const box = holder.firstElementChild as HTMLElement | null;
      if (!box) return;
      list.append(box);
      syncBox(box);
      box.querySelector<HTMLElement>('[data-effect-type]')?.focus();
      return;
    }

    const remove = target?.closest<HTMLElement>('[data-effect-remove]');
    if (remove) {
      event.preventDefault();
      remove.closest('[data-effect-box]')?.remove();
    }
  });

  // 보낼 때 상자 번호를 화면 순서대로 0, 1, 2… (템플릿 안 칸은 보내지 않는다)
  document.addEventListener('submit', (event) => {
    const form = event.target as HTMLFormElement | null;
    const list = form?.querySelector<HTMLElement>('[data-effect-list]');
    if (!list) return;

    list.querySelectorAll<HTMLElement>('[data-effect-box]').forEach((box, index) => {
      box.querySelectorAll<HTMLInputElement | HTMLSelectElement>('[name^="game_shop_item[item_effects]"]').forEach((field) => {
        field.name = field.name.replace(/^game_shop_item\[item_effects\]\[[^\]]+\]/, `game_shop_item[item_effects][${index}]`);
      });
    });
  }, true);
};

// 누적 효과 모달: 누적 횟수가 '최대치'면 횟수·지속시간 칸을 숨기고(영구), 지속시간이 '영구'면 숫자 칸을 숨긴다
const syncCounterRule = (form: HTMLFormElement) => {
  const atMax = form.querySelector<HTMLSelectElement>('[data-rule-mode]')?.value === 'max';
  const forever = form.querySelector<HTMLSelectElement>('[data-rule-unit]')?.value === 'forever';
  const hide: Record<string, boolean> = { number: atMax, duration: atMax, amount: atMax || forever };

  form.querySelectorAll<HTMLElement>('[data-rule-part]').forEach((part) => {
    const hidden = hide[part.dataset.rulePart ?? ''] ?? false;
    part.hidden = hidden;
    part.querySelectorAll<HTMLInputElement | HTMLSelectElement>('input, select').forEach((field) => {
      field.disabled = hidden;
    });
  });
};

export const setupCounterRules = () => {
  document.querySelectorAll<HTMLFormElement>('form[data-counter-rule]').forEach(syncCounterRule);

  document.addEventListener('change', (event) => {
    const field = event.target as HTMLElement | null;
    if (!field?.matches('[data-rule-mode], [data-rule-unit]')) return;

    const form = field.closest<HTMLFormElement>('form[data-counter-rule]');
    if (form) syncCounterRule(form);
  });
};
