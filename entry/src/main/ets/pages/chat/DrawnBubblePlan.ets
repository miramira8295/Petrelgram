import { DrawnTextFooter } from './DrawnTextFooter';
import { common2D, drawing } from '@kit.ArkGraphics2D';
import { AlbumCellRenderData } from '../../util/albumCellRenderData';
import { DrawnAlbumRect } from '../../util/drawnAlbumPolicy';
import { DrawnRichTextLayout } from './DrawnRichTextLayout';
import { DrawnSenderHeader } from './DrawnSenderHeader';
import { DrawnReplyQuote } from './DrawnReplyQuote';
import { DrawnTextLine } from './DrawnTextLine';
import { DrawnBubbleChrome } from './DrawnBubbleChrome';

export interface DrawnBubbleStyle {
  radius: number; fontSize: number; environment: string; textEnvironment: string;
  role: string; views: string;
}
export interface DrawnBubbleTile extends DrawnAlbumRect {
  cell: AlbumCellRenderData;
  opaque?: boolean;
  key: string;
}

export class DrawnBubblePlan {
  chrome: DrawnBubbleChrome | null = null;
  width: number = 0;
  height: number = 0;
  density: number = 1;
  bubbleX: number = 0;
  bubbleY: number = 0;
  grid: DrawnAlbumRect = { x: 0, y: 0, width: 0, height: 0 };
  private outlinePath: drawing.Path | null = null;
  // Layout engines normally assign a cached outline. Do not allocate an empty
  // native Path just to overwrite it on every new footer/media plan.
  get outline(): drawing.Path {
    if (this.outlinePath === null) { this.outlinePath = new drawing.Path(); }
    return this.outlinePath;
  }
  set outline(path: drawing.Path) { this.outlinePath = path; }
  tiles: DrawnBubbleTile[] = [];
  // Existing grid-local snapshot; shared by native anchors without allocation.
  // Separate from absolute hit-test/paint tiles and footer/shell geometry.
  nativeTiles: DrawnBubbleTile[] = [];
  header: DrawnSenderHeader | null = null;
  headerX: number = 0;
  headerY: number = 0;
  quote: DrawnReplyQuote | null = null;
  quoteRect: DrawnAlbumRect = { x: 0, y: 0, width: 0, height: 0 };
  quoteBackground: drawing.RoundRect | null = null;
  quoteStripe: common2D.Rect = { left: 0, top: 0, right: 0, bottom: 0 };
  quoteClip: common2D.Rect = { left: 0, top: 0, right: 0, bottom: 0 };
  caption: DrawnRichTextLayout | null = null;
  captionX: number = 0;
  captionY: number = 0;
  // Geometry stays immutable. A same-size footer slot can replace only its
  // paint paragraph; the foreground has a separate content dependency.
  footerSlot: DrawnTextFooter | null = null;
  private footerLine: DrawnTextLine | null = null;
  get footer(): DrawnTextLine | null { return this.footerSlot?.line ?? this.footerLine; }
  set footer(line: DrawnTextLine | null) { this.footerLine = line; }
  footerX: number = 0;
  footerY: number = 0;
  footerWidth: number = 0;
  footerTextOffset: number = 0;
  statusSize: number = 12;
  statusX: number = 0;
  statusY: number = 0;
  footerBackdrop: drawing.RoundRect | null = null;
  footerEye: common2D.Rect = { left: 0, top: 0, right: 0, bottom: 0 };
  onMedia: boolean = false;
  outgoing: boolean = false;
  views: boolean = false;
  avatar: DrawnAlbumRect = { x: 0, y: 0, width: 0, height: 0 };
  initials: DrawnTextLine | null = null;
  fill: common2D.Color = { alpha: 0, red: 0, green: 0, blue: 0 };
  secondary: common2D.Color = { alpha: 0, red: 0, green: 0, blue: 0 };
  accent: common2D.Color = { alpha: 0, red: 0, green: 0, blue: 0 };
  avatarColor: common2D.Color = { alpha: 0, red: 0, green: 0, blue: 0 };
}
