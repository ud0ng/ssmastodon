// 관리 > 컨텐츠 설정 화면 (admin/game_settings/show) 을 쓰기 편하게:
//  - 기본값과 달라진 항목에 '변경됨' 표시 + 항목별 '기본값으로'
//  - 묶음 제목에 바뀐 항목 수
//  - 저장하지 않은 변경이 있으면 화면 아래 저장 줄 (+ 나갈 때 경고)
//  - 문구 칸 옆 실시간 미리보기 (견본 이름으로 채운 툿 모양, 모르는 {명령어}는 빨간 표시)
//  - 줄마다 하나인 목록(젤리빈 맛 등)은 칩으로 추가·삭제
//  - '(%)' 숫자 칸은 슬라이더도 같이

type Segment =
  | { kind: 'text'; text: string }
  | { kind: 'value'; text: string }
  | { kind: 'token'; text: string }
  | { kind: 'unknown'; text: string }
  | { kind: 'particle'; text: string };

const PARTICLES: Record<string, [string, string]> = {
  이가: ['이', '가'],
  을를: ['을', '를'],
  은는: ['은', '는'],
  과와: ['과', '와'],
  아야: ['아', '야'],
  으로로: ['으로', '로'],
};

const CLOSERS = /[\s」』)\]}>'"”’》〉]+$/;

// 앞 글자 받침에 맞는 조사 (Game::Text.particle 과 같다)
const particle = (before: string, key: string) => {
  const [withFinal, withoutFinal] = PARTICLES[key] ?? ['', ''];
  const char = before.replace(CLOSERS, '').slice(-1);
  const code = char.charCodeAt(0);
  if (!char || code < 0xac00 || code > 0xd7a3) return `${withFinal}(${withoutFinal})`;

  const final = (code - 0xac00) % 28;
  if (key === '으로로' && final === 8) return withoutFinal;
  return final === 0 ? withoutFinal : withFinal;
};

const segmentsOf = (
  template: string,
  samples: Record<string, string>,
  allowed: string[],
): Segment[] => {
  const segments: Segment[] = [];
  const pattern = /\{([^{}\n]{1,30})\}|%\{(\w+)\}/g;
  let last = 0;

  for (const match of template.matchAll(pattern)) {
    if (match.index > last)
      segments.push({ kind: 'text', text: template.slice(last, match.index) });
    last = match.index + match[0].length;

    const name = match[1] ?? match[2] ?? '';
    if (match[2]) segments.push({ kind: 'token', text: name });
    else if (PARTICLES[name]) segments.push({ kind: 'particle', text: name });
    else if (samples[name] !== undefined)
      segments.push({ kind: 'value', text: samples[name] });
    else if (allowed.includes(name))
      segments.push({ kind: 'token', text: name });
    else segments.push({ kind: 'unknown', text: name });
  }
  if (last < template.length)
    segments.push({ kind: 'text', text: template.slice(last) });

  // 조사는 바로 앞에 실제로 보이는 글자를 본다
  let before = '';
  return segments.map((segment) => {
    if (segment.kind === 'particle') {
      const text = particle(before, segment.text);
      before += text;
      return { kind: 'text', text };
    }
    before += segment.kind === 'text' || segment.kind === 'value' ? segment.text : '○';
    return segment;
  });
};

const renderPreview = (
  body: HTMLElement,
  warn: HTMLElement,
  template: string,
  samples: Record<string, string>,
  allowed: string[],
) => {
  body.replaceChildren();
  const unknown = new Set<string>();

  segmentsOf(template, samples, allowed).forEach((segment) => {
    if (segment.kind === 'text') {
      body.append(segment.text);
      return;
    }

    const span = document.createElement('span');
    span.className = `game-preview__${segment.kind}`;
    if (segment.kind === 'value' && segment.text === '🖼') {
      span.className = 'game-preview__photo';
      span.textContent = '🖼';
    } else {
      span.textContent = segment.kind === 'value' ? segment.text : `{${segment.text}}`;
    }
    if (segment.kind === 'unknown') unknown.add(segment.text);
    body.append(span);
  });

  warn.hidden = unknown.size === 0;
  warn.textContent = unknown.size
    ? (warn.dataset.template ?? '{tokens}').replace(
        '{tokens}',
        [...unknown].map((name) => `{${name}}`).join(' '),
      )
    : '';
};

