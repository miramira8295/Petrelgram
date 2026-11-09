// 取色器与气泡文字色用的纯函数。没有任何 ArkUI 依赖，单测直接跑。

const HEX_RE: RegExp = /^#[0-9a-fA-F]{6}$/;

export function isValidHex(s: string): boolean {
  return HEX_RE.test(s);
}

// 官方取色器回的可能是 #AARRGGBB；统一成大写 #RRGGBB，认不出返回空串。
const ARGB_RE: RegExp = /^#[0-9a-fA-F]{8}$/;

export function toRgbHex(s: string): string {
  const t = s.trim();
  if (isValidHex(t)) {
    return t.toUpperCase();
  }
  if (ARGB_RE.test(t)) {
    return `#${t.substring(3).toUpperCase()}`;
  }
  return '';
}

function channel(v: number): string {
  const n = Math.max(0, Math.min(255, Math.round(v)));
  return (n < 16 ? '0' : '') + n.toString(16).toUpperCase();
}

export function hsvToHex(h: number, s: number, v: number): string {
  const hh = ((h % 360) + 360) % 360 / 60;
  const c = v * s;
  const x = c * (1 - Math.abs((hh % 2) - 1));
  const m = v - c;
  let r = 0;
  let g = 0;
  let b = 0;
  if (hh < 1) {
    r = c; g = x;
  } else if (hh < 2) {
    r = x; g = c;
  } else if (hh < 3) {
    g = c; b = x;
  } else if (hh < 4) {
    g = x; b = c;
  } else if (hh < 5) {
    r = x; b = c;
  } else {
    r = c; b = x;
  }
  return `#${channel((r + m) * 255)}${channel((g + m) * 255)}${channel((b + m) * 255)}`;
}

function rgbOf(hex: string): number[] {
  const n = parseInt(hex.substring(1), 16);
  return [(n >> 16) & 0xFF, (n >> 8) & 0xFF, n & 0xFF];
}

// 返回 [h 0–360, s 0–1, v 0–1]
export function hexToHsv(hex: string): number[] {
  const rgb = rgbOf(hex);
  const r = rgb[0] / 255;
  const g = rgb[1] / 255;
  const b = rgb[2] / 255;
  const max = Math.max(r, g, b);
  const min = Math.min(r, g, b);
  const d = max - min;
  let h = 0;
  if (d > 0) {
    if (max === r) {
      h = 60 * (((g - b) / d) % 6);
    } else if (max === g) {
      h = 60 * ((b - r) / d + 2);
    } else {
      h = 60 * ((r - g) / d + 4);
    }
  }
  return [(h + 360) % 360, max === 0 ? 0 : d / max, max];
}

function linear(c: number): number {
  const v = c / 255;
  return v <= 0.03928 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4);
}

// WCAG 相对亮度，0（黑）–1（白）。
export function relativeLuminance(hex: string): number {
  const rgb = rgbOf(hex);
  return 0.2126 * linear(rgb[0]) + 0.7152 * linear(rgb[1]) + 0.0722 * linear(rgb[2]);
}

// 压在这个底色上的文字用黑还是白。
export function textOn(hex: string): string {
  return relativeLuminance(hex) >= 0.5 ? '#000000' : '#FFFFFF';
}
