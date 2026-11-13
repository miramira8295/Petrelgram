import { DrawnRouteReason, drawnSourceRouteReason } from '../../util/drawnRouteMetrics';
import { DrawnRowLayoutEngine } from './DrawnLayoutWarmCache';
import { DrawnBubbleOutlineCache, DrawnRoundRectCache } from './DrawnBubbleGeometry';
import { DrawnTextUnits } from '../../util/drawnTextUnits';
import { DrawnSingleMediaGeometry } from './DrawnSingleMediaGeometry';
import { drawnLiveSurface } from '../../util/drawnContentPolicy';
import { UIContext } from '@kit.ArkUI';
import { AlbumGroup } from '../../util/collapseAlbums';
import { DrawnAlbumGridLayouts, DrawnAlbumGridPlan } from './DrawnAlbumGridLayout';
import { DrawnBubbleChrome, DrawnChromeLayouts, placeChromeComments, placeChromeReactions } from './DrawnBubbleChrome';
import { placeDrawnFooter } from '../../util/drawnFooterPlacement';
import { BubbleCornerCache } from '../../util/messageBubblePresentation';
import { cornerPx, senderLeadInset } from '../../util/bubbleCornerInset';
import { mediaThumbWidth, inlineMaxWidth, BUBBLE_AVATAR_GUTTER_VP } from '../../util/mediaBox';
import { DrawnRichSourceCache } from '../../util/drawnRichTextPolicy';
import { DrawnRichTextLayout, DrawnRichTextLayouts } from './DrawnRichTextLayout';
import { DrawnSenderHeaderCache } from './DrawnSenderHeader';
import { DrawnReplyQuoteCache } from './DrawnReplyQuote';
import { DrawnTextFooterCache, sameDrawnFooterGeometry } from './DrawnTextFooter';
import { DrawnTextLineCache } from './DrawnTextLine';
import { DrawnMediaColors } from './DrawnMediaColors';
import { MessageBubbleRenderData } from './ReusableMessageBubble';
import { formatClockTime } from '../../util/formatTime';
import { str } from '../../util/strings';
import { AVATAR_PALETTE, COLOR_BUBBLE_IN, COLOR_BUBBLE_OUT, COLOR_PRIMARY,
  COLOR_TEXT_SECONDARY, accentSoft, bubbleTextFor } from '../../util/theme';
import { getAccentColorStore, getUserStore } from '../../tdkit/Globals';
import { DrawnBubblePlan, DrawnBubbleStyle, DrawnBubbleTile } from './DrawnBubblePlan';

interface MediaCaptionLastLine { right: number; top: number; }

// One owner per mounted media row. Paragraph/source caches are bounded; image and
// progress notifications never call this class. Geometry traverses each tile
// once, O(N + S), with no per-tile search through selection or message lists.
export class DrawnMediaLayouts implements DrawnRowLayoutEngine {
  failureReason: DrawnRouteReason = DrawnRouteReason.Drawn;
  private colors: DrawnMediaColors = new DrawnMediaColors();
  private units: DrawnTextUnits = new DrawnTextUnits();
  private footerShapes: DrawnRoundRectCache = new DrawnRoundRectCache();
  private outlines: DrawnBubbleOutlineCache = new DrawnBubbleOutlineCache();
  private quoteShapes: DrawnRoundRectCache = new DrawnRoundRectCache();
  private single: boolean;
  private singleGeometry: DrawnSingleMediaGeometry | null = null;
  constructor(single: boolean) { this.single = single; }
  private cached: DrawnBubblePlan | null = null;
  private cachedGroup: AlbumGroup | null = null;
  private cachedSelection: number[] | null = null;
  private cachedViews: string = '';
  private cachedKey: string = '';
  private cachedGrid: DrawnAlbumGridPlan | null = null;
  private cachedUi: UIContext | null = null;
  private cachedPure: boolean = false;
  private grids: DrawnAlbumGridLayouts | null = null;
  private chrome: DrawnChromeLayouts = new DrawnChromeLayouts();
  private placedGrid: DrawnAlbumGridPlan | null = null;
  private placedX: number = 0;
  private placedY: number = 0;
  private placedTiles: DrawnBubbleTile[] = [];
  private lastLines: WeakMap<DrawnRichTextLayout, MediaCaptionLastLine> = new WeakMap();