const normalize = (value: string) => value.replace(/\r\n/g, '\n').trimEnd();

class FieldState {
  readonly element: HTMLElement;
  readonly type: string;
  readonly defaultValue: string;
  readonly initial: string;
  private badge?: HTMLElement;

  constructor(element: HTMLElement) {
    this.element = element;
    this.type = element.dataset.gameField ?? 'string';
    this.defaultValue = normalize(element.dataset.default ?? '');
    this.initial = this.value();
  }

  get input() {
    if (this.type === 'boolean')
      return this.element.querySelector<HTMLInputElement>('input[type="checkbox"]');
    return this.element.querySelector<HTMLInputElement | HTMLTextAreaElement | HTMLSelectElement>(
      'textarea, select, input:not([type="hidden"]):not([type="range"]):not(.game-chips__input)',
    );
  }

  value() {
    const input = this.input;
    if (!input) return '';
    if (input instanceof HTMLInputElement && input.type === 'checkbox')
      return input.checked ? '1' : '0';
    return normalize(input.value);
  }

  set(value: string) {
    const input = this.input;
    if (!input) return;
    if (input instanceof HTMLInputElement && input.type === 'checkbox')
      input.checked = value === '1';
    else input.value = value;
    input.dispatchEvent(new Event('input', { bubbles: true }));
    input.dispatchEvent(new Event('change', { bubbles: true }));
  }

  get changedFromDefault() {
    return this.value() !== this.defaultValue;
  }

  get dirty() {
    return this.value() !== this.initial;
  }

  // 라벨 옆 '변경됨' + '기본값으로'
  decorate(labels: { changed: string; reset: string }) {
    const label =
      this.element.querySelector('.bot-sheet-switch__label') ??
      this.element.querySelector('.label_input > label');
    if (!label) return;

    const badge = document.createElement('span');
    badge.className = 'game-field__changed';
    badge.textContent = labels.changed;

    const reset = document.createElement('button');
    reset.type = 'button';
    reset.className = 'game-field__reset';
    reset.textContent = labels.reset;
    reset.title = this.defaultValue;
    reset.addEventListener('click', (event) => {
      event.preventDefault();
      this.set(this.defaultValue);
    });

    badge.append(reset);
    // 켜기/끄기 칸은 라벨 안이 좁아서 칸 아래에 붙인다
    if (this.type === 'boolean') this.element.append(badge);
    else label.after(badge);
    this.badge = badge;
  }

  refresh() {
    if (this.badge) this.badge.hidden = !this.changedFromDefault;
    this.element.classList.toggle('game-field--changed', this.changedFromDefault);
    this.element.classList.toggle('game-field--dirty', this.dirty);
  }
}

// 줄마다 하나인 목록 → 칩 (textarea 는 숨기고 값은 그대로 쓴다)
const attachChips = (field: FieldState, placeholder: string) => {
  const textarea = field.input;
  if (!(textarea instanceof HTMLTextAreaElement)) return;

  const box = document.createElement('div');
  box.className = 'game-chips';
  const input = document.createElement('input');
  input.type = 'text';
  input.className = 'game-chips__input';
  input.placeholder = placeholder;

  const items = () => textarea.value.split('\n').map((line) => line.trim()).filter(Boolean);
  const write = (list: string[]) => {
    textarea.value = list.join('\n');
    textarea.dispatchEvent(new Event('input', { bubbles: true }));
  };

  const render = () => {
    box.querySelectorAll('.game-chips__chip').forEach((chip) => {
      chip.remove();
    });
    items().forEach((item, index) => {
      const chip = document.createElement('span');
      chip.className = 'game-chips__chip';
      chip.textContent = item;
      // 끌어서 순서 바꾸기
      chip.draggable = true;
      chip.addEventListener('dragstart', (event) => {
        event.dataTransfer?.setData('text/plain', String(index));
        chip.classList.add('game-chips__chip--dragging');
      });
      chip.addEventListener('dragend', () => {
        chip.classList.remove('game-chips__chip--dragging');
      });
      chip.addEventListener('dragover', (event) => {
        event.preventDefault();
      });
      chip.addEventListener('drop', (event) => {
        event.preventDefault();
        const from = Number(event.dataTransfer?.getData('text/plain'));
        if (Number.isNaN(from) || from === index) return;
        const list = items();
        const [moved] = list.splice(from, 1);
        if (moved !== undefined) list.splice(index, 0, moved);
        write(list);
      });
      const remove = document.createElement('button');
      remove.type = 'button';
      remove.className = 'game-chips__remove';
      remove.textContent = '×';
      remove.setAttribute('aria-label', `${item} ×`);
      remove.addEventListener('click', () => {
        const list = items();
        list.splice(index, 1);
        write(list);
      });
      chip.append(remove);
      box.insertBefore(chip, input);
    });
  };

  input.addEventListener('keydown', (event) => {
    if (event.key !== 'Enter' && event.key !== ',') return;
    event.preventDefault();
    const value = input.value.trim();
    if (!value) return;
    write([...items(), value]);
    input.value = '';
  });

  box.append(input);
  textarea.after(box);
  textarea.classList.add('game-chips__source');
  textarea.addEventListener('input', render);
  render();
};

