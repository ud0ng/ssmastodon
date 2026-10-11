// 커뮤니티 테마 (낮/밤) 스타일시트에서 고정된 파란색(#1d9bf0, Bird UI 포인트색)을
// 서브색 변수로 바꾼다. 기본 스타일 곳곳에 파란색과 그 변형(진하게·연하게·반투명)이
// 수백 군데 박혀 있어서, 하나씩 덮어쓰는 대신 빌드할 때 바꾼다.
//
//   #1d9bf0                → var(--ct-point, #1d9bf0)
//   rgba(29, 155, 240, .5) → color-mix(in srgb, var(--ct-point, #1d9bf0) 50%, transparent)
//   진한/연한 파란색       → 서브색에 검정/흰색을 섞은 색
//
// --ct-point 가 없는 곳(관리자 화면 등)은 원래 파란색 그대로다.
// 다른 테마(유사 트위터 등)는 건드리지 않는다.
import type { Plugin } from 'postcss';

const COMMUNITY_THEME_FILE = /styles[\\/]community-(light|dark)\.scss$/;
const POINT = 'var(--ct-point, #1d9bf0)';
const BASE = { r: 29, g: 155, b: 240 };

// #rrggbb, #rgb, rgb()/rgba(), hsl()/hsla() (소수, 쉼표/공백 문법 모두).
// Sass 가 진하게/연하게 만든 색은 소수 rgb 나 hsl 로 나온다 (압축할 때 hex 가 된다).
const NUM = '-?[\\d.]+';
const SEP = '\\s*[,\\s]\\s*';
const COLOR = new RegExp(
  `#(?:[0-9a-f]{6}|[0-9a-f]{3})\\b|(rgba?|hsla?)\\(\\s*(${NUM})(?:deg)?${SEP}(${NUM}%?)${SEP}(${NUM}%?)(?:\\s*[,/]\\s*(${NUM}%?))?\\s*\\)`,
  'gi',
);

interface Rgb {
  r: number;
  g: number;
  b: number;
}

const toHsl = ({ r, g, b }: Rgb) => {
  const [rr, gg, bb] = [r / 255, g / 255, b / 255];
  const max = Math.max(rr, gg, bb);
  const min = Math.min(rr, gg, bb);
  const delta = max - min;
  const lightness = (max + min) / 2;
  if (delta === 0) return { hue: 0, saturation: 0, lightness };

  const saturation =
    lightness > 0.5 ? delta / (2 - max - min) : delta / (max + min);
  let hue =
    max === rr
      ? ((gg - bb) / delta) % 6
      : max === gg
        ? (bb - rr) / delta + 2
        : (rr - gg) / delta + 4;
  hue = (hue * 60 + 360) % 360;
  return { hue, saturation, lightness };
};

const fromHsl = (hue: number, saturation: number, lightness: number): Rgb => {
  const chroma = (1 - Math.abs(2 * lightness - 1)) * saturation;
  const x = chroma * (1 - Math.abs(((hue / 60) % 2) - 1));
  const m = lightness - chroma / 2;
  const sectors: [number, number, number][] = [
    [chroma, x, 0],
    [x, chroma, 0],
    [0, chroma, x],
    [0, x, chroma],
    [x, 0, chroma],
    [chroma, 0, x],
  ];
  const [r, g, b] = sectors[Math.floor(hue / 60) % 6] ?? [0, 0, 0];
  return { r: (r + m) * 255, g: (g + m) * 255, b: (b + m) * 255 };
};

const BASE_LIGHTNESS = toHsl(BASE).lightness;

const parseHex = (hex: string): Rgb => {
  const digits =
    hex.length === 4
      ? hex
          .slice(1)
          .split('')
          .map((d) => d + d)
          .join('')
      : hex.slice(1);
  return {
    r: parseInt(digits.slice(0, 2), 16),
    g: parseInt(digits.slice(2, 4), 16),
    b: parseInt(digits.slice(4, 6), 16),
  };
};

const isPointBlue = (color: Rgb) => {
  const { hue, saturation } = toHsl(color);
  return hue > 195 && hue < 215 && saturation > 0.6;
};

const round = (value: number) => Math.round(value * 10) / 10;

// 파란색 변형 → 서브색 기준 색
const pointShade = (color: Rgb) => {
  const { lightness } = toHsl(color);
  if (Math.abs(lightness - BASE_LIGHTNESS) < 0.01) return POINT;
  if (lightness < BASE_LIGHTNESS)
    return `color-mix(in srgb, ${POINT} ${round((lightness / BASE_LIGHTNESS) * 100)}%, #000)`;
  return `color-mix(in srgb, ${POINT} ${round(((1 - lightness) / (1 - BASE_LIGHTNESS)) * 100)}%, #fff)`;
};

const withAlpha = (color: string, alpha: string | undefined) => {
  if (alpha === undefined) return color;

  const percent = alpha.endsWith('%')
    ? parseFloat(alpha)
    : parseFloat(alpha) * 100;
  if (percent >= 100) return color;
  return `color-mix(in srgb, ${color} ${round(percent)}%, transparent)`;
};

const parseColor = (
  match: string,
  kind: string | undefined,
  first: string | undefined,
  second: string | undefined,
  third: string | undefined,
): Rgb | null => {
  if (match.startsWith('#')) return parseHex(match);
  if (kind?.toLowerCase().startsWith('hsl'))
    return fromHsl(
      ((Number(first) % 360) + 360) % 360,
      parseFloat(second ?? '0') / 100,
      parseFloat(third ?? '0') / 100,
    );
  if ([first, second, third].some((v) => v?.endsWith('%'))) return null;
  return { r: Number(first), g: Number(second), b: Number(third) };
};

export const replacePointBlue = (value: string) =>
  value.replace(
    COLOR,
    (
      match: string,
      kind?: string,
      first?: string,
      second?: string,
      third?: string,
      alpha?: string,
    ) => {
      const color = parseColor(match, kind, first, second, third);
      if (!color || !isPointBlue(color)) return match;

      return withAlpha(pointShade(color), alpha);
    },
  );

export const communityThemeColors = (): Plugin => ({
  postcssPlugin: 'community-theme-colors',
  Once(root, { result }) {
    const file = root.source?.input.file ?? result.opts.from ?? '';
    if (!COMMUNITY_THEME_FILE.test(file)) return;

    root.walkDecls((decl) => {
      // data: URL 안의 색(아이콘 SVG)은 변수를 쓸 수 없으니 그대로 둔다
      if (decl.value.includes('url(')) return;

      decl.value = replacePointBlue(decl.value);
    });
  },
});