  private corners: BubbleCornerCache = new BubbleCornerCache();
  private sources: DrawnRichSourceCache = new DrawnRichSourceCache();
  private captions: DrawnRichTextLayouts = new DrawnRichTextLayouts();
  private headers: DrawnSenderHeaderCache = new DrawnSenderHeaderCache();
  private quotes: DrawnReplyQuoteCache = new DrawnReplyQuoteCache();
  private footer: DrawnTextFooterCache = new DrawnTextFooterCache();
  private initials: DrawnTextLineCache = new DrawnTextLineCache();
  private tagText: Resource = $r('app.color.tag_text');
  private tagFill: Resource = $r('app.color.selected_pill');
  private quoteText: Resource = $r('app.color.quote_text');
  private quoteFill: ResourceColor = '';
  private paletteEnvironment: string = '';

  private placeTiles(grid: DrawnAlbumGridPlan, x: number, y: number): DrawnBubbleTile[] {
    if (grid === this.placedGrid && x === this.placedX && y === this.placedY) { return this.placedTiles; }
    const tiles: DrawnBubbleTile[] = [];
    for (const t of grid.tiles) {
      tiles.push({ cell: t.cell, x: x + t.x, y: y + t.y, width: t.width, height: t.height, opaque: !this.single,
        key: `${t.key}:${x}:${y}:${t.cell.failed}:${t.cell.thumbFileId}` });
    }
    this.placedGrid = grid; this.placedX = x; this.placedY = y; this.placedTiles = tiles;
    return tiles;
  }

