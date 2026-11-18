import { documentEmbedHeight } from '../../util/documentEmbedMetrics';
import { DrawnDocumentWidget, DrawnDocumentWidgetPlacement } from '../../util/drawnDocumentWidget';
import { DrawnInlineIconPlacement, appendDrawnIcons } from '../../util/drawnInlineIcon';
import { packAlbumRows } from '../../util/packAlbumRows';
import { DrawnDocumentMedia } from '../../util/drawnDocumentMedia';
import { drawnPageButtonBoxes } from '../../util/drawnPageButton';
import { botButtonBg } from '../../util/theme';
import { mathMetricsFor, mathKeyOf } from '../../util/mathImageCache';
import { DrawnMathPlacement } from './DrawnMathPlacement';
import { drawnTableGrid } from '../../util/drawnTableGrid';
import { textWidthEstimate } from '../../util/tableLayout';
import { DrawnAlbumRect } from '../../util/drawnAlbumPolicy';
import { TdObject } from '../../tdkit/TdTypes';
import { DrawnRichParagraph, DrawnRichNativeParagraph, DrawnRichCompositeParagraph, DrawnRichBlockBackground } from './DrawnRichCompositeParagraph';
import { str } from '../../util/strings';
import { DrawnTextUnits } from '../../util/drawnTextUnits';
import { ColorMetrics, UIContext } from '@kit.ArkUI';
import { common2D, drawing, text } from '@kit.ArkGraphics2D';
import { DrawnPlainLayoutCache } from '../../util/drawnPlainTextPolicy';
import { DrawnRichHitIndex } from '../../util/drawnRichHitIndex';
import { appendDrawnRichHits, DrawnRichLink, DrawnRichHit, DrawnRichRect, DrawnRichSourceCache, DrawnRichSource, DrawnRichButton } from '../../util/drawnRichTextPolicy';

const EMPTY_DRAWN_LABEL_ENTITIES: TdObject[] = [];
const EMPTY_DRAWN_ANCHORS: ReadonlyMap<string, number> = new Map<string, number>();

export interface DrawnRichTextSpec {
  mathRevision?: number;
  scrollMath?: boolean;
  source: DrawnRichSource;
  expandedBlocks?: ReadonlyArray<number>;
  spoilersRevealed?: boolean;
  maxLines?: number;
  codeBlock?: boolean;
  maxWidthVp: number;
  minWidthVp: number;
  fontSize: number;
  reserve: string;
  foreground: ResourceColor;
  accent: ResourceColor;
  environment: string;
}

function sameRichSpec(a: DrawnRichTextSpec, b: DrawnRichTextSpec): boolean {
  return (!(a.source.hasMath || a.source.hasEmbed) || a.mathRevision === b.mathRevision) && a.scrollMath === b.scrollMath && (a.spoilersRevealed === true) === (b.spoilersRevealed === true) && a.expandedBlocks === b.expandedBlocks && a.maxLines === b.maxLines && (a.codeBlock === true) === (b.codeBlock === true) && a.source === b.source && a.maxWidthVp === b.maxWidthVp && a.minWidthVp === b.minWidthVp &&
    a.fontSize === b.fontSize && a.reserve === b.reserve && a.foreground === b.foreground &&
    a.accent === b.accent && a.environment === b.environment;
}

function richSpecSnapshot(spec: DrawnRichTextSpec): DrawnRichTextSpec {
  return { source: spec.source, mathRevision: spec.mathRevision, scrollMath: spec.scrollMath, spoilersRevealed: spec.spoilersRevealed, expandedBlocks: spec.expandedBlocks, maxLines: spec.maxLines, codeBlock: spec.codeBlock, maxWidthVp: spec.maxWidthVp, minWidthVp: spec.minWidthVp,
    fontSize: spec.fontSize, reserve: spec.reserve, foreground: spec.foreground,
    accent: spec.accent, environment: spec.environment };
}

function richColor(color: ResourceColor): common2D.Color {
  const c = ColorMetrics.resourceColor(color);
  return { alpha: c.alpha, red: c.red, green: c.green, blue: c.blue };
}

export interface DrawnInlineEmojiPlacement {
  id: string;
  rect: common2D.Rect;
  fallback: text.Paragraph;
  fallbackY: number;
  color: common2D.Color;
}

export interface DrawnDocumentMediaPlacement {
  slides?: DrawnDocumentMedia[];
  key: string; media: DrawnDocumentMedia; x: number; y: number; width: number; height: number;
}

export interface DrawnTablePlacement {
  key: string;
  x: number;
  y: number;
  width: number;
  height: number;
  layout: DrawnRichTextLayout;
}

export class DrawnRichTextLayout {
  anchors: ReadonlyMap<string, number> = EMPTY_DRAWN_ANCHORS;
  readonly widgetOwners: Set<DrawnDocumentWidget> = new Set<DrawnDocumentWidget>();
  readonly widgets: DrawnDocumentWidgetPlacement[] = [];
  readonly icons: DrawnInlineIconPlacement[] = [];
  readonly tables: DrawnTablePlacement[] = [];
  readonly media: DrawnDocumentMediaPlacement[] = [];
  readonly maths: DrawnMathPlacement[] = [];
  readonly emojis: DrawnInlineEmojiPlacement[] = [];
  previewImage: DrawnAlbumRect | null = null;
  accessibilityText: string = '';
  emojiSizeVp: number = 0;
  density: number = 1;
  paragraph: DrawnRichParagraph;
  widthVp: number;
  heightVp: number;
  source: DrawnRichSource;
  hits: DrawnRichHit[];
  hitIndex: DrawnRichHitIndex;
  // Built once per paragraph: O(H) space/time; a busy URL lookup is O(1).
  readonly hitsByUrl: Map<string, DrawnRichHit[]> = new Map();
  constructor(paragraph: DrawnRichParagraph, widthVp: number, heightVp: number,
    source: DrawnRichSource, hits: DrawnRichHit[]) {
    if ((source.anchorNames?.length ?? 0) > 0) {
      const anchors = new Map<string, number>();
      for (const name of source.anchorNames ?? []) { anchors.set(name, 0); }
      this.anchors = anchors;
    }
    this.paragraph = paragraph; this.widthVp = widthVp; this.heightVp = heightVp;
    this.source = source; this.accessibilityText = source.content; this.hits = hits;
    this.hitIndex = new DrawnRichHitIndex(hits);
    for (const hit of hits) {
      if (hit.link.action !== undefined) { continue; }
      let group = this.hitsByUrl.get(hit.link.url);
      if (group === undefined) { group = []; this.hitsByUrl.set(hit.link.url, group); }
      group.push(hit);
    }
  }
}

