import { drawing } from '@kit.ArkGraphics2D';
import { glassBubbleCommands } from '../../util/bubbleGlassPath';

// One last shape per layout owner. Published paths are borrowed read-only:
// never reset/transform them, because an older plan may still be painting.
// Fixed-size keys, no text, entities, media or UIContext retained here.
export class DrawnBubbleOutlineCache {
  private key: string = '';
  private path: drawing.Path | null = null;

  prepare(w: number, h: number, outgoing: boolean, tail: boolean,
    tl: number, tr: number, br: number, bl: number, density: number, gutter: number): drawing.Path {
    const key = `${w}:${h}:${outgoing}:${tail}:${tl}:${tr}:${br}:${bl}:${density}:${gutter}`;
    if (this.path !== null && this.key === key) { return this.path; }
    const path = new drawing.Path();
    if (!path.buildFromSvgString(glassBubbleCommands(w, h, outgoing, tail,
      tl, tr, br, bl, 8, 12, density, 0, gutter))) {
      throw new Error('invalid drawn bubble outline');
    }
    this.key = key; this.path = path;
    return path;
  }
}

// Quote and footer use separate owners so alternating between them does not
// evict the other shape. A miss allocates a new immutable native object.
export class DrawnRoundRectCache {
  private key: string = '';
  private shape: drawing.RoundRect | null = null;

  prepare(left: number, top: number, right: number, bottom: number, radius: number): drawing.RoundRect {
    const key = `${left}:${top}:${right}:${bottom}:${radius}`;
    if (this.shape !== null && this.key === key) { return this.shape; }
    const shape = new drawing.RoundRect({ left, top, right, bottom }, radius, radius);
    this.key = key; this.shape = shape;
    return shape;
  }
}