  prepare(ui: UIContext, group: AlbumGroup, data: MessageBubbleRenderData,
    style: DrawnBubbleStyle): DrawnBubblePlan | null {
    this.failureReason = DrawnRouteReason.Drawn;
    const m = group.head;
    this.units.prepare(ui, style.textEnvironment);
    const d = this.units.density;
    const playing = !this.single && drawnLiveSurface(group, data);
    const key = `${d}:${this.units.fp2px(11)}:${this.units.fp2px(style.fontSize)}:${data.contentWidth}:${data.isGroup}:${data.isChannel}:${data.themeBubbleOut}:` +
      `${data.chatId}:${data.selectionActive}:${playing ? data.playSlotKey : ''}:${playing && data.autoplayMuted}:` +
      `${playing ? data.playSlotStartMs : 0}:${style.radius}:${style.fontSize}:${style.environment}:${style.textEnvironment}:${style.role}`;
    if (this.cached !== null && this.cachedUi === ui && this.cachedGroup === group && this.cachedSelection === data.selectedMemberIds &&
      this.cachedKey === key && this.cachedViews === style.views) { return this.cached; }
    const avatarSpace = data.isGroup && !m.isOutgoing ? BUBBLE_AVATAR_GUTTER_VP : 0;
    const maxWidth = this.single ? inlineMaxWidth(data.contentWidth, avatarSpace)
      : mediaThumbWidth(data.contentWidth, avatarSpace);
    let gridWidth = maxWidth;
    if (!(gridWidth > 20) || !(d > 0)) { this.failureReason = DrawnRouteReason.InvalidGeometry; return null; }
    const captionText = this.single ? m.text : group.caption;
    const source = captionText !== '' ? this.sources.prepare(captionText, this.single ? m.textEntities : group.captionEntities) : null;
    if (captionText !== '' && source === null) { this.failureReason = drawnSourceRouteReason(this.sources.reason); return null; }
    const chrome = this.chrome.prepare(ui, m, data.isChannel, gridWidth - 16, style.environment);
    const shownName = data.isGroup && !m.isOutgoing && group.showSenderName && m.senderName !== '';
    const pure = captionText === '' && m.text === '' && !shownName && m.replyToMessageId === 0 && m.forwardFrom === '' &&
      !chrome.hasReactions && chrome.comments === null;
    const tail = group.showAvatar && !pure;
    const radius = pure ? 15 : style.radius;
    const c = this.corners.prepare(radius, m.isOutgoing, pure || group.showSenderName, pure || group.showAvatar);
    const secondary = this.colors.resolve(captionText === '' && !chrome.hasReactions ? Color.White : COLOR_TEXT_SECONDARY, style.environment);
    const accentId = m.senderId > 0 ? getUserStore().accentColorId(m.senderId) : -1;
    const senderColor: ResourceColor = (accentId >= 0 ? getAccentColorStore().nameColorHex(accentId, false) : '') ||
      AVATAR_PALETTE[Math.abs(m.senderId) % AVATAR_PALETTE.length];
    if (this.paletteEnvironment !== style.environment) {
      this.quoteFill = accentSoft(); this.paletteEnvironment = style.environment;
    }
    const header = shownName ? this.headers.prepare(ui, m.senderName, style.role, (maxWidth - 16) * d,
      senderColor, this.tagText, this.tagFill, style.textEnvironment, style.environment) : null;
    const quote = m.replyToMessageId !== 0 ? this.quotes.prepare(ui, m.replySenderName, m.replyText, maxWidth * d,
      COLOR_PRIMARY, this.quoteText, this.quoteFill, style.textEnvironment, style.environment, m.replyThumbPath !== '' || m.replyDiceLayers.length > 0) : null;
    const caption = source !== null ? this.captions.prepare(ui, { source, maxWidthVp: maxWidth - 16, minWidthVp: 0,
      fontSize: style.fontSize, reserve: '', foreground: bubbleTextFor(m.isOutgoing),
      accent: COLOR_PRIMARY, environment: style.environment }) : null;
    const footer = this.footer.prepare(ui, formatClockTime(m.date), m.editDate > 0 ? str('mb_edited') : '',
      style.views, m.isOutgoing, (maxWidth - 16) * d, secondary, style.environment);
    if (this.single && this.singleGeometry === null) { this.singleGeometry = new DrawnSingleMediaGeometry(); }
    if (!this.single && this.grids === null) { this.grids = new DrawnAlbumGridLayouts(); }
    const grid = this.single && this.singleGeometry !== null
      ? this.singleGeometry.prepare(m, data.chatId, data.contentWidth, avatarSpace, d)
      : this.grids?.prepare(group, data, maxWidth, d);
    if (grid === undefined) { this.failureReason = DrawnRouteReason.MissingGrid; return null; }
    const old = this.cached;
    const previous = this.cachedGroup;
    // A new immutable message snapshot need not imply new geometry. Subcaches
    // compare their own inputs; fixed fields below cover shell/avatar policy.
    // Returning the same plan also avoids waking its @Monitor and native paint
    // bindings. Media/file delivery still has its independent slot channel.
    if (old !== null && previous !== null && this.cachedUi === ui && this.cachedKey === key &&
      this.cachedGrid === grid && this.cachedPure === pure && old.caption === caption &&
      old.header === header && old.quote === quote && sameDrawnFooterGeometry(old.footerSlot, footer) && old.chrome?.content === chrome &&
      previous.showAvatar === group.showAvatar && previous.showSenderName === group.showSenderName &&
      previous.head.isOutgoing === m.isOutgoing && previous.head.senderId === m.senderId &&
      previous.head.senderInitials === m.senderInitials) {
      this.cachedGroup = group; this.cachedSelection = data.selectedMemberIds;
      footer.line.recolor(old.secondary);
      if (old.footerSlot !== null) { old.footerSlot.line = footer.line; }
      this.cachedViews = style.views;
      return old;
    }
    const p = new DrawnBubblePlan();
    p.chrome = new DrawnBubbleChrome(chrome);
    p.density = d; p.outgoing = m.isOutgoing;
    p.fill = this.colors.resolve(m.isOutgoing ? (data.themeBubbleOut || COLOR_BUBBLE_OUT) : COLOR_BUBBLE_IN, style.environment);
    p.accent = this.colors.resolve(COLOR_PRIMARY, style.environment); p.secondary = secondary;
    p.avatarColor = this.colors.resolve(AVATAR_PALETTE[Math.abs(m.senderId) % AVATAR_PALETTE.length], style.environment);
    if (this.single) {
      gridWidth = Math.min(maxWidth, Math.max(grid.width, (header?.widthPx ?? 0) / d + 16,
        (quote?.widthPx ?? 0) / d, chrome.width + 16, (caption?.widthVp ?? 0) + 16, footer.widthPx / d + 16));
    }
    p.bubbleX = avatarSpace;
    const left = avatarSpace + (m.isOutgoing ? 0 : 7);
    const shellWidth = gridWidth + 4 + 7;
    p.width = avatarSpace + shellWidth;
    let y = 2;
    if (shownName || chrome.forward !== null) { y += senderLeadInset(cornerPx(c.topLeft), 2); }
    if (chrome.forward !== null) {
      p.chrome.forwardRect = { x: left + 10, y, width: gridWidth - 16, height: chrome.forward.heightPx / d };
      y += chrome.forward.heightPx / d + 2;
    }
    if (header !== null) {
      p.header = header;
      p.headerX = left + 10; p.headerY = y;
      y += p.header.heightPx / d + 4;
    }
    if (quote !== null) {
      p.quote = quote;
      p.quoteRect = { x: left + 2, y, width: gridWidth, height: p.quote.heightPx / d };
      p.quoteBackground = this.quoteShapes.prepare(0, 0, gridWidth * d, p.quote.heightPx, 4 * d);
      p.quoteStripe = { left: 0, top: 0, right: 4 * d, bottom: p.quote.heightPx };
      p.quoteClip = { left: 10 * d, top: 3 * d, right: (gridWidth - 6) * d, bottom: 35 * d };
      y += p.quote.heightPx / d + 4;
    }
    const gridX = left + 2 + (gridWidth - grid.width) / 2;
    p.nativeTiles = grid.tiles;
    p.tiles = this.placeTiles(grid, gridX, y);
    p.grid = { x: gridX, y, width: grid.width, height: grid.height };
    y += grid.height;
    p.footerSlot = footer; p.views = style.views !== '';
    p.footerWidth = footer.widthPx / d; p.footerTextOffset = footer.textOffsetPx / d;
    p.statusSize = footer.iconPx / d;
    p.onMedia = source === null && !chrome.hasReactions && grid.width >= p.footerWidth + 16 && grid.height >= footer.heightPx / d + 8;
    if (source === null && !p.onMedia) {
      p.secondary = this.colors.resolve(COLOR_TEXT_SECONDARY, style.environment); footer.line.recolor(p.secondary);
    }
    let captionFooterY = 0;
    if (caption !== null) {
      p.caption = caption;
      p.captionX = left + 10; p.captionY = y;
      let last = this.lastLines.get(p.caption);
      if (last === undefined) {
        const line = p.caption.paragraph.getLineMetrics(p.caption.paragraph.getLineCount() - 1);
        last = { right: line !== undefined ? line.left + line.width : Number.NaN,
          top: line !== undefined ? Math.max(0, line.baseline - line.ascent) : Number.NaN };
        this.lastLines.set(p.caption, last);
      }
      const placed = placeDrawnFooter({ maxWidthPx: (gridWidth - 16) * d, bodyWidthPx: p.caption.widthVp * d,
        bodyHeightPx: p.caption.heightVp * d, lastLineRightPx: last.right, lastLineTopPx: last.top,
        chromeWidthPx: (gridWidth - 16) * d, footerWidthPx: p.footerWidth * d,
        footerHeightPx: footer.heightPx, gapPx: 4 * d, bottomGapPx: 2 * d });
      captionFooterY = y + placed.footerYPx / d;
      y += chrome.hasReactions ? p.caption.heightVp : placed.heightPx / d;
    }
    p.footerX = p.onMedia ? p.grid.x + p.grid.width - 8 - p.footerWidth : left + 2 + gridWidth - 8 - p.footerWidth;
    p.footerY = source !== null ? captionFooterY : y - footer.heightPx / d - 4;
    if (source === null && !p.onMedia && !chrome.hasReactions) {
      p.footerY = y + 4; y = p.footerY + footer.heightPx / d;
    }
    if (chrome.hasReactions) {
      const placed = placeChromeReactions(p.chrome, this.chrome.reactionFlow(gridWidth - 16),
        left + 10, y, gridWidth - 16, p.footerWidth, footer.heightPx / d);
      p.footerY = placed.footerY; y = placed.bottom;
    }
    p.statusX = p.footerX + p.footerWidth - p.statusSize * 4 / 3;
    p.statusY = p.footerY + (footer.heightPx - footer.iconPx) / (2 * d);
    if (p.views) {
      p.footerEye = { left: p.footerX * d, top: (p.footerY + 3) * d,
        right: (p.footerX + 10) * d, bottom: (p.footerY + 9) * d };
    }
    if (p.onMedia) {
      p.footerBackdrop = this.footerShapes.prepare((p.footerX - 4) * d, (p.footerY - 2) * d,
        (p.footerX + p.footerWidth + 4) * d, (y - 2) * d, 5 * d);
    }
    p.height = placeChromeComments(p.chrome, left + 10, y, gridWidth - 16, d) + 2 +
      (source !== null || chrome.hasReactions ? 6 : 0);
    if (avatarSpace > 0 && group.showAvatar) { p.height = Math.max(38, p.height); }
    p.outline = this.outlines.prepare(shellWidth, p.height, m.isOutgoing, tail,
      cornerPx(c.topLeft), cornerPx(c.topRight), cornerPx(c.bottomRight), cornerPx(c.bottomLeft), d, 7);
    if (avatarSpace > 0 && group.showAvatar) {
      p.avatar = { x: 0, y: p.height - 38, width: 38, height: 38 };
      p.initials = this.initials.prepare(m.senderInitials, 38 * d, this.units.fp2px(38 * .4), this.colors.resolve(Color.White, style.environment),
        style.textEnvironment, true);
    }
    this.cachedViews = style.views;
    this.cached = p; this.cachedGroup = group; this.cachedSelection = data.selectedMemberIds; this.cachedKey = key;
    this.cachedGrid = grid; this.cachedUi = ui; this.cachedPure = pure;
    return p;
  }
}
