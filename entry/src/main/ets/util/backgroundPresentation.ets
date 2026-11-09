import { TdObject } from '../tdkit/TdTypes';

// Pure mapping from TDLib background objects to what the wallpaper picker can
// render natively (solid / gradient / freeform fills, plus the fill layer
// under patterns). Photo wallpapers surface as kind 'wallpaper' with no
// colors — the picker needs the document file for those.
export interface BackgroundPreview {
  backgroundId: string;
  name: string;
  kind: string; // 'fill' | 'pattern' | 'wallpaper'
  colors: string[];
  angle: number;
  isDark: boolean;
}

export function intToHexColor(value: number): string {
  const clamped = Math.max(0, Math.min(0xFFFFFF, Math.round(value)));
  return `#${clamped.toString(16).toUpperCase().padStart(6, '0')}`;
}

export function fillColorsOf(fill: TdObject | null): string[] {
  if (fill === null) { return []; }
  const typeName = (fill['@type'] as string | undefined) ?? '';
  if (typeName === 'backgroundFillSolid') {
    return [intToHexColor((fill['color'] as number | undefined) ?? 0)];
  }
  if (typeName === 'backgroundFillGradient') {
    return [
      intToHexColor((fill['top_color'] as number | undefined) ?? 0),
      intToHexColor((fill['bottom_color'] as number | undefined) ?? 0)
    ];
  }
  if (typeName === 'backgroundFillFreeformGradient') {
    return ((fill['colors'] as number[] | undefined) ?? [])
      .map((color: number): string => intToHexColor(color));
  }
  return [];
}

// Linear-gradient stops for a fill's colors, evenly spaced over [0, 1].
// A single color still needs two stops — ArkUI's linearGradient renders nothing
// from one — so it is emitted at both ends.
export function gradientStops(colors: string[]): Array<[string, number]> {
  const result: Array<[string, number]> = [];
  if (colors.length === 0) {
    return result;
  }
  if (colors.length === 1) {
    result.push([colors[0], 0]);
    result.push([colors[0], 1]);
    return result;
  }
  const last: number = colors.length - 1;
  colors.forEach((color: string, index: number): void => {
    result.push([color, index / last]);
  });
  return result;
}

// Widened to accept null as well as undefined: TDLib field reads yield either,
// and a narrower parameter makes ArkTS treat the indexed access as `any`.
export function objectOrNull(value: Object | null | undefined): TdObject | null {
  return value !== undefined && value !== null && typeof value === 'object'
    ? value as TdObject : null;
}

// The small preview image TDLib attaches to photo/pattern wallpapers.
export function backgroundThumbnailFile(background: TdObject): TdObject | null {
  const document = objectOrNull(background['document']);
  if (document === null) { return null; }
  const thumbnail = objectOrNull(document['thumbnail']);
  if (thumbnail === null) { return null; }
  return objectOrNull(thumbnail['file']);
}

// 图案壁纸的「底」：TDLib 对一部分 pattern 背景给的是 backgroundFillSolid +
// color=0，fillColorsOf 如实翻成 #000000。这层填充只是**垫在图案下面**的底色，
// 真正的观感来自 pattern 文档本身（网格瓦片现在会把它叠上去）。
//
// 2026-11-06 结论（用户确认）：这些 pattern **本来就是黑色壁纸**，底色就该是黑的。
// 曾经在这里加过「纯黑填充 → 中性灰 #8C9096」的显示回退，属于误判，已整体删除；
// 不要再用中性色去"修正"它。
export function backgroundPreviewOf(background: TdObject): BackgroundPreview | null {
  const type = objectOrNull(background['type']);
  if (type === null) { return null; }
  const typeName = (type['@type'] as string | undefined) ?? '';
  let kind = '';
  let fill: TdObject | null = null;
  if (typeName === 'backgroundTypeFill') {
    kind = 'fill';
    fill = objectOrNull(type['fill']);
  } else if (typeName === 'backgroundTypePattern') {
    kind = 'pattern';
    fill = objectOrNull(type['fill']);
  } else if (typeName === 'backgroundTypeWallpaper') {
    kind = 'wallpaper';
  } else {
    return null;
  }
  return {
    // TDLib serializes int64 ids as strings in JSON — keep them verbatim.
    backgroundId: `${(background['id'] as string | number | undefined) ?? ''}`,
    name: (background['name'] as string | undefined) ?? '',
    kind,
    colors: fillColorsOf(fill),
    angle: fill !== null ? ((fill['rotation_angle'] as number | undefined) ?? 180) : 180,
    isDark: (background['is_dark'] as boolean | undefined) ?? false
  };
}