export class DrawnRichTextLayouts {
  private units: DrawnTextUnits = new DrawnTextUnits();
  private cache: DrawnPlainLayoutCache<DrawnRichTextSpec, DrawnRichTextLayout> =
    new DrawnPlainLayoutCache<DrawnRichTextSpec, DrawnRichTextLayout>(sameRichSpec);
  private blockLabels: DrawnRichSourceCache | null = null;
  private blockLayouts: DrawnRichTextLayouts[] = [];
  private generation: number = 0;
  private environment: string = '';
  private failedSpec: DrawnRichTextSpec | null = null;

  prepare(ui: UIContext, spec: DrawnRichTextSpec): DrawnRichTextLayout {
    this.units.prepare(ui, spec.environment);
    const density: number = this.units.density;
    const fontPx: number = this.units.fp2px(spec.fontSize);
    const reservePx: number = this.units.fp2px(14);
    const linePx: number = this.units.fp2px(spec.fontSize * 1.34);
    const environment: string = `${spec.environment}:${density}:${fontPx}:${reservePx}:${linePx}`;
    if (this.environment !== environment) { this.failedSpec = null; this.environment = environment; }
    this.cache.prepare(environment);
    const hit = this.cache.get(spec);
    if (hit !== undefined) { return hit; }
    if (this.failedSpec !== null && sameRichSpec(this.failedSpec, spec)) {
      throw new Error('rich paragraph remains unavailable');
    }
    try {
      const result = spec.source.table !== undefined ? this.buildTable(ui, spec, density) : spec.source.blocks !== undefined ? this.buildBlocks(ui, spec, density) : this.build(spec, density, fontPx, reservePx, linePx);
      this.cache.put(richSpecSnapshot(spec), result);
      return result;
    } catch (error) {
      this.failedSpec = richSpecSnapshot(spec);
      throw error as Error;
    }
  }

