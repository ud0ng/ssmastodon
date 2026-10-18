import { createRoot } from 'react-dom/client';

import Rails from '@rails/ujs';

import { setupCommunityCombobox } from '../mastodon/admin/community_combobox';
import { setupInlineSelects } from '../mastodon/admin/inline_select';
import { setupCommunitySelect } from '../mastodon/admin/community_select';
import { setupDateInputs } from '../mastodon/admin/date_picker';
import { setupCommunityThemeEditor } from '../mastodon/admin/community_theme_editor';
import { setupGameConfigEditor, setupStatsEditor } from '../mastodon/admin/game_config_editor';
import { addItemCard, filterItemOptions } from '../mastodon/admin/item_picker';
import ready from '../mastodon/ready';

const setAnnouncementEndsAttributes = (target: HTMLInputElement) => {
  const valid = target.value && target.validity.valid;
  const element = document.querySelector<HTMLInputElement>(
    'input[type="datetime-local"]#announcement_ends_at',
  );

  if (!element) return;

  if (valid) {
    element.classList.remove('optional');
    element.required = true;
    element.min = target.value;
  } else {
    element.classList.add('optional');
    element.removeAttribute('required');
    element.removeAttribute('min');
  }
};

Rails.delegate(
  document,
  'input[type="datetime-local"]#announcement_starts_at',
  'change',
  ({ target }) => {
    if (target instanceof HTMLInputElement)
      setAnnouncementEndsAttributes(target);
  },
);

const SITE_UPLOAD_INPUT = '#edit_admin_settings input[type="file"]';

const loadImageSize = (url: string) =>
  new Promise<{ width: number; height: number }>((resolve, reject) => {
    const image = new Image();
    image.onload = () => {
      resolve({ width: image.naturalWidth, height: image.naturalHeight });
    };
    image.onerror = () => {
      reject(new Error(`Could not read image ${url}`));
    };
    image.src = url;
  });

const findSiteUploadProblem = async (
  input: HTMLInputElement,
  file: File,
  url: string,
): Promise<string | null> => {
  const {
    allowedTypes,
    typeError,
    sizeError,
    expectedWidth,
    expectedHeight,
    tolerance,
  } = input.dataset;

  if (allowedTypes && typeError && !allowedTypes.split(',').includes(file.type))
    return typeError;

  if (!sizeError || !expectedWidth || !expectedHeight) return null;

  try {
    const { width, height } = await loadImageSize(url);
    const slack = Number(tolerance ?? 0);
    const fits =
      Math.abs(width - Number(expectedWidth)) <= slack &&
      Math.abs(height - Number(expectedHeight)) <= slack;

    return fits ? null : sizeError.replace('{actual}', `${width}×${height}`);
  } catch {
    return typeError ?? null;
  }
};

const showSiteUploadProblem = (
  input: HTMLInputElement,
  message: string | null,
) => {
  input.setCustomValidity(message ?? '');

  const slot = document.querySelector<HTMLElement>(
    `[data-client-error="${input.id}"]`,
  );
  if (slot) {
    slot.textContent = message ?? '';
    slot.hidden = !message;
  }

  input
    .closest('.image-picker__frame')
    ?.classList.toggle('image-picker__frame--invalid', Boolean(message));
};

const setSiteUploadPreviews = (input: HTMLInputElement, url?: string) => {
  const frame = input.closest<HTMLElement>('.image-picker__frame');

  // 아직 아무 이미지도 없던 칸이면 미리보기 이미지를 새로 만든다 (안 그러면 고른 게 안 보인다)
  if (
    url &&
    frame &&
    !frame.querySelector(`img[data-upload-preview="${input.id}"]`)
  ) {
    const image = document.createElement('img');
    image.className = 'image-picker__img';
    image.alt = '';
    image.dataset.uploadPreview = input.id;
    image.dataset.created = 'true';
    frame.prepend(image);
  }

  // 고른 파일은 저장해야 올라간다는 표시
  if (!url)
    frame
      ?.querySelectorAll('img[data-created="true"]')
      .forEach((image) => {
        image.remove();
      });
  frame?.classList.toggle('image-picker__frame--pending', Boolean(url));
  frame?.classList.toggle(
    'image-picker__frame--empty',
    !url && !frame.querySelector('img'),
  );

  document
    .querySelectorAll<HTMLImageElement>(
      `img[data-upload-preview="${input.id}"]`,
    )
    .forEach((image) => {
      const src = url ?? image.dataset.originalSrc;
      if (src) image.src = src;
    });
};