// '(%)' 숫자 칸 옆 슬라이더
const attachSlider = (field: FieldState) => {
  const number = field.input;
  if (!(number instanceof HTMLInputElement)) return;

  const slider = document.createElement('input');
  slider.type = 'range';
  slider.min = '0';
  slider.max = '100';
  slider.className = 'game-slider';
  slider.value = number.value || '0';
  slider.addEventListener('input', () => {
    number.value = slider.value;
    number.dispatchEvent(new Event('input', { bubbles: true }));
  });
  number.addEventListener('input', () => {
    slider.value = number.value || '0';
  });
  number.parentElement?.classList.add('game-slider__wrapper');
  number.before(slider);
};

// '…_perfect' + '…_half' 확률 → 완벽·어중간·실패(나머지) 막대. 합이 100 을 넘으면 경고.
const attachSplitBars = (form: HTMLFormElement, labels: string[]) => {
  form.querySelectorAll<HTMLInputElement>('input[name$="_half]"]').forEach((half) => {
    const prefix = half.name.replace(/_half]$/, '');
    const perfect = form.querySelector<HTMLInputElement>(`input[name="${prefix}_perfect]"]`);
    const field = half.closest<HTMLElement>('.game-field');
    if (!perfect || !field) return;

    const bar = document.createElement('div');
    bar.className = 'game-split';
    field.append(bar);

    const update = () => {
      const a = Math.max(0, Number(perfect.value) || 0);
      const b = Math.max(0, Number(half.value) || 0);
      const rest = 100 - a - b;
      bar.replaceChildren();
      [[a, 'perfect'], [b, 'half'], [Math.max(rest, 0), 'fail']].forEach(([value, kind], index) => {
        const segment = document.createElement('span');
        segment.className = `game-split__segment game-split__segment--${kind}`;
        segment.style.flexGrow = String(value);
        segment.textContent = Number(value) > 0 ? `${labels[index] ?? ''} ${value}%` : '';
        bar.append(segment);
      });
      bar.classList.toggle('game-split--over', rest < 0);
      bar.title = rest < 0 ? (labels[3] ?? '') : '';
    };
    perfect.addEventListener('input', update);
    half.addEventListener('input', update);
    update();
  });
};

