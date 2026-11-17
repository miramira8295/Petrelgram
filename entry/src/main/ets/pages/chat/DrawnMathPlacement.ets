import { common2D, text } from '@kit.ArkGraphics2D';

// Layouts retain only metrics/keys, never PixelMaps or asynchronous subscriptions.
export interface DrawnMathPlacement {
  key: string;
  expression: string;
  renderSize: number;
  color: number;
  rect: common2D.Rect;
  ready: boolean;
  fallback: text.Paragraph;
  fallbackY: number;
}