Rails.delegate(document, SITE_UPLOAD_INPUT, 'change', ({ target }) => {
  if (!(target instanceof HTMLInputElement)) return;

  document
    .querySelectorAll<HTMLElement>(`[data-server-error="${target.id}"]`)
    .forEach((element) => {
      element.hidden = true;
    });

  const file = target.files?.[0];
  if (!file) {
    setSiteUploadPreviews(target);
    showSiteUploadProblem(target, null);
    return;
  }

  const url = URL.createObjectURL(file);
  setSiteUploadPreviews(target, url);
  void findSiteUploadProblem(target, file, url).then((message) => {
    showSiteUploadProblem(target, message);
  });
});

const batchCheckboxClassName = '.batch-checkbox input[type="checkbox"]';

const showSelectAll = () => {
  const selectAllMatchingElement = document.querySelector(
    '.batch-table__select-all',
  );
  selectAllMatchingElement?.classList.add('active');
};

const hideSelectAll = () => {
  const selectAllMatchingElement = document.querySelector(
    '.batch-table__select-all',
  );
  const hiddenField = document.querySelector<HTMLInputElement>(
    'input#select_all_matching',
  );
  const selectedMsg = document.querySelector(
    '.batch-table__select-all .selected',
  );
  const notSelectedMsg = document.querySelector(
    '.batch-table__select-all .not-selected',
  );

  selectAllMatchingElement?.classList.remove('active');
  selectedMsg?.classList.remove('active');
  notSelectedMsg?.classList.add('active');
  if (hiddenField) hiddenField.value = '0';
};

Rails.delegate(document, '#batch_checkbox_all', 'change', ({ target }) => {
  if (!(target instanceof HTMLInputElement)) return;

  const selectAllMatchingElement = document.querySelector(
    '.batch-table__select-all',
  );

  document
    .querySelectorAll<HTMLInputElement>(batchCheckboxClassName)
    .forEach((content) => {
      content.checked = target.checked;
    });

  if (selectAllMatchingElement) {
    if (target.checked) {
      showSelectAll();
    } else {
      hideSelectAll();
    }
  }
});

Rails.delegate(document, '.batch-table__select-all button', 'click', () => {
  const hiddenField = document.querySelector<HTMLInputElement>(
    '#select_all_matching',
  );

  if (!hiddenField) return;

  const active = hiddenField.value === '1';
  const selectedMsg = document.querySelector(
    '.batch-table__select-all .selected',
  );
  const notSelectedMsg = document.querySelector(
    '.batch-table__select-all .not-selected',
  );

  if (!selectedMsg || !notSelectedMsg) return;

  if (active) {
    hiddenField.value = '0';
    selectedMsg.classList.remove('active');
    notSelectedMsg.classList.add('active');
  } else {
    hiddenField.value = '1';
    notSelectedMsg.classList.remove('active');
    selectedMsg.classList.add('active');
  }
});

Rails.delegate(document, batchCheckboxClassName, 'change', () => {
  const checkAllElement = document.querySelector<HTMLInputElement>(
    'input#batch_checkbox_all',
  );
  const selectAllMatchingElement = document.querySelector(
    '.batch-table__select-all',
  );

  if (checkAllElement) {
    const allCheckboxes = Array.from(
      document.querySelectorAll<HTMLInputElement>(batchCheckboxClassName),
    );
    checkAllElement.checked = allCheckboxes.every((content) => content.checked);
    checkAllElement.indeterminate =
      !checkAllElement.checked &&
      allCheckboxes.some((content) => content.checked);

    if (selectAllMatchingElement) {
      if (checkAllElement.checked) {
        showSelectAll();
      } else {
        hideSelectAll();
      }
    }
  }
});

Rails.delegate(
  document,
  '.filter-subset--with-select select',
  'change',
  ({ target }) => {
    if (target instanceof HTMLSelectElement) target.form?.submit();
  },
);

const onDomainBlockSeverityChange = (target: HTMLSelectElement) => {
  const rejectMediaDiv = document.querySelector(
    '.input.with_label.domain_block_reject_media',
  );
  const rejectReportsDiv = document.querySelector(
    '.input.with_label.domain_block_reject_reports',
  );

  if (rejectMediaDiv && rejectMediaDiv instanceof HTMLElement) {
    rejectMediaDiv.style.display =
      target.value === 'suspend' ? 'none' : 'block';
  }

  if (rejectReportsDiv && rejectReportsDiv instanceof HTMLElement) {
    rejectReportsDiv.style.display =
      target.value === 'suspend' ? 'none' : 'block';
  }
};