export const setupGameConfigEditor = () => {
  const form = document.querySelector<HTMLFormElement>('form[data-game-config]');
  if (!form) return;

  const samples = JSON.parse(form.dataset.samples ?? '{}') as Record<string, string>;
  const labels = {
    changed: form.dataset.changedLabel ?? 'Changed',
    reset: form.dataset.resetLabel ?? 'Default',
    chips: form.dataset.chipsPlaceholder ?? 'Add',
    unknown: form.dataset.unknownLabel ?? 'Unknown: {tokens}',
  };
  const fields = Array.from(form.querySelectorAll<HTMLElement>('.game-field')).map(
    (element) => new FieldState(element),
  );

  fields.forEach((field) => {
    field.decorate(labels);
    if (field.type === 'lines') attachChips(field, labels.chips);
    if (field.element.dataset.percent !== undefined) attachSlider(field);

    if (field.type === 'text') {
      const textarea = field.input;
      if (!(textarea instanceof HTMLTextAreaElement)) return;

      const allowed = JSON.parse(field.element.dataset.tokens ?? '[]') as string[];
      const preview = document.createElement('div');
      preview.className = 'game-preview';
      preview.innerHTML = `<div class="game-preview__head"><img class="game-preview__avatar" alt=""><strong class="game-preview__name"></strong></div><div class="game-preview__body"></div><div class="game-preview__warn" hidden></div>`;
      const avatar = preview.querySelector<HTMLImageElement>('.game-preview__avatar');
      if (avatar) {
        if (form.dataset.systemAvatar) avatar.src = form.dataset.systemAvatar;
        else avatar.remove();
      }
      const name = preview.querySelector('.game-preview__name');
      if (name) name.textContent = form.dataset.systemName ?? '';
      const body = preview.querySelector<HTMLElement>('.game-preview__body');
      const warn = preview.querySelector<HTMLElement>('.game-preview__warn');
      if (!body || !warn) return;
      warn.dataset.template = labels.unknown;

      const update = () => {
        renderPreview(body, warn, textarea.value, samples, allowed);
      };
      textarea.addEventListener('input', update);
      field.element.classList.add('game-field--message');
      textarea.closest('.label_input')?.append(preview);
      update();
    }
  });

  attachSplitBars(form, JSON.parse(form.dataset.splitLabels ?? '[]') as string[]);

  const savebar = form.querySelector<HTMLElement>('.game-savebar');
  const savebarText = savebar?.querySelector<HTMLElement>('.game-savebar__text');
  let submitting = false;

  const refresh = () => {
    fields.forEach((field) => {
      field.refresh();
    });

    form.querySelectorAll<HTMLDetailsElement>('details.game-group').forEach((group) => {
      const changed = group.querySelectorAll('.game-field--changed').length;
      const badge = group.querySelector<HTMLElement>('.game-group__changed');
      if (!badge) return;
      badge.hidden = changed === 0;
      badge.textContent = `${labels.changed} ${changed}`;
    });

    const dirty = fields.filter((field) => field.dirty).length;
    if (savebar) savebar.hidden = dirty === 0;
    if (savebarText)
      savebarText.textContent = (savebarText.dataset.template ?? '{count}').replace('{count}', String(dirty));
  };

  form.addEventListener('input', refresh);
  form.addEventListener('change', refresh);
  form.addEventListener('submit', () => {
    submitting = true;
  });

  savebar?.querySelector('.game-savebar__reset')?.addEventListener('click', () => {
    fields.filter((field) => field.dirty).forEach((field) => {
      field.set(field.initial);
    });
  });

  window.addEventListener('beforeunload', (event) => {
    if (submitting || !fields.some((field) => field.dirty)) return;
    event.preventDefault();
  });

  refresh();
};

