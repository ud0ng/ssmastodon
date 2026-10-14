// 서버 설정 > 커뮤니티 테마: 색을 바꾸면 미리보기(낮/밤)를 바로 다시 칠한다.
// 자동 색 계산은 app/lib/community_theme.rb 와 같다 (빈 칸 → 메인/서브색으로 자동).

type Rgb = [number, number, number];
type Mode = 'light' | 'dark';
type Palette = Record<string, string>;

const MODES: Mode[] = ['light', 'dark'];
const COLOR_FORMAT = /^#[0-9a-f]{6}$/i;
const DEFAULT_BOX_OPACITY = 92;

const color = (value: string | undefined) =>
  value && COLOR_FORMAT.test(value.trim()) ? value.trim().toLowerCase() : null;

const rgb = (hex: string): Rgb => [
  parseInt(hex.slice(1, 3), 16),
  parseInt(hex.slice(3, 5), 16),
  parseInt(hex.slice(5, 7), 16),
];

const toHex = (channels: number[]) =>
  `#${channels
    .map((channel) =>
      Math.round(Math.min(255, Math.max(0, channel)))
        .toString(16)
        .padStart(2, '0'),
    )
    .join('')}`;

// a 를 percent% 섞는다 (CSS color-mix(in srgb, a percent%, b) 와 같다)
const mix = (first: string, percent: number, second: string) => {
  const weight = percent / 100;
  const a = rgb(first);
  const b = rgb(second);
  return toHex(a.map((value, index) => value * weight + (b[index] ?? 0) * (1 - weight)));
};

// 채도는 그대로 두고 밝기만 올린다
const lighten = (hex: string, amount = 0.3) => {
  const [r, g, b] = rgb(hex).map((channel) => channel / 255) as Rgb;
  const max = Math.max(r, g, b);
  const min = Math.min(r, g, b);
  const delta = max - min;
  let lightness = (max + min) / 2;
  let hue = 0;
  let saturation = 0;

  if (delta !== 0) {
    saturation =
      lightness > 0.5 ? delta / (2 - max - min) : delta / (max + min);
    if (max === r) hue = ((g - b) / delta) % 6;
    else if (max === g) hue = (b - r) / delta + 2;
    else hue = (r - g) / delta + 4;
    hue /= 6;
    if (hue < 0) hue += 1;
  }

  lightness += (1 - lightness) * amount;

  const chroma = (1 - Math.abs(2 * lightness - 1)) * saturation;
  const x = chroma * (1 - Math.abs(((hue * 6) % 2) - 1));
  const m = lightness - chroma / 2;
  const sectors: Rgb[] = [
    [chroma, x, 0],
    [x, chroma, 0],
    [0, chroma, x],
    [0, x, chroma],
    [x, 0, chroma],
    [chroma, 0, x],
  ];
  const sector = sectors[Math.floor(hue * 6) % 6] ?? [0, 0, 0];
  return toHex(sector.map((channel) => (channel + m) * 255));
};

// 흰 글자가 충분히 읽히면(대비 3:1 이상) 흰색, 아니면 검은색
const onColor = (hex: string) => {
  const [r, g, b] = rgb(hex).map((channel) => {
    const value = channel / 255;
    return value <= 0.03928 ? value / 12.92 : ((value + 0.055) / 1.055) ** 2.4;
  }) as Rgb;
  const luminance = 0.2126 * r + 0.7152 * g + 0.0722 * b;
  return 1.05 / (luminance + 0.05) >= 3 ? '#ffffff' : '#14161a';
};

class Editor {
  private root: HTMLElement;
  private form: HTMLFormElement;
  private defaultColor: string;

  constructor(root: HTMLElement) {
    this.root = root;
    this.form = root.closest('form') ?? (document.forms[0] as HTMLFormElement);
    this.defaultColor = root.dataset.defaultColor ?? '#4a5390';
  }

  private input(key: string) {
    return this.form.querySelector<HTMLInputElement>(
      `[name="form_admin_settings[community_theme_${key}]"]:not([type="hidden"])`,
    );
  }

  private value(key: string) {
    return this.input(key)?.value ?? '';
  }

  private postButtonMain() {
    return Boolean(this.input('post_button_main')?.checked);
  }

  private baseColors() {
    const mainLight = color(this.value('main_light')) ?? this.defaultColor;
    const pointLight = color(this.value('point_light')) ?? mainLight;
    const mainDark = color(this.value('main_dark'));
    const pointDark =
      color(this.value('point_dark')) ?? lighten(mainDark ?? pointLight);

    return {
      light: [mainLight, pointLight],
      dark: [mainDark ?? mainLight, pointDark],
    } as Record<Mode, [string, string]>;
  }