  private buildBlocks(ui: UIContext, spec: DrawnRichTextSpec, density: number): DrawnRichTextLayout {
    const blocks = spec.source.blocks ?? [];
    const anchors: Map<string, number> = new Map<string, number>();
    let lastContentIndex = blocks.length - 1;
    while (lastContentIndex >= 0 && blocks[lastContentIndex].kind === 'anchor') { lastContentIndex--; }
    const document = new DrawnRichCompositeParagraph();
    const hits: DrawnRichHit[] = [];
    const emojis: DrawnInlineEmojiPlacement[] = [];
    const widgets: DrawnDocumentWidgetPlacement[] = [];
    const icons: DrawnInlineIconPlacement[] = [];
    const maths: DrawnMathPlacement[] = [];
    const media: DrawnDocumentMediaPlacement[] = [];
    const spoken: string[] = [];
    const tables: DrawnTablePlacement[] = [];
    let previewImage: DrawnAlbumRect | null = null;
    let previewTop: number = -1;
    let previewBottom: number = 0;
    const expanded = new Set<number>(spec.expandedBlocks ?? []);
    const accent = richColor(spec.accent);
    const background = richColor($r('app.color.code_surface'));
    let y: number = 0;
    let width: number = Math.max(0, spec.minWidthVp);
    let engineIndex: number = 0;
    const generation = ++this.generation;
    for (let i: number = 0; i < blocks.length; i++) {
      const block = blocks[i], framed = block.kind === 'pre' || block.kind === 'quote';
      if (block.kind === 'anchor') { anchors.set(block.anchorName ?? '', y); continue; }
      const labelBlock = block.kind === 'translation-label';
      if (block.preview && previewTop < 0) { previewTop = y; }
      const padding = framed || block.preview ? 9 : block.kind === 'list-item' ? 24 : 0;
      const innerWidth = Math.max(1, spec.maxWidthVp - padding * 2);
      if (block.kind === 'preview-image') {
        const height = Math.max(108, Math.min(188, innerWidth / (block.imageRatio ?? 1.5)));
        previewImage = { x: padding, y, width: innerWidth, height };
        const action: DrawnRichLink = { action: 'web-preview', start: 0, end: 0, label: '', url: '',
          hidesUrl: false, accessibilityFirst: true, accessibilityLabel: str('mb_web_link') };
        if (block.action !== undefined) {
          hits.push({ key: `${generation}:preview-image`, link: action, x: padding, y,
            widthVp: innerWidth, heightVp: height, accessible: true });
        }
        y += height + 6; width = spec.maxWidthVp; previewBottom = y;
        document.lastLine = { left: 0, width: width * density, baseline: y * density, ascent: 0 };
        continue;
      }
      if (block.article !== undefined) {
        const article = block.article;
        const hasPhoto = article.avatar !== undefined || (article.avatarMini ?? '') !== '';
        const textWidth = Math.max(1, spec.maxWidthVp - 20 - (hasPhoto ? 50 : 0));
        while (this.blockLayouts.length < engineIndex + 2) { this.blockLayouts.push(new DrawnRichTextLayouts()); }
        const titleEngine = this.blockLayouts[engineIndex++];
        const title = block.title !== undefined && block.title.content !== '' ? titleEngine.prepare(ui, {
          source: block.title, maxWidthVp: textWidth, minWidthVp: 0,
          fontSize: spec.fontSize, reserve: '', maxLines: 3, foreground: spec.foreground,
          accent: spec.accent, environment: spec.environment }) : null;
        const titleHeight = title?.heightVp ?? 0;
        const description = this.blockLayouts[engineIndex++].prepare(ui, {
          source: block.source, maxWidthVp: textWidth, minWidthVp: 0, fontSize: Math.max(11, spec.fontSize - 2),
          reserve: '', maxLines: Math.max(1, 4 - (title?.paragraph.getLineCount() ?? 0)),
          foreground: spec.foreground, accent: spec.accent, environment: spec.environment });
        const gap = titleHeight > 0 ? 6 : 0;
        const height = Math.max(60, 18 + titleHeight + gap + description.heightVp);
        if (title !== null) { document.parts.push({ paragraph: title.paragraph, x: 10 * density, y: (y + 8) * density }); }
        document.parts.push({ paragraph: description.paragraph, x: 10 * density, y: (y + 8 + titleHeight + gap) * density });
        if (hasPhoto) { widgets.push({ widget: article, x: spec.maxWidthVp - 44, y: y + 8, width: 44, height: 44 }); }
        const label = [title?.source.content ?? '', description.source.content].filter((value: string): boolean => value !== '').join(' · ');
        const link: DrawnRichLink = { start: 0, end: 0, label, url: article.url ?? '', hidesUrl: true,
          accessibilityLabel: label, accessibilityFirst: true };
        hits.push({ key: `${generation}:article:${i}`, link, x: 0, y, widthVp: spec.maxWidthVp, heightVp: height, accessible: true });
        spoken.push(label);
        if (block.divider) { document.backgrounds.push(new DrawnRichBlockBackground({ left: 10 * density,
          top: (y + height) * density, right: spec.maxWidthVp * density, bottom: (y + height) * density + 1 }, 0, background, accent, 0)); }
        y += height + (block.divider ? 1 / density : 0); width = spec.maxWidthVp;
        document.lastLine = { left: 0, width: width * density, baseline: y * density, ascent: 0 };
        continue;
      }
      if (block.widget !== undefined) {
        const widget = block.widget;
        const height = widget.kind === 'message-sticker' ? widget.height * Math.min(1, spec.maxWidthVp / widget.width) : widget.kind === 'message-dice' ? Math.min(150, spec.maxWidthVp) : widget.kind === 'message-video-note' ? Math.min(180, spec.maxWidthVp) : widget.kind === 'message-location' ? widget.height : (widget.kind === 'message-contact' || widget.kind === 'message-poll' || widget.kind === 'message-game' || widget.kind === 'message-gift' || widget.kind === 'message-paid-media' || widget.kind === 'message-giveaway') ? widget.height : widget.kind === 'message-voice' ? 60 : widget.kind === 'message-audio' ? 148 : widget.kind === 'message-file' ? 80 : (widget.kind === 'html-embed' || widget.kind === 'video-embed') ? documentEmbedHeight(widget, spec.maxWidthVp) : widget.kind === 'map' ? Math.max(80, Math.min(300, spec.maxWidthVp * widget.height / widget.width)) : (widget.kind === 'post-author' || widget.kind === 'chat-link') ? 56 : 72;
        widgets.push({ widget, x: 0, y, width: widget.kind === 'message-contact' ? widget.width : widget.kind === 'message-sticker' ? Math.min(widget.width, spec.maxWidthVp) : (widget.kind === 'message-video-note' || widget.kind === 'message-dice') ? height : spec.maxWidthVp, height });
        y += height + 6; width = widget.kind === 'message-contact' ? widget.width : widget.kind === 'message-sticker' ? Math.min(widget.width, spec.maxWidthVp) : (widget.kind === 'message-video-note' || widget.kind === 'message-dice') ? height : spec.maxWidthVp;
        document.lastLine = { left: 0, width: width * density, baseline: y * density, ascent: 0 };
        continue;
      }
      if (block.gallery !== undefined && block.gallery.length > 0) {
        const gallery = block.gallery;
        const ratios = gallery.map((item: DrawnDocumentMedia): number => item.width / item.height);
        if (block.kind === 'slideshow') {
          let sum: number = 0;
          for (const ratio of ratios) { sum += ratio; }
          const height = Math.max(100, Math.min(300, spec.maxWidthVp / Math.max(0.5, sum / ratios.length)));
          media.push({ key: `slideshow:${block.offset}`, media: gallery[0], slides: gallery,
            x: 0, y, width: spec.maxWidthVp, height });
          y += height + 6;
        } else {
          // Same bounded linear mosaic strategy as ordinary albums. Packing
          // runs only when geometry changes, never on download/playback ticks.
          const rows = packAlbumRows(ratios, spec.maxWidthVp);
          for (const row of rows) {
            let x: number = 0, height: number = 0;
            for (const cell of row) {
              const item = gallery[cell.idx];
              media.push({ key: item.key, media: item, x, y, width: cell.width, height: cell.height });
              x += cell.width + 2; height = Math.max(height, cell.height);
            }
            y += height + 2;
          }
          y += 4;
        }
        width = spec.maxWidthVp;
        document.lastLine = { left: 0, width: width * density, baseline: y * density, ascent: 0 };
        continue;
      }
      if (block.kind === 'media' && block.media !== undefined) {
        const height = Math.max(100, Math.min(300, spec.maxWidthVp * block.media.height / block.media.width));
        media.push({ key: block.media.key, media: block.media, x: 0, y, width: spec.maxWidthVp, height });
        y += height + 6; width = spec.maxWidthVp;
        document.lastLine = { left: 0, width: width * density, baseline: y * density, ascent: 0 };
        continue;
      }
      if (block.kind === 'buttons') {
        const buttons = block.buttons ?? [];
        const preferred = buttons.map((button: DrawnRichButton): number => textWidthEstimate(button.source.content, 14) + 28);
        const boxes = drawnPageButtonBoxes(preferred, spec.maxWidthVp, block.buttonAlign ?? 'fill');
        let bottom = y;
        for (let b: number = 0; b < boxes.length; b++) {
          const button = buttons[b], box = boxes[b];
          if (engineIndex === this.blockLayouts.length) { this.blockLayouts.push(new DrawnRichTextLayouts()); }
          const filled = button.style !== '' && button.style !== 'link';
          const label = this.blockLayouts[engineIndex++].prepare(ui, { source: button.source,
            maxWidthVp: Math.max(1, box.width - 16), minWidthVp: 0, fontSize: 14, reserve: '', maxLines: 1,
            foreground: filled ? Color.White : spec.accent, accent: filled ? Color.White : spec.accent,
            environment: spec.environment, mathRevision: spec.mathRevision });
          const x = box.x + (box.width - label.widthVp) / 2;
          const top = y + box.y + Math.max(0, (box.height - label.heightVp) / 2);
          if (button.style !== 'link') {
            document.backgrounds.push(new DrawnRichBlockBackground({ left: box.x * density, top: (y + box.y) * density,
              right: (box.x + box.width) * density, bottom: (y + box.y + box.height) * density }, 7 * density,
              richColor(botButtonBg(button.style, $r('app.color.code_surface'))), accent, 0));
          }
          document.parts.push({ paragraph: label.paragraph, x: x * density, y: top * density });
          for (const anchor of label.anchors) { anchors.set(anchor[0], anchor[1] + top); }
          spoken.push(label.accessibilityText);
          appendDrawnIcons(icons, label.icons, x, top);
          for (const math of label.maths) {
            maths.push({ key: math.key, expression: math.expression, renderSize: math.renderSize, color: math.color,
              ready: math.ready, fallback: math.fallback, fallbackY: math.fallbackY + top * density,
              rect: { left: math.rect.left + x * density, right: math.rect.right + x * density,
                top: math.rect.top + top * density, bottom: math.rect.bottom + top * density } });
          }
          if (button.action.kind !== 'disabled') {
            const action: DrawnRichLink = { action: 'page-button', button: button.action,
              start: 0, end: 0, label: label.accessibilityText, url: '', hidesUrl: false,
              accessibilityLabel: label.accessibilityText, accessibilityFirst: true };
            hits.push({ key: `${generation}:button:${block.offset}:${b}`, link: action,
              x: box.x, y: y + box.y, widthVp: box.width, heightVp: box.height, accessible: true });
          }
          bottom = Math.max(bottom, y + box.y + box.height);
        }
        y = bottom + 6; width = spec.maxWidthVp;
        document.lastLine = { left: 0, width: width * density, baseline: y * density, ascent: 0 };
        continue;
      }
      if (block.kind === 'table' || block.kind === 'math') {
        if (engineIndex === this.blockLayouts.length) { this.blockLayouts.push(new DrawnRichTextLayouts()); }
        const layout = this.blockLayouts[engineIndex++].prepare(ui, { source: block.source, mathRevision: spec.mathRevision, scrollMath: block.kind === 'math',
          maxWidthVp: spec.maxWidthVp, minWidthVp: 0, fontSize: 14, reserve: '',
          foreground: spec.foreground, accent: spec.accent, environment: spec.environment });
        for (const anchor of layout.anchors) { anchors.set(anchor[0], anchor[1] + y); }
        tables.push({ key: `${block.kind}:${block.offset}`, layout, x: 0, y,
          width: Math.min(spec.maxWidthVp, layout.widthVp), height: layout.heightVp });
        y += layout.heightVp + 6; width = Math.max(width, Math.min(spec.maxWidthVp, layout.widthVp));
        if (block.title !== undefined && block.title.content !== '') {
          if (engineIndex === this.blockLayouts.length) { this.blockLayouts.push(new DrawnRichTextLayouts()); }
          const caption = this.blockLayouts[engineIndex++].prepare(ui, { source: block.title, mathRevision: spec.mathRevision,
            maxWidthVp: spec.maxWidthVp, minWidthVp: 0, fontSize: 12, reserve: '',
            foreground: spec.foreground, accent: spec.accent, environment: spec.environment });
          for (const anchor of caption.anchors) { anchors.set(anchor[0], anchor[1] + y); }
          document.parts.push({ paragraph: caption.paragraph, x: 0, y: y * density });
          for (const hit of caption.hits) { hits.push({ key: `${generation}:caption:${i}:${hit.key}`, link: hit.link,
            x: hit.x, y: y + hit.y, widthVp: hit.widthVp, heightVp: hit.heightVp, accessible: hit.accessible }); }
          appendDrawnIcons(icons, caption.icons, 0, y);
          for (const math of caption.maths) {
            maths.push({ key: math.key, expression: math.expression, renderSize: math.renderSize, color: math.color,
              ready: math.ready, fallback: math.fallback, fallbackY: math.fallbackY + y * density,
              rect: { left: math.rect.left, right: math.rect.right, top: math.rect.top + y * density, bottom: math.rect.bottom + y * density } });
          }
          spoken.push(caption.accessibilityText); y += caption.heightVp + 6;
          width = Math.max(width, caption.widthVp);
        }
        document.lastLine = { left: 0, width: width * density, baseline: y * density, ascent: 0 };
        continue;
      }
      if (block.kind === 'divider') {
        document.backgrounds.push(new DrawnRichBlockBackground({ left: 0, top: (y + 5) * density,
          right: spec.maxWidthVp * density, bottom: (y + 6) * density }, 0, background, accent, 0));
        y += 12; width = spec.maxWidthVp;
        document.lastLine = { left: 0, width: width * density, baseline: y * density, ascent: 0 };
        continue;
      }
      if (block.kind === 'list-item') {
        const marker = this.blockLabel(ui, block.marker ?? '•', 22, spec, engineIndex++);
        document.parts.push({ paragraph: marker.paragraph, x: 0, y: y * density });
        spoken.push(block.marker ?? '•');
      }
      if (block.kind === 'details' && block.title !== undefined) {
        if (engineIndex === this.blockLayouts.length) { this.blockLayouts.push(new DrawnRichTextLayouts()); }
        const title = this.blockLayouts[engineIndex++].prepare(ui, { source: block.title, mathRevision: spec.mathRevision,
          maxWidthVp: spec.maxWidthVp - 24, minWidthVp: 0, fontSize: spec.fontSize, reserve: '',
          foreground: spec.accent, accent: spec.accent, environment: spec.environment });
        for (const anchor of title.anchors) { anchors.set(anchor[0], anchor[1] + y); }
        appendDrawnIcons(icons, title.icons, 24, y);
        for (const math of title.maths) {
          maths.push({ key: math.key, expression: math.expression, renderSize: math.renderSize, color: math.color,
            ready: math.ready, fallback: math.fallback, fallbackY: math.fallbackY + y * density,
            rect: { left: math.rect.left + 24 * density, right: math.rect.right + 24 * density,
              top: math.rect.top + y * density, bottom: math.rect.bottom + y * density } });
        }
        const open = (block.initiallyOpen === true) !== expanded.has(block.offset);
        const arrow = this.blockLabel(ui, open ? '▾' : '▸', 22, spec, engineIndex++);
        document.parts.push({ paragraph: arrow.paragraph, x: 0, y: y * density });
        document.parts.push({ paragraph: title.paragraph, x: 24 * density, y: y * density });
        const label = title.accessibilityText + ' · ' + str(open ? 'mb_collapse_quote' : 'mb_expand_quote');
        const action: DrawnRichLink = { action: 'quote', blockOffset: block.offset, start: 0, end: 0,
          label, url: '', hidesUrl: false, accessibilityFirst: true, accessibilityLabel: label };
        hits.push({ key: `${generation}:details:${i}`, link: action, x: 0, y,
          widthVp: spec.maxWidthVp, heightVp: Math.max(28, title.heightVp), accessible: true });
        spoken.push(label); y += Math.max(28, title.heightVp) + 6; width = spec.maxWidthVp;
        document.lastLine = { left: 0, width: width * density, baseline: y * density, ascent: 0 };
        if (!open) { continue; }
      }
      const top = y;
      if (framed) { y += 7; }
      if (block.kind === 'pre') {
        const label = block.language !== '' ? block.language : str('mb_code');
        const title = this.blockLabel(ui, label + '    ' + str('copy'), innerWidth, spec, engineIndex++);
        document.parts.push({ paragraph: title.paragraph, x: padding * density, y: y * density });
        const action: DrawnRichLink = { start: 0, end: block.source.content.length,
          label: block.source.content, url: '', hidesUrl: false, action: 'copy',
          accessibilityLabel: str('copy'), accessibilityFirst: true };
        hits.push({ key: `${generation}:copy:${i}`, link: action, x: padding, y,
          widthVp: innerWidth, heightVp: Math.max(26, title.heightVp), accessible: true });
        y += Math.max(26, title.heightVp) + 5;
      }
      if (engineIndex === this.blockLayouts.length) { this.blockLayouts.push(new DrawnRichTextLayouts()); }
      const bodySpec: DrawnRichTextSpec = {
        source: block.source, mathRevision: spec.mathRevision, expandedBlocks: spec.expandedBlocks, spoilersRevealed: spec.spoilersRevealed, maxWidthVp: innerWidth, minWidthVp: 0,
        fontSize: block.fontSize ?? (labelBlock ? 11 : spec.fontSize), reserve: i === lastContentIndex && !framed ? spec.reserve : '',
        foreground: block.kind === 'preview-site' || block.kind === 'preview-action' ? spec.accent : spec.foreground,
        accent: spec.accent, environment: spec.environment,
        maxLines: block.lineLimit ?? (block.expandable && !expanded.has(block.offset) ? 4 : undefined),
        codeBlock: block.kind === 'pre'
      };
      const child = this.blockLayouts[engineIndex++];
      const retained = this.cache.get(bodySpec);
      if (retained !== undefined) { child.cache.put(richSpecSnapshot(bodySpec), retained); }
      const body = retained ?? child.prepare(ui, bodySpec);
      for (const anchor of body.anchors) { anchors.set(anchor[0], anchor[1] + y); }
      spoken.push(body.accessibilityText);
      for (const item of body.widgets) { widgets.push({ widget: item.widget, x: item.x + padding, y: item.y + y, width: item.width, height: item.height }); }
      for (const item of body.media) { media.push({ key: `${i}:${item.key}`, media: item.media, slides: item.slides,
        x: item.x + padding, y: item.y + y, width: item.width, height: item.height }); }
      for (const table of body.tables) { tables.push({ key: `${i}:${table.key}`, layout: table.layout,
        x: table.x + padding, y: table.y + y, width: table.width, height: table.height }); }
      document.parts.push({ paragraph: body.paragraph, x: padding * density, y: y * density });
      for (const hit of body.hits) {
        if (labelBlock || block.preview) { continue; }
        hits.push({ key: `${generation}:${i}:${hit.key}`, link: hit.link, x: hit.x + padding,
          y: hit.y + y, widthVp: hit.widthVp, heightVp: hit.heightVp, accessible: hit.accessible });
      }
      appendDrawnIcons(icons, body.icons, padding, y);
      for (const math of body.maths) {
        maths.push({ key: math.key, expression: math.expression, renderSize: math.renderSize, color: math.color,
          ready: math.ready, fallback: math.fallback, fallbackY: math.fallbackY + y * density,
          rect: { left: math.rect.left + padding * density, right: math.rect.right + padding * density,
            top: math.rect.top + y * density, bottom: math.rect.bottom + y * density } });
      }
      for (const emoji of body.emojis) {
        emojis.push({ id: emoji.id, fallback: emoji.fallback, color: emoji.color,
          fallbackY: emoji.fallbackY + y * density,
          rect: { left: emoji.rect.left + padding * density, right: emoji.rect.right + padding * density,
            top: emoji.rect.top + y * density, bottom: emoji.rect.bottom + y * density } });
      }
      const line = body.paragraph.getLineMetrics(body.paragraph.getLineCount() - 1);
      document.lastLine = line !== undefined ? { left: line.left + padding * density,
        width: line.width, baseline: line.baseline + y * density, ascent: line.ascent } : undefined;
      if (block.action !== undefined) {
        const action: DrawnRichLink = { action: block.action, start: 0, end: 0, label: block.source.content,
          url: '', hidesUrl: false, accessibilityFirst: true, accessibilityLabel: block.source.content };
        hits.push({ key: `${generation}:translation:${i}`, link: action, x: padding, y,
          widthVp: body.widthVp, heightVp: Math.max(24, body.heightVp), accessible: true });
      }
      y += labelBlock ? Math.max(24, body.heightVp) : body.heightVp;
      width = Math.max(width, framed ? spec.maxWidthVp : body.widthVp + padding);
      if (block.expandable) {
        y += 4;
        const label = str(expanded.has(block.offset) ? 'mb_collapse_quote' : 'mb_expand_quote');
        const control = this.blockLabel(ui, label, innerWidth, spec, engineIndex++);
        document.parts.push({ paragraph: control.paragraph, x: padding * density, y: y * density });
        const action: DrawnRichLink = { start: 0, end: 0, label, url: '', hidesUrl: false,
          action: 'quote', blockOffset: block.offset, accessibilityLabel: label, accessibilityFirst: true };
        hits.push({ key: `${generation}:quote:${i}`, link: action, x: padding, y,
          widthVp: innerWidth, heightVp: Math.max(24, control.heightVp), accessible: true });
        y += Math.max(24, control.heightVp);
      }
      if (framed) {
        y += 7;
        document.backgrounds.push(new DrawnRichBlockBackground({ left: 0, top: top * density,
          right: spec.maxWidthVp * density, bottom: y * density }, 7 * density, background,
          accent, block.kind === 'quote' ? 3 * density : 0));
        document.lastLine = { left: 0, width: spec.maxWidthVp * density,
          baseline: y * density, ascent: 0 };
      }
      if (block.preview) { previewBottom = y; width = spec.maxWidthVp; }
      if (i < lastContentIndex) { y += block.preview ? 3 : 6; }
    }
    if (previewTop >= 0) {
      document.backgrounds.push(new DrawnRichBlockBackground({ left: 0, top: previewTop * density,
        right: 3 * density, bottom: previewBottom * density }, density, accent, accent, 0));
    }
    this.blockLayouts.length = engineIndex;
    document.height = y * density;
    const result = new DrawnRichTextLayout(document, width, y, spec.source, hits);
    if (anchors.size > 0) { result.anchors = anchors; }
    result.previewImage = previewImage;
    for (const table of tables) { result.tables.push(table); }
    result.accessibilityText = spoken.join('\n');
    result.density = density; result.emojiSizeVp = spec.fontSize + 3;
    for (const emoji of emojis) { result.emojis.push(emoji); }
    for (const item of widgets) { result.widgets.push(item); result.widgetOwners.add(item.widget); }
    appendDrawnIcons(result.icons, icons, 0, 0);
    for (const math of maths) { result.maths.push(math); }
    for (const item of media) { result.media.push(item); }
    return result;
  }

