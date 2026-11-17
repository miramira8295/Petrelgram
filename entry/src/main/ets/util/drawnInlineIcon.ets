import { TdObject } from '../tdkit/TdTypes';
import { documentFileId } from './drawnDocumentMedia';
export interface DrawnInlineIcon { file: TdObject; width: number; height: number; }
export interface DrawnInlineIconPlacement { icon: DrawnInlineIcon; x: number; y: number; width: number; height: number; }
export function drawnInlineIcon(node: TdObject): DrawnInlineIcon | undefined {
  const document = node['document'] as TdObject | undefined;
  const file = document?.['document'] as TdObject | undefined;
  const width = node['width'] as number, height = node['height'] as number;
  if (file === undefined || documentFileId(file) <= 0 || !Number.isFinite(width) || !Number.isFinite(height) || width <= 0 || height <= 0) { return undefined; }
  return { file, width, height };
}
export function appendDrawnIcons(target: DrawnInlineIconPlacement[], source: DrawnInlineIconPlacement[], x: number, y: number): void {
  for (const item of source) { target.push({ icon: item.icon, x: item.x + x, y: item.y + y, width: item.width, height: item.height }); }
}