// 캐릭터 개인 값: '이름=값' 줄 → 표 (textarea 는 숨기고 값은 그대로 쓴다)
// 이름=값 / 이름|개수|메모 같은 줄 글을 칸 표로 (data-stats-editor: { key, value } 또는 { columns: [...], sep })
export const setupStatsEditor = () => {
  document.querySelectorAll<HTMLTextAreaElement>('textarea[data-stats-editor]').forEach((textarea) => {
    const options = JSON.parse(textarea.dataset.statsEditor ?? '{}') as { key?: string; value?: string; columns?: string[]; sep?: string };
    const columns = options.columns ?? [options.key ?? '', options.value ?? ''];
    const sep = options.sep ?? '=';
    const table = document.createElement('div');
    table.className = `game-stats game-stats--${columns.length}`;

    const split = (line: string) => {
      const parts = line.split(sep);
      const head = parts.slice(0, columns.length - 1);
      const rest = parts.slice(columns.length - 1).join(sep);
      return [...head, rest].map((cell) => cell.trim()).concat(Array(columns.length).fill('')).slice(0, columns.length);
    };

    const rows = () =>
      textarea.value
        .split('\n')
        .filter((line) => line.split(sep)[0]?.trim())
        .map(split);

    const write = (list: string[][]) => {
      textarea.value = list
        .filter(([key]) => key)
        .map((row) => {
          const cells = [...row];
          while (cells.length > 2 && !cells[cells.length - 1]) cells.pop();
          return cells.join(sep);
        })
        .join('\n');
    };

    const render = () => {
      table.replaceChildren();
      const list = rows();
      [...list, columns.map(() => '')].forEach((row, index) => {
        const line = document.createElement('div');
        line.className = 'game-stats__row';
        row.forEach((cell, column) => {
          const input = document.createElement('input');
          input.type = 'text';
          input.value = cell;
          input.placeholder = columns[column] ?? '';
          input.addEventListener('change', () => {
            const next = rows();
            const current = next[index] ?? columns.map(() => '');
            current[column] = input.value.trim().replaceAll(sep, ' ');
            next[index] = current;
            write(next);
            render();
          });
          line.append(input);
        });
        if (index < list.length) {
          const remove = document.createElement('button');
          remove.type = 'button';
          remove.className = 'game-stats__remove';
          remove.textContent = '×';
          remove.addEventListener('click', () => {
            const next = rows();
            next.splice(index, 1);
            write(next);
            render();
          });
          line.append(remove);
        }
        table.append(line);
      });
    };

    textarea.classList.add('game-chips__source');
    textarea.after(table);
    render();
  });
};

// 토너먼트 대진표 (admin/game_tournaments/show): 경기를 누르면 오른쪽 패널에 그 경기 편집,
// 선수 칩을 경기 칸에 끌어다 놓으면 그 경기 폼에 넣고 바로 저장한다.
export const setupBracketEditor = () => {
  const root = document.querySelector<HTMLElement>('[data-bracket-editor]');
  if (!root) return;

  const select = (id: string) => {
    root.querySelectorAll<HTMLElement>('.game-bracket__match').forEach((match) => {
      match.classList.toggle('game-bracket__match--selected', match.dataset.match === id);
    });
    root.querySelectorAll<HTMLElement>('[data-edit]').forEach((panel) => {
      panel.hidden = panel.dataset.edit !== id;
    });
    const hint = root.querySelector<HTMLElement>('.game-bracket__panel-hint');
    if (hint) hint.hidden = true;
  };

  root.querySelectorAll<HTMLElement>('.game-bracket__match').forEach((match) => {
    const open = () => {
      if (match.dataset.match) select(match.dataset.match);
    };
    match.addEventListener('click', open);
    match.addEventListener('keydown', (event) => {
      if (event.key === 'Enter' || event.key === ' ') {
        event.preventDefault();
        open();
      }
    });
  });

  // 저장하고 돌아오면 (#match-3) 그 경기를 연다
  const fromHash = /^#match-(\d+)$/.exec(window.location.hash)?.[1];
  if (fromHash) select(fromHash);

  root.querySelectorAll<HTMLElement>('.game-bracket__chip').forEach((chip) => {
    chip.addEventListener('dragstart', (event) => {
      event.dataTransfer?.setData('text/plain', chip.dataset.accountId ?? '');
    });
  });

  root.querySelectorAll<HTMLElement>('.game-bracket__slot[data-droppable]').forEach((slot) => {
    slot.addEventListener('dragover', (event) => {
      event.preventDefault();
      slot.classList.add('game-bracket__slot--over');
    });
    slot.addEventListener('dragleave', () => {
      slot.classList.remove('game-bracket__slot--over');
    });
    slot.addEventListener('drop', (event) => {
      event.preventDefault();
      slot.classList.remove('game-bracket__slot--over');
      const accountId = event.dataTransfer?.getData('text/plain');
      const form = root.querySelector<HTMLFormElement>(`form[data-match-form="${slot.dataset.match}"]`);
      const field = form?.querySelector<HTMLSelectElement>(`select[data-slot="${slot.dataset.slot}"]`);
      if (!accountId || !form || !field) return;
      field.value = accountId;
      form.requestSubmit();
    });
  });
};