Rails.delegate(document, '#domain_block_severity', 'change', ({ target }) => {
  if (target instanceof HTMLSelectElement) onDomainBlockSeverityChange(target);
});

const onEnableBootstrapTimelineAccountsChange = (target: HTMLInputElement) => {
  const bootstrapTimelineAccountsField =
    document.querySelector<HTMLInputElement>(
      '#form_admin_settings_bootstrap_timeline_accounts',
    );

  if (bootstrapTimelineAccountsField) {
    bootstrapTimelineAccountsField.disabled = !target.checked;
    if (target.checked) {
      bootstrapTimelineAccountsField.parentElement?.classList.remove(
        'disabled',
      );
      bootstrapTimelineAccountsField.parentElement?.parentElement?.classList.remove(
        'disabled',
      );
    } else {
      bootstrapTimelineAccountsField.parentElement?.classList.add('disabled');
      bootstrapTimelineAccountsField.parentElement?.parentElement?.classList.add(
        'disabled',
      );
    }
  }
};

Rails.delegate(
  document,
  '#form_admin_settings_enable_bootstrap_timeline_accounts',
  'change',
  ({ target }) => {
    if (target instanceof HTMLInputElement)
      onEnableBootstrapTimelineAccountsChange(target);
  },
);

const onChangeRegistrationMode = (target: HTMLSelectElement) => {
  const enabled = target.value === 'approved';

  document
    .querySelectorAll<HTMLElement>(
      '.form_admin_settings_registrations_mode .warning-hint',
    )
    .forEach((warning_hint) => {
      warning_hint.style.display = target.value === 'open' ? 'inline' : 'none';
    });

  document
    .querySelectorAll<HTMLInputElement>(
      'input#form_admin_settings_require_invite_text',
    )
    .forEach((input) => {
      input.disabled = !enabled;
      if (enabled) {
        let element: HTMLElement | null = input;
        do {
          element.classList.remove('disabled');
          element = element.parentElement;
        } while (element && !element.classList.contains('fields-group'));
      } else {
        let element: HTMLElement | null = input;
        do {
          element.classList.add('disabled');
          element = element.parentElement;
        } while (element && !element.classList.contains('fields-group'));
      }
    });
};

const convertUTCDateTimeToLocal = (value: string) => {
  const date = new Date(value + 'Z');
  const twoChars = (x: number) => x.toString().padStart(2, '0');
  return `${date.getFullYear()}-${twoChars(date.getMonth() + 1)}-${twoChars(date.getDate())}T${twoChars(date.getHours())}:${twoChars(date.getMinutes())}`;
};

function convertLocalDatetimeToUTC(value: string) {
  const date = new Date(value);
  const fullISO8601 = date.toISOString();
  return fullISO8601.slice(0, fullISO8601.indexOf('T') + 6);
}

Rails.delegate(
  document,
  '#form_admin_settings_registrations_mode',
  'change',
  ({ target }) => {
    if (target instanceof HTMLSelectElement) onChangeRegistrationMode(target);
  },
);

async function mountReactComponent(element: Element) {
  const componentName = element.getAttribute('data-admin-component');
  const stringProps = element.getAttribute('data-props');

  if (!stringProps) return;

  const componentProps = JSON.parse(stringProps) as object;

  const { default: AdminComponent } = await import(
    '@/mastodon/containers/admin_component'
  );

  const { default: Component } = (await import(
    `@/mastodon/components/admin/${componentName}.jsx`
  )) as { default: React.ComponentType };

  const root = createRoot(element);

  root.render(
    <AdminComponent>
      <Component {...componentProps} />
    </AdminComponent>,
  );
}

// 색 코드 칸 옆에 색 고르기(스포이드 포함) 버튼을 붙인다.
// data-color-picker 는 칸을 비워 뒀을 때 실제로 쓰이는 색.
const COLOR_CODE = /^#[0-9a-f]{6}$/i;

