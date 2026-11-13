import { DrawnRouteReason, drawnSourceRouteReason } from '../../util/drawnRouteMetrics';
import { DrawnRowLayoutEngine } from './DrawnLayoutWarmCache';
import { DrawnBubbleOutlineCache, DrawnRoundRectCache } from './DrawnBubbleGeometry';
import { DrawnTextUnits } from '../../util/drawnTextUnits';
import { UIContext } from '@kit.ArkUI';
import { AlbumGroup } from '../../util/collapseAlbums';
import { MessageBubbleRenderData } from './ReusableMessageBubble';
import { DrawnBubblePlan, DrawnBubbleStyle } from './DrawnBubblePlan';
import { DrawnRichSourceCache } from '../../util/drawnRichTextPolicy';
import { DrawnRichTextLayout, DrawnRichTextLayouts } from './DrawnRichTextLayout';
import { DrawnSenderHeaderCache } from './DrawnSenderHeader';
import { DrawnReplyQuoteCache } from './DrawnReplyQuote';
import { DrawnTextLineCache, drawnColor } from './DrawnTextLine';
import { DrawnTextFooterCache, sameDrawnFooterGeometry } from './DrawnTextFooter';
import { DrawnBubbleChrome, DrawnChromeLayouts, placeChromeComments, placeChromeReactions } from './DrawnBubbleChrome';
import { BubbleCornerCache } from '../../util/messageBubblePresentation';
import { cornerPx } from '../../util/bubbleCornerInset';
import { BUBBLE_AVATAR_GUTTER_VP, bubbleMaxWidth } from '../../util/mediaBox';
import { drawnTailGutter } from '../../util/drawnPlainTextPolicy';
import { placeDrawnFooter } from '../../util/drawnFooterPlacement';
import { formatClockTime } from '../../util/formatTime';
import { str } from '../../util/strings';
import { getAccentColorStore, getUserStore } from '../../tdkit/Globals';
import { AVATAR_PALETTE, COLOR_BUBBLE_IN, COLOR_BUBBLE_OUT, COLOR_PRIMARY,
  COLOR_TEXT_SECONDARY, accentSoft, bubbleTextFor } from '../../util/theme';

interface DrawnBodyLastLine { right: number; top: number; }

// One bounded source/paragraph cache per row; the footer and chrome have their
// own caches. No text serialization, entity scans or shaping on status updates.
export class DrawnTextLayouts implements DrawnRowLayoutEngine {
  failureReason: DrawnRouteReason = DrawnRouteReason.Drawn;
  private units: DrawnTextUnits = new DrawnTextUnits();
  private outlines: DrawnBubbleOutlineCache = new DrawnBubbleOutlineCache();
  private quoteShapes: DrawnRoundRectCache = new DrawnRoundRectCache();
  private sources: DrawnRichSourceCache = new DrawnRichSourceCache();
  private bodies: DrawnRichTextLayouts = new DrawnRichTextLayouts();
  private headers: DrawnSenderHeaderCache = new DrawnSenderHeaderCache();
  private quotes: DrawnReplyQuoteCache = new DrawnReplyQuoteCache();
  private footers: DrawnTextFooterCache = new DrawnTextFooterCache();
  private chrome: DrawnChromeLayouts = new DrawnChromeLayouts();
  private initials: DrawnTextLineCache = new DrawnTextLineCache();
  private corners: BubbleCornerCache = new BubbleCornerCache();
  private lastLines: WeakMap<DrawnRichTextLayout, DrawnBodyLastLine> = new WeakMap<DrawnRichTextLayout, DrawnBodyLastLine>();
  private current: DrawnBubblePlan | null = null;
  private tagText: Resource = $r('app.color.tag_text');
  private tagFill: Resource = $r('app.color.selected_pill');
  private quoteText: Resource = $r('app.color.quote_text');
  private quoteFill: ResourceColor = '';
  private paletteEnvironment: string = '';
  private key: string = '';

