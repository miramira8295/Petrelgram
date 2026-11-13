import { DrawnTextUnits } from '../../util/drawnTextUnits';
import { UIContext } from '@kit.ArkUI';
import { common2D, text } from '@kit.ArkGraphics2D';
import { DrawnTextLine } from './DrawnTextLine';

export class DrawnTextFooter {
  line: DrawnTextLine;
  widthPx: number;
  heightPx: number;
  iconPx: number;
  textOffsetPx: number;
  constructor(line: DrawnTextLine, width: number, height: number, icon: number, offset: number) {
    this.line = line; this.widthPx = width; this.heightPx = height; this.iconPx = icon; this.textOffsetPx = offset;
  }
}

// Footer changes do not enter the body source/layout cache. One entry is enough
// for the live row; widths are measured in px, including scaled status icons.
export class DrawnTextFooterCache {
  private units: DrawnTextUnits = new DrawnTextUnits();
  private current: DrawnTextFooter | null = null;
  private key: string = '';
  prepare(ui: UIContext, time: string, edited: string, views: string, outgoing: boolean,
    maxPx: number, color: common2D.Color, environment: string): DrawnTextFooter {
    this.units.prepare(ui, environment);
    const d = this.units.density, font = this.units.fp2px(11), small = this.units.fp2px(10.5), icon = this.units.fp2px(12);
    const key = `${time}:${edited}:${views}:${outgoing}:${maxPx}:${d}:${font}:${small}:${icon}:${environment}`;
    if (this.current !== null && key === this.key) { this.current.line.recolor(color); return this.current; }
    const pb = new text.ParagraphBuilder({ textStyle: { fontSize: font, color } }, text.FontCollection.getGlobalInstance());
    if (views !== '') { pb.addText(views); this.gap(pb, 6 * d); }
    if (edited !== '') {
      pb.pushStyle({ fontSize: small, color }); pb.addText(edited); pb.popStyle(); this.gap(pb, 4 * d);
    }
    pb.addText(time);
    const paragraph = pb.build(); paragraph.layoutSync(maxPx);
    const labelWidth = Math.ceil(paragraph.getMaxIntrinsicWidth());
    const offset = views !== '' ? 13 * d : 0;
    const width = offset + labelWidth + (outgoing ? icon * 4 / 3 + 4 * d : 0);
    const height = Math.max(paragraph.getHeight(), outgoing ? icon : 0, views !== '' ? 12 * d : 0);
    if (!Number.isFinite(width) || width <= 0 || width > maxPx || !Number.isFinite(height) || height <= 0) {
      throw new Error('invalid text footer metrics');
    }
    this.current = new DrawnTextFooter(new DrawnTextLine(paragraph, labelWidth, color), width, height, icon, offset);
    this.key = key; return this.current;
  }
  private gap(pb: text.ParagraphBuilder, width: number): void {
    pb.addPlaceholder({ width, height: 0, align: text.PlaceholderAlignment.BOTTOM_OF_ROW_BOX,
      baseline: text.TextBaseline.ALPHABETIC, baselineOffset: 0 });
  }
}

// Geometry equality is fixed work. The caller commits a new paint line only
// after ALL plan inputs matched, so a failed A -> B -> A attempt cannot poison A.
export function sameDrawnFooterGeometry(a: DrawnTextFooter | null, b: DrawnTextFooter): boolean {
  return a !== null && a.widthPx === b.widthPx && a.heightPx === b.heightPx &&
    a.iconPx === b.iconPx && a.textOffsetPx === b.textOffsetPx &&
    a.line.widthPx === b.line.widthPx && a.line.heightPx === b.line.heightPx;
}