const attachColorPicker = (text: HTMLInputElement) => {
  const picker = document.createElement('input');
  picker.type = 'color';
  picker.className = 'color-picker';
  picker.title = text.placeholder;

  const showTextColor = () => {
    const value = text.value.trim();
    picker.value = (
      COLOR_CODE.test(value) ? value : (text.dataset.colorPicker ?? '#000000')
    ).toLowerCase();
  };

  picker.addEventListener('input', () => {
    text.value = picker.value;
    text.dispatchEvent(new Event('input', { bubbles: true }));
  });
  text.addEventListener('input', showTextColor);
  text.addEventListener('colorpicker:refresh', showTextColor);

  showTextColor();
  // simple_form 칸은 그 감싸개를, 표 칸 등은 새 감싸개를 쓴다
  let wrapper = text.parentElement;
  if (!wrapper?.classList.contains('label_input__wrapper')) {
    wrapper = document.createElement('div');
    text.replaceWith(wrapper);
    wrapper.append(text);
  }
  text.after(picker);
  wrapper.classList.add('label_input__wrapper--color');
};

// 캐릭터 명단: '전체 선택' 칸 (data-select-all 에 체크박스 이름)
Rails.delegate(document, 'input[data-select-all]', 'change', ({ target }) => {
  if (!(target instanceof HTMLInputElement)) return;
  const name = target.dataset.selectAll ?? '';
  target.form
    ?.querySelectorAll<HTMLInputElement>(`input[type="checkbox"][name="${name}"]`)
    .forEach((box) => {
      box.checked = target.checked;
    });
});

// 컨텐츠 설정: 문구 아래 명령어({계정명} 등)를 누르면 커서 자리에 넣는다
Rails.delegate(document, 'button.game-token', 'click', ({ target }) => {
  const button =
    target instanceof HTMLElement ? target.closest<HTMLButtonElement>('button.game-token') : null;
  const field = button?.dataset.target ? document.getElementById(button.dataset.target) : null;
  if (!button || !(field instanceof HTMLTextAreaElement)) return;

  const token = button.dataset.insert ?? '';
  const start = field.selectionStart;
  const end = field.selectionEnd;
  field.setRangeText(token, start, end, 'end');
  field.focus();
  field.dispatchEvent(new Event('input', { bubbles: true }));
});

// 캐릭터 관리 > 스탯: 유형(스탯/상태 수치)에 따라 최소·최대치 칸 또는 수식 칸만 보인다
const syncStatParts = (select: HTMLSelectElement) => {
  select
    .closest('[data-stat-form]')
    ?.querySelectorAll<HTMLElement>('[data-stat-part]')
    .forEach((part) => {
      part.hidden = part.dataset.statPart !== select.value;
    });
};

Rails.delegate(document, 'select[data-stat-type]', 'change', ({ target }) => {
  if (target instanceof HTMLSelectElement) syncStatParts(target);
});

// 입력창 모달 (admin/ui/_modal): data-modal-open="id" 버튼으로 열고, X·바깥 클릭·Esc 로 닫는다
Rails.delegate(document, '[data-modal-open]', 'click', ({ target }) => {
  if (!(target instanceof Element)) return;

  const id = target
    .closest<HTMLElement>('[data-modal-open]')
    ?.getAttribute('data-modal-open');
  const dialog = id ? document.getElementById(id) : null;

  if (dialog instanceof HTMLDialogElement) {
    dialog.showModal();
    dialog
      .querySelector<HTMLElement>('input:not([type=hidden]), select, textarea')
      ?.focus();
  }
});

Rails.delegate(document, '[data-modal-close]', 'click', ({ target }) => {
  if (target instanceof Element) target.closest('dialog')?.close();
});

// 상자 바깥(어두운 배경)을 누르면 닫는다. 안에서 끌다가 바깥에서 놓은 건 무시
let modalPressTarget: EventTarget | null = null;

document.addEventListener('mousedown', ({ target }) => {
  modalPressTarget = target;
});

document.addEventListener('click', ({ target }) => {
  if (
    target instanceof HTMLDialogElement &&
    target.classList.contains('game-modal') &&
    modalPressTarget === target
  )
    target.close();
});

// 캐릭터 명단: 줄 아무 곳이나 누르면 상세 화면 (링크·버튼·체크박스를 누른 건 그대로)
Rails.delegate(document, 'tr[data-href]', 'click', ({ target }) => {
  if (!(target instanceof Element) || target.closest('a, button, input, label, select, .ct-select-popout'))
    return;

  const href = target.closest<HTMLElement>('tr[data-href]')?.dataset.href;
  if (href) window.location.assign(href);
});

