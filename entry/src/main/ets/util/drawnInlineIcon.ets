import { TdObject } from '../tdkit/TdTypes';
import { documentFileId } from './drawnDocumentMedia';
export interface DrawnInlineIcon { file: TdObject; width: number; height: number; animated?: boolean; }
const DRAWN_INLINE_ANIMATED_PATH: RegExp = /\.(?:gif|apng)(?:$|[?#])/i;
// Keep known animated documents on their playback host. Static PixelMap caching
// intentionally decodes a single frame and must not silently freeze these spans.
export function drawnInlineIconAnimated(icon: DrawnInlineIcon, path: string): boolean {
  return icon.animated === true || DRAWN_INLINE_ANIMATED_PATH.test(path);
}
export interface DrawnInlineIconPlacement { icon: DrawnInlineIcon; x: number; y: number; width: number; height: number; }
export function drawnInlineIcon(node: TdObject): DrawnInlineIcon | undefined {
  const document = node['document'] as TdObject | undefined;
  const file = document?.['document'] as TdObject | undefined;
  const width = node['width'] as number, height = node['height'] as number;
  if (file === undefined || documentFileId(file) <= 0 || !Number.isFinite(width) || !Number.isFinite(height) || width <= 0 || height <= 0) { return undefined; }
  const mime = ((document?.['mime_type'] as string | undefined) ?? '').toLowerCase();
  const name = (document?.['file_name'] as string | undefined) ?? '';
  return { file, width, height,
    animated: mime === 'image/gif' || mime === 'image/apng' || DRAWN_INLINE_ANIMATED_PATH.test(name) };
}
export function appendDrawnIcons(target: DrawnInlineIconPlacement[], source: DrawnInlineIconPlacement[], x: number, y: number): void {
  for (const item of source) { target.push({ icon: item.icon, x: item.x + x, y: item.y + y, width: item.width, height: item.height }); }
}