  autoPalette(mode: Mode): Palette {
    const [main, point] = this.baseColors()[mode];
    let colors: Palette;

    if (mode === 'dark') {
      const box = mix(main, 28, '#0a0b10');
      const text = mix(main, 6, '#f4f5f8');
      colors = {
        page: box,
        box,
        compose: mix(main, 36, '#0d0e14'),
        selected: mix(main, 45, '#121318'),
        hover: mix('#ffffff', 6, box),
        border: mix(mix(main, 40, '#ffffff'), 16, box),
        text,
        nav: mix(main, 12, '#ffffff'),
        dim: mix(main, 40, '#b9bcc8'),
        dim_hover: text,
      };
    } else {
      const box = mix(main, 5, '#ffffff');
      const nav = mix(main, 80, '#14161a');
      colors = {
        page: box,
        box,
        compose: box,
        selected: mix(main, 10, '#ffffff'),
        hover: mix(mix(main, 8, '#14161a'), 5, box),
        border: mix(main, 22, '#ffffff'),
        text: mix(main, 8, '#14161a'),
        nav,
        dim: mix(main, 50, '#ffffff'),
        dim_hover: nav,
      };
    }

    colors.main = main;
    colors.point = point;
    colors.on_point = onColor(point);
    colors.nav_hover = point;
    colors.bracket = colors.text ?? point;
    colors.paren = colors.text ?? point;
    colors.link_hover =
      mode === 'dark' ? mix(point, 75, '#ffffff') : mix(point, 75, '#000000');
    colors.post_button = this.postButtonMain() ? (colors.nav ?? point) : point;
    colors.post_button_text = onColor(colors.post_button);
    // 채팅: 보낸 말풍선 = 서브색, 받은 말풍선·입력창 = 고른 항목, 버튼 = 게시 버튼 (community_theme.rb 와 같게)
    colors.dm_sent = point;
    colors.dm_sent_text = colors.on_point;
    colors.dm_received = colors.selected ?? point;
    colors.dm_received_text = colors.text ?? point;
    colors.dm_input = colors.selected ?? point;
    colors.dm_button = colors.post_button;
    colors.dm_button_text = colors.post_button_text;
    return colors;
  }

  palette(mode: Mode) {
    const auto = this.autoPalette(mode);
    const colors: Palette = { ...auto };
    Object.keys(auto).forEach((item) => {
      if (item === 'main' || item === 'point') return;
      const override = color(this.value(`${item}_${mode}`));
      if (override) colors[item] = override;
    });

    // 정하지 않은 호버 배경은 반투명 (실제 화면과 같게)
    if (!color(this.value(`hover_${mode}`)))
      colors.hover =
        mode === 'dark'
          ? 'color-mix(in srgb, #fff 6%, transparent)'
          : `color-mix(in srgb, ${colors.text} 5%, transparent)`;

    const parenSize = parseInt(this.value('paren_size'), 10);
    colors.paren_size = `${Number.isNaN(parenSize) ? 100 : Math.min(150, Math.max(50, parenSize))}%`;

    const opacity = parseInt(this.value(`box_opacity_${mode}`), 10);
    colors.opacity = `${Number.isNaN(opacity) ? DEFAULT_BOX_OPACITY : Math.min(100, Math.max(0, opacity))}%`;
    return { auto, colors };
  }

  render() {
    MODES.forEach((mode) => {
      const { auto, colors } = this.palette(mode);

      const screen = this.root.querySelector<HTMLElement>(
        `[data-preview-mode="${mode}"]`,
      );
      if (screen)
        Object.entries(colors).forEach(([item, value]) => {
          screen.style.setProperty(`--pv-${item.replace(/_/g, '-')}`, value);
        });

      // 빈 칸의 흐린 값과 색 버튼을 지금 자동 색으로
      Object.entries(auto).forEach(([item, value]) => {
        const field = this.input(`${item}_${mode}`);
        if (!field || item === 'main' || item === 'point') return;
        field.placeholder = value;
        field.dataset.colorPicker = value;
        field.dispatchEvent(new Event('colorpicker:refresh'));
      });
      (['main', 'point'] as const).forEach((item) => {
        const field = this.input(`${item}_${mode}`);
        if (!field) return;
        field.dataset.colorPicker = auto[item];
        field.dispatchEvent(new Event('colorpicker:refresh'));
      });
    });
  }

  // 배경 이미지를 고르면 미리보기에도 바로
  showBackground(mode: Mode, url: string | null) {
    const screen = this.root.querySelector<HTMLElement>(
      `[data-preview-mode="${mode}"]`,
    );
    if (!screen) return;
    if (url) screen.style.setProperty('--pv-background', `url("${url}")`);
    else screen.style.removeProperty('--pv-background');
  }

  bind() {
    this.form.addEventListener('input', () => {
      this.render();
    });
    this.form.addEventListener('change', (event) => {
      const target = event.target;
      if (
        target instanceof HTMLInputElement &&
        target.type === 'file' &&
        target.name.includes('community_theme_background_')
      ) {
        const mode: Mode = target.name.includes('_dark') ? 'dark' : 'light';
        const file = target.files?.[0];
        if (file) this.showBackground(mode, URL.createObjectURL(file));
      }
      this.render();
    });

    // 낮/밤 미리보기 각각에서 '호버' 같은 상태를 보여 주는 칸을 누르면 그 항목 칸으로 이동
    this.root.addEventListener('click', (event) => {
      const target = (event.target as HTMLElement).closest<HTMLElement>(
        '[data-preview-item]',
      );
      const screen = target?.closest<HTMLElement>('[data-preview-mode]');
      if (!target || !screen) return;
      event.preventDefault();
      const field = this.input(
        `${target.dataset.previewItem}_${screen.dataset.previewMode}`,
      );
      if (!field) return;
      field.scrollIntoView({ behavior: 'smooth', block: 'center' });
      field.focus({ preventScroll: true });
      const row = field.closest('tr');
      row?.classList.add('community-theme-table__row--flash');
      window.setTimeout(() => {
        row?.classList.remove('community-theme-table__row--flash');
      }, 1200);
    });

    this.render();
  }
}

export const setupCommunityThemeEditor = () => {
  const root = document.querySelector<HTMLElement>('[data-community-theme-editor]');
  if (root) new Editor(root).bind();
};