  private buildTable(ui: UIContext, spec: DrawnRichTextSpec, density: number): DrawnRichTextLayout {
    const table = spec.source.table!;
    const anchors: Map<string, number> = new Map<string, number>();
    const grid = drawnTableGrid(table.rows);
    if (grid === null) { throw new Error('invalid structured table spans'); }
    const widths: number[] = new Array<number>(grid.columns).fill(48);
    for (const position of grid.cells) {
      const needed = Math.min(200, Math.max(48,
        (textWidthEstimate(position.cell.source.content, spec.fontSize) + 20) / position.columns));
      for (let c: number = position.column; c < position.column + position.columns; c++) {
        widths[c] = Math.max(widths[c], needed);
      }
    }
    const xs: number[] = [0];
    for (const width of widths) { xs.push(xs[xs.length - 1] + width); }
    const heights: number[] = new Array<number>(grid.rows).fill(30);
    const bodies: DrawnRichTextLayout[] = [];
    for (let i: number = 0; i < grid.cells.length; i++) {
      const pos = grid.cells[i];
      if (i === this.blockLayouts.length) { this.blockLayouts.push(new DrawnRichTextLayouts()); }
      const body = this.blockLayouts[i].prepare(ui, { source: pos.cell.source, mathRevision: spec.mathRevision,
        maxWidthVp: xs[pos.column + pos.columns] - xs[pos.column] - 20, minWidthVp: 0,
        fontSize: spec.fontSize, reserve: '', foreground: spec.foreground, accent: spec.accent,
        environment: spec.environment });
      bodies.push(body);
      if (pos.rows === 1) { heights[pos.row] = Math.max(heights[pos.row], body.heightVp + 12); }
    }
    // Satisfy merged-cell heights after ordinary rows; each span is bounded.
    for (let i: number = 0; i < grid.cells.length; i++) {
      const pos = grid.cells[i];
      if (pos.rows === 1) { continue; }
      let current: number = 0;
      for (let r: number = pos.row; r < pos.row + pos.rows; r++) { current += heights[r]; }
      const extra = Math.max(0, bodies[i].heightVp + 12 - current) / pos.rows;
      for (let r: number = pos.row; r < pos.row + pos.rows; r++) { heights[r] += extra; }
    }
    const ys: number[] = [0];
    for (const height of heights) { ys.push(ys[ys.length - 1] + height); }
    const document = new DrawnRichCompositeParagraph();
    const hits: DrawnRichHit[] = [], spoken: string[] = [];
    const tableIcons: DrawnInlineIconPlacement[] = [];
    const tableMaths: DrawnMathPlacement[] = [];
    const border = richColor('#8C6E7887'), tint = richColor('#22808A96');
    const generation = ++this.generation;
    for (let i: number = 0; i < grid.cells.length; i++) {
      const pos = grid.cells[i], body = bodies[i];
      const left = xs[pos.column], right = xs[pos.column + pos.columns];
      const top = ys[pos.row], bottom = ys[pos.row + pos.rows];
      const cellWidth = right - left - 20;
      const x = left + 10 + (pos.cell.align === 'right' ? cellWidth - body.widthVp
        : pos.cell.align === 'center' ? (cellWidth - body.widthVp) / 2 : 0);
      const y = top + 6 + (pos.cell.valign === 'bottom' ? bottom - top - 12 - body.heightVp
        : pos.cell.valign === 'middle' ? (bottom - top - 12 - body.heightVp) / 2 : 0);
      if (pos.cell.header || (table.striped && pos.row % 2 === 1)) {
        document.backgrounds.push(new DrawnRichBlockBackground({ left: left * density, top: top * density,
          right: right * density, bottom: bottom * density }, 0, tint, tint, 0));
      }
      if (table.bordered) {
        if (document.borderPen === null) {
          document.borderPen = new drawing.Pen(); document.borderPen.setAntiAlias(true);
          document.borderPen.setColor(border); document.borderPen.setStrokeWidth(density);
        }
        document.borders.push({ left: left * density + density / 2, top: top * density + density / 2,
          right: right * density - density / 2, bottom: bottom * density - density / 2 });
      }
      document.parts.push({ paragraph: body.paragraph, x: x * density, y: y * density });
      for (const anchor of body.anchors) { anchors.set(anchor[0], anchor[1] + y); }
      spoken.push(body.accessibilityText);
      appendDrawnIcons(tableIcons, body.icons, x, y);
      for (const math of body.maths) {
        tableMaths.push({ key: math.key, expression: math.expression, renderSize: math.renderSize, color: math.color,
          ready: math.ready, fallback: math.fallback, fallbackY: math.fallbackY + y * density,
          rect: { left: math.rect.left + x * density, right: math.rect.right + x * density,
            top: math.rect.top + y * density, bottom: math.rect.bottom + y * density } });
      }
      for (const hit of body.hits) { hits.push({ key: `${generation}:${i}:${hit.key}`, link: hit.link,
        x: hit.x + x, y: hit.y + y, widthVp: hit.widthVp, heightVp: hit.heightVp, accessible: hit.accessible }); }
    }
    this.blockLayouts.length = grid.cells.length;
    document.height = ys[ys.length - 1] * density;
    document.lastLine = { left: 0, width: xs[xs.length - 1] * density, baseline: document.height, ascent: 0 };
    const result = new DrawnRichTextLayout(document, xs[xs.length - 1], document.height / density, spec.source, hits);
    if (anchors.size > 0) { result.anchors = anchors; }
    result.accessibilityText = spoken.join(' / '); result.density = density;
    appendDrawnIcons(result.icons, tableIcons, 0, 0);
    for (const math of tableMaths) { result.maths.push(math); }
    return result;
  }

