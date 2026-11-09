import { TdObject } from '../tdkit/TdTypes';
import { fillColorsOf, intToHexColor } from './backgroundPresentation';

// Renderable summary of one official chat theme (TDLib chatTheme object) for
// the theme picker: background fill colors, outgoing-bubble fill and accent.
export interface ChatThemePreview {
  name: string;
  backgroundColors: string[];
  bubbleColors: string[];
  accent: string;
}

function objectOrNull(value: Object | undefined): TdObject | null {
  return value !== undefined && typeof value === 'object' ? value as TdObject : null;
}

export function chatThemePreviewOf(theme: TdObject, forDark: boolean): ChatThemePreview | null {
  const name = (theme['name'] as string | undefined) ?? '';
  if (name === '') { return null; }
  const settings = objectOrNull(theme[forDark ? 'dark_settings' : 'light_settings']);
  const background = settings !== null ? objectOrNull(settings['background']) : null;
  const backgroundType = background !== null ? objectOrNull(background['type']) : null;
  const backgroundFill = backgroundType !== null ? objectOrNull(backgroundType['fill']) : null;
  const bubbleFill = settings !== null ? objectOrNull(settings['outgoing_message_fill']) : null;
  const accent = settings !== null ? ((settings['accent_color'] as number | undefined) ?? 0) : 0;
  return {
    name,
    backgroundColors: fillColorsOf(backgroundFill),
    bubbleColors: fillColorsOf(bubbleFill),
    accent: intToHexColor(accent)
  };
}