  prepare(ui: UIContext, group: AlbumGroup, data: MessageBubbleRenderData, style: DrawnBubbleStyle): DrawnBubblePlan | null {
    this.failureReason = DrawnRouteReason.Drawn;
    this.units.prepare(ui, style.textEnvironment);
    const m = group.head, d = this.units.density;
    const avatarSpace = data.isGroup && !m.isOutgoing ? BUBBLE_AVATAR_GUTTER_VP : 0;
    const maxPx = Math.floor((bubbleMaxWidth(data.contentWidth, avatarSpace) - 16) * d);
    if (!(d > 0) || !(maxPx > 0)) { this.failureReason = DrawnRouteReason.InvalidGeometry; return null; }
    const source = this.sources.prepare(m.text, m.textEntities);
    if (source === null) { this.failureReason = drawnSourceRouteReason(this.sources.reason); return null; }
    const body = this.bodies.prepare(ui, { source, maxWidthVp: maxPx / d, minWidthVp: 0,
      fontSize: style.fontSize, reserve: '', foreground: bubbleTextFor(m.isOutgoing),
      accent: COLOR_PRIMARY, environment: style.environment });
    let last = this.lastLines.get(body);
    if (last === undefined) {
      const line = body.paragraph.getLineMetrics(body.paragraph.getLineCount() - 1);
      last = { right: line !== undefined ? line.left + line.width : Number.NaN,
        top: line !== undefined ? Math.max(0, line.baseline - line.ascent) : Number.NaN };
      this.lastLines.set(body, last);
    }
    if (this.paletteEnvironment !== style.environment) {
      this.quoteFill = accentSoft(); this.paletteEnvironment = style.environment;
    }
    const shownName = data.isGroup && !m.isOutgoing && group.showSenderName && m.senderName !== '';
    const accentId = m.senderId > 0 ? getUserStore().accentColorId(m.senderId) : -1;
    const senderColor: ResourceColor = (accentId >= 0 ? getAccentColorStore().nameColorHex(accentId, false) : '') ||
      AVATAR_PALETTE[Math.abs(m.senderId) % AVATAR_PALETTE.length];
    const header = shownName ? this.headers.prepare(ui, m.senderName, style.role, maxPx, senderColor,
      this.tagText, this.tagFill, style.textEnvironment, style.environment) : null;
    const quote = m.replyToMessageId !== 0 ? this.quotes.prepare(ui, m.replySenderName, m.replyText, maxPx,
      COLOR_PRIMARY, this.quoteText, this.quoteFill, style.textEnvironment, style.environment, m.replyThumbPath !== '' || m.replyDiceLayers.length > 0) : null;
    const secondary = drawnColor(COLOR_TEXT_SECONDARY);
    const footer = this.footers.prepare(ui, formatClockTime(m.date), m.editDate > 0 ? str('mb_edited') : '',
      style.views, m.isOutgoing, maxPx, secondary, style.environment);
    const chrome = this.chrome.prepare(ui, m, data.isChannel, maxPx / d, style.environment);
    const key = `${avatarSpace}:${group.showAvatar}:${group.showSenderName}:${m.isOutgoing}:${m.senderId}:` +
      `${m.senderInitials}:${style.radius}:${style.environment}:${data.themeBubbleOut}`;
    const old = this.current;
    if (old !== null && key === this.key && old.caption === body && old.header === header &&
      old.quote === quote && sameDrawnFooterGeometry(old.footerSlot, footer) && old.chrome?.content === chrome) {
      if (old.footerSlot !== null) { old.footerSlot.line = footer.line; }
      return old;
    }
    const placed = placeDrawnFooter({ maxWidthPx: maxPx, bodyWidthPx: body.widthVp * d,
      bodyHeightPx: body.heightVp * d, lastLineRightPx: chrome.hasReactions ? Number.NaN : last.right, lastLineTopPx: last.top,
      chromeWidthPx: Math.max(header?.widthPx ?? 0, quote?.widthPx ?? 0, chrome.width * d,
        chrome.hasReactions ? Math.min(maxPx, chrome.reactionWidth * d + footer.widthPx + 6 * d) : 0), footerWidthPx: footer.widthPx,
      footerHeightPx: footer.heightPx, gapPx: 4 * d, bottomGapPx: 2 * d });
    const p = new DrawnBubblePlan();
    p.chrome = new DrawnBubbleChrome(chrome);
    p.density = d; p.outgoing = m.isOutgoing; p.bubbleX = avatarSpace;
    p.fill = drawnColor(m.isOutgoing ? (data.themeBubbleOut || COLOR_BUBBLE_OUT) : COLOR_BUBBLE_IN);
    p.secondary = secondary; p.accent = drawnColor(COLOR_PRIMARY);
    p.avatarColor = drawnColor(AVATAR_PALETTE[Math.abs(m.senderId) % AVATAR_PALETTE.length]);
    const gutter = drawnTailGutter(group.showAvatar), left = avatarSpace + 8 + (m.isOutgoing ? 0 : gutter);
    const contentWidth = placed.widthPx / d, shellWidth = contentWidth + 16 + gutter;
    p.width = avatarSpace + shellWidth;
    let y = 8;
    if (chrome.forward !== null) {
      p.chrome.forwardRect = { x: left, y, width: contentWidth, height: chrome.forward.heightPx / d };
      y += chrome.forward.heightPx / d + 2;
    }
    p.header = header; p.headerX = left; p.headerY = y;
    y += header !== null ? header.heightPx / d + 2 : 0;
    p.quote = quote;
    if (quote !== null) {
      p.quoteRect = { x: left, y, width: contentWidth, height: quote.heightPx / d };
      p.quoteBackground = this.quoteShapes.prepare(0, 0, placed.widthPx, quote.heightPx, 4 * d);
      p.quoteStripe = { left: 0, top: 0, right: 4 * d, bottom: quote.heightPx };
      p.quoteClip = { left: 10 * d, top: 3 * d, right: placed.widthPx - 6 * d, bottom: 35 * d };
      y += quote.heightPx / d + 4;
    }
    p.caption = body; p.captionX = left; p.captionY = y;
    p.footerSlot = footer; p.views = style.views !== '';
    p.footerWidth = footer.widthPx / d; p.footerTextOffset = footer.textOffsetPx / d;
    p.footerX = left + contentWidth - p.footerWidth;
    p.footerY = y + placed.footerYPx / d;
    let bottom = y + placed.heightPx / d;
    if (chrome.hasReactions) {
      const reactionFooter = placeChromeReactions(p.chrome, this.chrome.reactionFlow(contentWidth),
        left, y + body.heightVp, contentWidth, p.footerWidth, footer.heightPx / d);
      p.footerY = reactionFooter.footerY; bottom = reactionFooter.bottom;
    }
    p.statusSize = footer.iconPx / d;
    p.statusX = left + contentWidth - p.statusSize * 4 / 3;
    p.statusY = p.footerY + (footer.heightPx - footer.iconPx) / (2 * d);
    if (p.views) {
      p.footerEye = { left: p.footerX * d, top: (p.footerY + 3) * d,
        right: (p.footerX + 10) * d, bottom: (p.footerY + 9) * d };
    }
    p.height = placeChromeComments(p.chrome, left, bottom, contentWidth, d) + 8;
    const bubbleHeight = p.height;
    if (avatarSpace > 0 && group.showAvatar && p.height < 38) { this.alignShortRow(p, 38 - p.height); }
    const c = this.corners.prepare(style.radius, m.isOutgoing, group.showSenderName, group.showAvatar);
    p.outline = this.outlines.prepare(shellWidth, bubbleHeight, m.isOutgoing, group.showAvatar,
      cornerPx(c.topLeft), cornerPx(c.topRight), cornerPx(c.bottomRight), cornerPx(c.bottomLeft), d, gutter);
    if (avatarSpace > 0 && group.showAvatar) {
      p.avatar = { x: 0, y: p.height - 38, width: 38, height: 38 };
      p.initials = this.initials.prepare(m.senderInitials, 38 * d, this.units.fp2px(38 * .4), drawnColor(Color.White), style.textEnvironment, true);
    }
    this.current = p; this.key = key; return p;
  }
  // Keep the native 38vp row and original short bubble height. Shift the fixed
  // row coordinates once; do not widen/reflow text or pad the bubble itself.
  private alignShortRow(p: DrawnBubblePlan, dy: number): void {
    p.height += dy; p.bubbleY = dy;
    p.headerY += dy; p.quoteRect.y += dy; p.captionY += dy;
    p.footerY += dy; p.statusY += dy;
    p.footerEye.top += dy * p.density; p.footerEye.bottom += dy * p.density;
    if (p.chrome !== null) {
      p.chrome.forwardRect.y += dy; p.chrome.commentsRect.y += dy; p.chrome.reactionsY += dy;
    }
  }

}