  private blockLabel(ui: UIContext, label: string, width: number, spec: DrawnRichTextSpec,
    engineIndex: number): DrawnRichTextLayout {
    if (engineIndex === this.blockLayouts.length) { this.blockLayouts.push(new DrawnRichTextLayouts()); }
    // Label sources are immutable and cached by this physical block engine.
    if (this.blockLabels === null) { this.blockLabels = new DrawnRichSourceCache(); }
    const source = this.blockLabels.prepare(label, EMPTY_DRAWN_LABEL_ENTITIES);
    if (source === null) { throw new Error('invalid block control label'); }
    return this.blockLayouts[engineIndex].prepare(ui, { source, maxWidthVp: width, minWidthVp: 0,
      fontSize: 11, reserve: '', foreground: spec.accent, accent: spec.accent, environment: spec.environment });
  }

  private build(spec: DrawnRichTextSpec, density: number, fontPx: number, reservePx: number,
    linePx: number): DrawnRichTextLayout {
    const maxPx: number = Math.floor(spec.maxWidthVp * density);
    if (!(maxPx > 0) || !(fontPx > 0)) { throw new Error('invalid rich paragraph geometry'); }
    const rtl = spec.source.rtl === true && spec.codeBlock !== true && spec.scrollMath !== true;
    const foreground = richColor(spec.foreground);
    const accent = richColor(spec.accent);
    // Code remains in the same shaped paragraph, preserving UTF-16 offsets,
    // wrapping and mixed-script fallback. Resolve its paint once per layout.
    let codeBackground: text.RectStyle | undefined = undefined;
    let markedBackground: text.RectStyle | undefined = undefined;
    const paragraphBuilder = new text.ParagraphBuilder({
      textStyle: { fontSize: fontPx, color: foreground, heightOnly: true, heightScale: linePx / fontPx,
        halfLeading: true },
      maxLines: spec.maxLines,
      wordBreak: text.WordBreak.BREAK_WORD, textDirection: rtl ? text.TextDirection.RTL : text.TextDirection.LTR,
      align: rtl ? text.TextAlign.RIGHT : text.TextAlign.LEFT
    }, text.FontCollection.getGlobalInstance());
    // A placeholder occupies ONE UTF-16 position. Keep original source offsets
    // for copy/accessibility; project each run/link once, never scan all icons per link.
    let paragraphOffset: number = 0;
    const linkRanges: text.Range[] = [];
    const emojiFallbacks: text.Paragraph[] = [];
    const emojiIds: string[] = [];
    const emojiColors: common2D.Color[] = [];
    const emojiHidden: boolean[] = [];
    const hiddenLinks: boolean[] = [];
    const spoilerRanges: text.Range[] = [];
    const spoken: string[] = [];
    const fallbacks: Map<string, text.Paragraph> = new Map();
    const mathPlacements: DrawnMathPlacement[] = [];
    const inlineIcons: DrawnInlineIconPlacement[] = [];
    const placeholderIcon: number[] = [];
    const placeholderMath: number[] = [];
    const placeholderEmoji: number[] = [];
    let paragraphWidth = maxPx;
    const emojiPx: number = (spec.fontSize + 3) * density;
    for (const run of spec.source.runs) {
      if (run.code && codeBackground === undefined) {
        codeBackground = { color: richColor($r('app.color.code_surface')),
          leftTopRadius: 3 * density, rightTopRadius: 3 * density,
          rightBottomRadius: 3 * density, leftBottomRadius: 3 * density };
      }
      if (run.marked && markedBackground === undefined) { markedBackground = { color: richColor($r('app.color.select_highlight')), leftTopRadius: 0, rightTopRadius: 0, rightBottomRadius: 0, leftBottomRadius: 0 }; }
      const hidden = run.spoiler && spec.spoilersRevealed !== true;
      const color: common2D.Color = hidden ? { alpha: 0, red: 0, green: 0, blue: 0 } :
        (run.link || run.url !== '' ? accent : foreground);
      spoken.push(hidden ? str('mb_spoiler') : run.text);
      const runStyle: text.TextStyle = { fontSize: fontPx, color,
        heightOnly: true, heightScale: linePx / fontPx, halfLeading: true,
        badgeType: run.script === 1 ? text.TextBadgeType.TEXT_SUPERSCRIPT : run.script === -1 ? text.TextBadgeType.TEXT_SUBSCRIPT : undefined,
        fontFamilies: run.code ? ['monospace'] : undefined,
        fontWeight: run.bold ? text.FontWeight.W700 : text.FontWeight.W400,
        fontStyle: run.italic ? text.FontStyle.ITALIC : text.FontStyle.NORMAL,
        decoration: { textDecoration: run.strike ? text.TextDecorationType.LINE_THROUGH :
          (run.underline ? text.TextDecorationType.UNDERLINE : text.TextDecorationType.NONE), color }
      };
      // Omit optional native background fields entirely for ordinary text.
      // Passing an own property with undefined is not equivalent to omission
      // in every platform TextStyle conversion path.
      if (!hidden && run.marked && markedBackground !== undefined) { runStyle.backgroundRect = markedBackground; }
      else if (run.code && !hidden && !spec.codeBlock && codeBackground !== undefined) { runStyle.backgroundRect = codeBackground; }
      paragraphBuilder.pushStyle(runStyle);
      const length: number = run.customEmojiId === '' && run.math === undefined && run.icon === undefined ? run.text.length : 1;
      if (run.url !== '') { linkRanges.push({ start: paragraphOffset, end: paragraphOffset + length }); hiddenLinks.push(hidden); }
      if (hidden) { spoilerRanges.push({ start: paragraphOffset, end: paragraphOffset + length }); }
      paragraphOffset += length;
      if (run.icon !== undefined) {
        const scale = Math.min(density, maxPx / run.icon.width, 300 * density / run.icon.height);
        const width = run.icon.width * scale, height = run.icon.height * scale;
        paragraphBuilder.addPlaceholder({ width, height, align: text.PlaceholderAlignment.CENTER_OF_ROW_BOX,
          baseline: text.TextBaseline.ALPHABETIC, baselineOffset: 0 });
        placeholderIcon.push(hidden ? -1 : inlineIcons.length); placeholderMath.push(-1); placeholderEmoji.push(-1);
        if (!hidden) { inlineIcons.push({ icon: run.icon, x: 0, y: 0, width: width / density, height: height / density }); }
      } else if (run.math !== undefined) {
        const expression = run.math.trim();
        const argb = ((color.alpha << 24) | (color.red << 16) | (color.green << 8) | color.blue) >>> 0;
        const renderSize = fontPx * 2;
        const key = mathKeyOf(expression, renderSize, argb);
        const bitmap = mathMetricsFor(key);
        const fallbackBuilder = new text.ParagraphBuilder({ textStyle: { fontSize: fontPx,
          fontFamilies: ['monospace'], color }, textDirection: text.TextDirection.LTR }, text.FontCollection.getGlobalInstance());
        fallbackBuilder.addText(run.text); const fallback = fallbackBuilder.build(); fallback.layoutSync(maxPx);
        let width = bitmap !== undefined ? bitmap.width / 2 : Math.max(1, fallback.getLongestLine());
        let height = bitmap !== undefined ? bitmap.height / 2 : fallback.getHeight();
        if (!spec.scrollMath && width > maxPx) { height *= maxPx / width; width = maxPx; }
        paragraphWidth = Math.max(paragraphWidth, width);
        paragraphBuilder.addPlaceholder({ width, height, align: text.PlaceholderAlignment.CENTER_OF_ROW_BOX,
          baseline: text.TextBaseline.ALPHABETIC, baselineOffset: 0 });
        placeholderIcon.push(-1); placeholderMath.push(mathPlacements.length); placeholderEmoji.push(-1);
        mathPlacements.push({ key, expression, renderSize, color: argb, ready: bitmap !== undefined,
          rect: { left: 0, top: 0, right: width, bottom: height }, fallback, fallbackY: 0 });
      } else if (run.customEmojiId === '') { paragraphBuilder.addText(run.text); }
      else {
        paragraphBuilder.addPlaceholder({ width: emojiPx, height: emojiPx,
          align: text.PlaceholderAlignment.CENTER_OF_ROW_BOX, baseline: text.TextBaseline.ALPHABETIC,
          baselineOffset: 0 });
        const fallbackKey: string = `${run.text}:${run.link || run.url !== ''}`;
        let fallback = fallbacks.get(fallbackKey);
        if (fallback === undefined) {
          const builder = new text.ParagraphBuilder({ textStyle: { fontSize: fontPx, color },
            maxLines: 1, align: text.TextAlign.CENTER, textDirection: text.TextDirection.LTR },
            text.FontCollection.getGlobalInstance());
          builder.addText(run.text); fallback = builder.build(); fallback.layoutSync(emojiPx);
          fallbacks.set(fallbackKey, fallback);
        }
        placeholderIcon.push(-1); placeholderMath.push(-1); placeholderEmoji.push(emojiIds.length);
        emojiHidden.push(hidden); emojiIds.push(run.customEmojiId); emojiColors.push(color); emojiFallbacks.push(fallback);
      }
      paragraphBuilder.popStyle();
    }
    if (spec.reserve !== '') {
      // Keep the existing rich shell's transparent time reservation, including
      // its 14fp wrapped-line height. Footer painting still belongs to the shell.
      paragraphBuilder.pushStyle({ fontSize: reservePx, color: { alpha: 0, red: 0, green: 0, blue: 0 },
        heightOnly: true, heightScale: linePx / reservePx, halfLeading: true });
      paragraphBuilder.addText(spec.reserve);
      paragraphBuilder.popStyle();
    }
    const paragraph = paragraphBuilder.build();
    paragraph.layoutSync(paragraphWidth);
    // getLongestLine may exclude trailing whitespace. Outgoing timeReserve
    // ends with spaces for the status icon; include their actual laid-out
    // boxes instead of losing the slot or doing a second paragraph layout.
    let reservedRight: number = 0;
    if (spec.reserve !== '') {
      const reserveBoxes = paragraph.getRectsForRange({ start: paragraphOffset,
        end: paragraphOffset + spec.reserve.length }, text.RectWidthStyle.TIGHT, text.RectHeightStyle.TIGHT);
      if (reserveBoxes.length === 0) { throw new Error('missing rich footer reservation'); }
      for (const box of reserveBoxes) { reservedRight = Math.max(reservedRight, rtl ? maxPx - box.rect.left : box.rect.right); }
    }
    const widthPx: number = Math.min(paragraphWidth, Math.max(Math.ceil(paragraph.getLongestLine()), Math.ceil(reservedRight),
      Math.min(maxPx, spec.minWidthVp * density)));
    const shiftX = rtl ? widthPx - maxPx : 0;
    const heightPx: number = Math.ceil(paragraph.getHeight());
    if (!Number.isFinite(widthPx) || !Number.isFinite(heightPx) || widthPx <= 0 || heightPx <= 0) {
      throw new Error('invalid rich paragraph metrics');
    }
    const hits: DrawnRichHit[] = [];
    const generation: number = ++this.generation;
    for (let index: number = 0; index < spec.source.links.length; index++) {
      if (hiddenLinks[index]) { continue; }
      const link = spec.source.links[index];
      const boxes: DrawnRichRect[] = paragraph.getRectsForRange(linkRanges[index],
        text.RectWidthStyle.TIGHT, text.RectHeightStyle.TIGHT)
        .map((box: text.TextBox): DrawnRichRect => ({ left: box.rect.left + shiftX, right: box.rect.right + shiftX,
          top: box.rect.top, bottom: box.rect.bottom }));
      if (boxes.length === 0 && spec.maxLines !== undefined) { continue; }
      if (!appendDrawnRichHits(hits, boxes, link, density, widthPx, heightPx, generation)) {
        throw new Error('rich link has no valid hit rectangles');
      }
    }
    let paint: DrawnRichParagraph = new DrawnRichNativeParagraph(paragraph, shiftX);
    if (spoilerRanges.length > 0) {
      const concealed = new DrawnRichCompositeParagraph();
      concealed.height = heightPx;
      concealed.lastLine = paint.getLineMetrics(paint.getLineCount() - 1);
      concealed.parts.push({ paragraph: paint, x: 0, y: 0 });
      const mask = richColor($r('app.color.text_secondary'));
      const action: DrawnRichLink = { action: 'spoiler', start: 0, end: 0, label: '', url: '', hidesUrl: false,
        accessibilityFirst: true, accessibilityLabel: str('mb_spoiler') };
      for (const range of spoilerRanges) {
        const boxes = paragraph.getRectsForRange(range, text.RectWidthStyle.TIGHT, text.RectHeightStyle.TIGHT);
        for (const box of boxes) {
          if (box.rect.bottom > heightPx || box.rect.right <= box.rect.left) { continue; }
          const rect: common2D.Rect = { left: box.rect.left + shiftX, right: box.rect.right + shiftX, top: box.rect.top, bottom: box.rect.bottom };
          concealed.backgrounds.push(new DrawnRichBlockBackground(rect, 3 * density, mask, mask, 0));
          appendDrawnRichHits(hits, [rect], action, density, widthPx, heightPx, generation);
        }
      }
      paint = concealed;
    }
    const result = new DrawnRichTextLayout(paint, widthPx / density, heightPx / density, spec.source, hits);
    result.accessibilityText = spoken.join('');
    result.emojiSizeVp = spec.fontSize + 3; result.density = density;
    if (placeholderEmoji.length > 0) {
      const boxes = paragraph.getRectsForPlaceholders();
      if (boxes.length !== placeholderEmoji.length && spec.maxLines === undefined) { throw new Error('missing inline emoji rectangles'); }
      for (let index: number = 0; index < Math.min(boxes.length, placeholderEmoji.length); index++) {
        const mathIndex = placeholderMath[index], emojiIndex = placeholderEmoji[index], iconIndex = placeholderIcon[index];
        if (iconIndex >= 0) {
          const icon = inlineIcons[iconIndex], rect = boxes[index].rect;
          if (rect.bottom <= heightPx && rect.right > rect.left) {
            result.icons.push({ icon: icon.icon, x: (rect.left + shiftX) / density, y: rect.top / density,
              width: (rect.right - rect.left) / density, height: (rect.bottom - rect.top) / density });
          }
          continue;
        }
        if (mathIndex >= 0) {
          const math = mathPlacements[mathIndex], rect = boxes[index].rect;
          if (rect.bottom <= heightPx && rect.right > rect.left) {
            math.rect = { left: rect.left + shiftX, right: rect.right + shiftX, top: rect.top, bottom: rect.bottom };
            math.fallbackY = rect.top + (rect.bottom - rect.top - math.fallback.getHeight()) / 2;
            result.maths.push(math);
          }
          continue;
        }
        if (emojiIndex < 0) { continue; }
        if (emojiHidden[emojiIndex] || boxes[index].rect.bottom > heightPx || boxes[index].rect.right <= boxes[index].rect.left) { continue; }
        result.emojis.push({ id: emojiIds[emojiIndex], rect: { left: boxes[index].rect.left + shiftX, right: boxes[index].rect.right + shiftX,
          top: boxes[index].rect.top, bottom: boxes[index].rect.bottom },
          fallback: emojiFallbacks[emojiIndex], color: emojiColors[emojiIndex],
          fallbackY: boxes[index].rect.top + (boxes[index].rect.bottom - boxes[index].rect.top -
            emojiFallbacks[emojiIndex].getHeight()) / 2 });
      }
    }
    // Fixed four-entry LRU. Theme/config changes drop mixed-color paragraphs;
    // updateColor on a whole paragraph would erase its per-run colors.
    return result;
  }
}