// 여러 개 고르는 드롭다운 (admin/ui/_multi_select): 고른 이름을 요약에 보이고, 바깥을 누르면 닫는다
const syncMultiSelect = (box: HTMLElement) => {
  const label = box.querySelector('.game-multi__label');
  if (!label) return;

  const names = Array.from(
    box.querySelectorAll<HTMLInputElement>('input[type="checkbox"][data-label]:checked'),
  ).map((input) => input.dataset.label ?? '');
  label.textContent =
    names.length === 0
      ? (box.dataset.placeholder ?? '')
      : names.length <= 3
        ? names.join(', ')
        : `${names.slice(0, 3).join(', ')} 외 ${names.length - 3}`;
};

document.addEventListener('change', ({ target }) => {
  const box =
    target instanceof Element &&
    target.closest<HTMLElement>('[data-multi-select]');
  if (box) syncMultiSelect(box);
});

// 팝오버 (admin/ui: multi_select · item_picker 의 details[data-popover] > .ui-popover):
// 화면 기준 고정 위치로 띄워 모달·표에 잘리지 않게 하고, 아래 공간이 모자라면 위로 띄운다. 바깥을 누르면 닫는다.
const placePopover = (details: HTMLDetailsElement) => {
  const popover = details.querySelector<HTMLElement>(':scope > .ui-popover');
  const anchor = details.querySelector<HTMLElement>(':scope > summary');
  if (!popover || !anchor) return;

  const rect = anchor.getBoundingClientRect();
  popover.style.position = 'fixed';
  popover.style.minWidth = `${rect.width}px`;
  popover.style.maxHeight = '';
  const below = window.innerHeight - rect.bottom - 8;
  const above = rect.top - 8;
  const up = popover.offsetHeight > below && above > below;
  const room = up ? above : below;
  if (popover.offsetHeight > room) popover.style.maxHeight = `${Math.max(room, 120)}px`;
  const height = popover.offsetHeight;
  popover.style.top = `${up ? rect.top - height - 4 : rect.bottom + 4}px`;
  popover.style.left = `${Math.max(8, Math.min(rect.left, window.innerWidth - popover.offsetWidth - 8))}px`;
};

const openPopovers = () =>
  document.querySelectorAll<HTMLDetailsElement>('details[data-popover][open]');

document.addEventListener(
  'toggle',
  ({ target }) => {
    if (target instanceof HTMLDetailsElement && target.matches('[data-popover]') && target.open) placePopover(target);
  },
  true,
);

document.addEventListener(
  'scroll',
  () => {
    openPopovers().forEach(placePopover);
  },
  true,
);

window.addEventListener('resize', () => {
  openPopovers().forEach(placePopover);
});

document.addEventListener('click', ({ target }) => {
  openPopovers().forEach((box) => {
    if (!(target instanceof Node) || !box.contains(target)) box.open = false;
  });
});

// 아이템 고르기 (admin/ui/_item_picker): 목록에서 고르면 카드가 붙고(같은 아이템이면 개수 +1), × 로 뺀다
Rails.delegate(document, '[data-item-pick]', 'click', ({ target }) => {
  if (!(target instanceof Element)) return;

  const option = target.closest<HTMLElement>('[data-item-pick]');
  const picker = option?.closest<HTMLElement>('[data-item-picker]');
  const add = picker?.querySelector<HTMLDetailsElement>('.ui-item-picker__add');
  const name = option?.dataset.itemPick;
  if (!option || !picker || !add || !name) return;

  add.open = false;
  addItemCard(picker, name);
  picker.querySelectorAll<HTMLElement>('.ui-item-picker__card').forEach((card) => {
    if (card.querySelector<HTMLInputElement>('input[type="hidden"]')?.value === name) card.querySelector<HTMLInputElement>('.ui-item-picker__count')?.select();
  });
  picker.dispatchEvent(new Event('change', { bubbles: true }));
});

// 목록 위 검색칸: 이름에 들어 있는 글자로 거른다. 목록을 열면 검색칸에 바로 쓸 수 있게
Rails.delegate(document, 'input[data-item-search]', 'input', ({ target }) => {
  if (target instanceof HTMLInputElement) filterItemOptions(target);
});

document.addEventListener(
  'toggle',
  ({ target }) => {
    if (!(target instanceof HTMLDetailsElement) || !target.matches('.ui-item-picker__add') || !target.open) return;

    const search = target.querySelector<HTMLInputElement>('input[data-item-search]');
    if (!search) return;
    search.value = '';
    filterItemOptions(search);
    search.focus();
  },
  true,
);

