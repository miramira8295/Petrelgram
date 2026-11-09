import { TdObject } from '../tdkit/TdTypes';
import { intToHexColor } from './backgroundPresentation';

// Accent color ids 0–6 are Telegram's built-in single-color name palette that
// every client hardcodes; ids 7+ arrive with explicit color lists via the
// updateAccentColors push.
// Name colours for the seven built-in accent ids (red, orange, violet, green,
// cyan, blue, pink). TDLib sends no colour values for these — official clients
// carry them — and they are NOT the avatar palette: that one is lighter and
// made the names read as pastel next to the official apps.
const BUILTIN_NAME_LIGHT: string[] = [
  '#CC5049', '#D67722', '#955CDB', '#40A920', '#309EBA', '#368AD1', '#C7508B'
];
const BUILTIN_NAME_DARK: string[] = [
  '#FF8E86', '#FFA95A', '#B18FFF', '#6FD36F', '#5CC5E0', '#68B5FF', '#FF7FB5'
];

export interface AccentPreview {
  id: number;
  colors: string[];
}

export function builtinAccentColor(id: number, forDark: boolean = false): string {
  const palette = forDark ? BUILTIN_NAME_DARK : BUILTIN_NAME_LIGHT;
  return palette[((id % palette.length) + palette.length) % palette.length];
}

function objectOrNull(value: Object | undefined): TdObject | null {
  return value !== undefined && typeof value === 'object' ? value as TdObject : null;
}

function hexListOf(values: number[] | undefined): string[] {
  return (values ?? []).map((color: number): string => intToHexColor(color));
}

export function accentPreviewOf(accent: TdObject, forDark: boolean): AccentPreview | null {
  const id = (accent['id'] as number | undefined) ?? -1;
  if (id < 0) { return null; }
  const colors = hexListOf(
    accent[forDark ? 'dark_theme_colors' : 'light_theme_colors'] as number[] | undefined
  );
  if (colors.length > 0) {
    return { id, colors };
  }
  const builtin = (accent['built_in_accent_color_id'] as number | undefined) ?? id;
  return { id, colors: [builtinAccentColor(builtin, forDark)] };
}

export function profileAccentPreviewOf(
  accent: TdObject, forDark: boolean
): AccentPreview | null {
  const id = (accent['id'] as number | undefined) ?? -1;
  if (id < 0) { return null; }
  const palette = objectOrNull(accent[forDark ? 'dark_theme_colors' : 'light_theme_colors']);
  if (palette === null) { return null; }
  const background = hexListOf(palette['background_colors'] as number[] | undefined);
  const fallback = hexListOf(palette['palette_colors'] as number[] | undefined);
  const colors = background.length > 0 ? background : fallback;
  return colors.length > 0 ? { id, colors } : null;
}