Rails.delegate(document, '.ui-item-picker__remove', 'click', ({ target }) => {
  if (!(target instanceof Element)) return;

  const picker = target.closest<HTMLElement>('[data-item-picker]');
  target.closest('.ui-item-picker__card')?.remove();
  picker?.dispatchEvent(new Event('change', { bubbles: true }));
});


// 지급 모달: 재화 / 아이템에 맞는 칸만
Rails.delegate(document, 'input[data-give-kind]', 'change', ({ target }) => {
  if (!(target instanceof HTMLInputElement)) return;

  target
    .closest('[data-give-form]')
    ?.querySelectorAll<HTMLElement>('[data-give-part]')
    .forEach((part) => {
      part.hidden = part.dataset.givePart !== target.value;
    });
});

ready(() => {
  document
    .querySelectorAll<HTMLSelectElement>('select[data-stat-type]')
    .forEach(syncStatParts);

  // 여러 개 고르기: 처음부터 골라 둔 것(selected)을 요약 칸에
  document.querySelectorAll<HTMLElement>('[data-multi-select]').forEach(syncMultiSelect);

  // 저장하다 오류가 난 모달은 다시 열어 둔다 (data-modal-reopen)
  document
    .querySelectorAll<HTMLDialogElement>('dialog.game-modal[data-modal-reopen]')
    .forEach((dialog) => {
      dialog.showModal();
    });

  document
    .querySelectorAll<HTMLInputElement>('input[data-color-picker]')
    .forEach(attachColorPicker);
  setupCommunityThemeEditor();
  setupGameConfigEditor();
  setupStatsEditor();
  setupCommunitySelect();
  setupCommunityCombobox();
  setupInlineSelects();
  setupDateInputs();

  const domainBlockSeveritySelect = document.querySelector<HTMLSelectElement>(
    'select#domain_block_severity',
  );
  if (domainBlockSeveritySelect)
    onDomainBlockSeverityChange(domainBlockSeveritySelect);

  const enableBootstrapTimelineAccounts =
    document.querySelector<HTMLInputElement>(
      'input#form_admin_settings_enable_bootstrap_timeline_accounts',
    );
  if (enableBootstrapTimelineAccounts)
    onEnableBootstrapTimelineAccountsChange(enableBootstrapTimelineAccounts);

  const registrationMode = document.querySelector<HTMLSelectElement>(
    'select#form_admin_settings_registrations_mode',
  );
  if (registrationMode) onChangeRegistrationMode(registrationMode);

  const checkAllElement = document.querySelector<HTMLInputElement>(
    'input#batch_checkbox_all',
  );
  if (checkAllElement) {
    const allCheckboxes = Array.from(
      document.querySelectorAll<HTMLInputElement>(batchCheckboxClassName),
    );
    checkAllElement.checked = allCheckboxes.every((content) => content.checked);
    checkAllElement.indeterminate =
      !checkAllElement.checked &&
      allCheckboxes.some((content) => content.checked);
  }

  document
    .querySelector('a#add-instance-button')
    ?.addEventListener('click', (e) => {
      const domain = document.querySelector<HTMLInputElement>(
        'input[type="text"]#by_domain',
      )?.value;

      if (domain && e.target instanceof HTMLAnchorElement) {
        const url = new URL(e.target.href);
        url.searchParams.set('_domain', domain);
        e.target.href = url.toString();
      }
    });

  document
    .querySelectorAll<HTMLInputElement>('input[type="datetime-local"]')
    .forEach((element) => {
      if (element.value) {
        element.value = convertUTCDateTimeToLocal(element.value);
      }
      if (element.placeholder) {
        element.placeholder = convertUTCDateTimeToLocal(element.placeholder);
      }
    });

  Rails.delegate(document, 'form', 'submit', ({ target }) => {
    if (target instanceof HTMLFormElement)
      target
        .querySelectorAll<HTMLInputElement>('input[type="datetime-local"]')
        .forEach((element) => {
          if (element.value && element.validity.valid) {
            element.value = convertLocalDatetimeToUTC(element.value);
          }
        });
  });

  const announcementStartsAt = document.querySelector<HTMLInputElement>(
    'input[type="datetime-local"]#announcement_starts_at',
  );
  if (announcementStartsAt) {
    setAnnouncementEndsAttributes(announcementStartsAt);
  }

  document.querySelectorAll('[data-admin-component]').forEach((element) => {
    void mountReactComponent(element);
  });
}).catch((reason: unknown) => {
  throw reason;
});
