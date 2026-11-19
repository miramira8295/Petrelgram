import { offsetDocumentWidget } from './DrawnDocumentCardLayout';
import { common2D } from '@kit.ArkGraphics2D';
import { drawnExpandedBlockSet } from '../../util/drawnExpandedBlocks';
import { DrawnRichBlock, DrawnRichSource, DrawnRichHit, DrawnRichLink, DrawnRichButton, drawnRichBlockPadding } from '../../util/drawnRichTextPolicy';
import { DrawnRichCompositeParagraph, DrawnRichBlockBackground } from './DrawnRichCompositeParagraph';
import { DrawnRichTextLayout, DrawnRichTextSpec } from './DrawnRichTextLayout';
import { drawnColor } from './DrawnTextLine';
import { appendDrawnIcons } from '../../util/drawnInlineIcon';
import { str } from '../../util/strings';

export interface DrawnDeepLayoutHost {
  prepare: (spec: DrawnRichTextSpec) => DrawnRichTextLayout;
  label: (content: string, width: number, spec: DrawnRichTextSpec) => DrawnRichTextLayout;
  create: (paragraph: DrawnRichCompositeParagraph, width: number, height: number, hits: DrawnRichHit[]) => DrawnRichTextLayout;
}
interface DrawnDeepClose {
  parent: DrawnDeepFrame;
  block: DrawnRichBlock;
  index: number;
  padding: number;
  top: number;
  bodyTop: number;
  background: number;
}
class DrawnDeepFrame {
  source: DrawnRichSource;
  spec: DrawnRichTextSpec;
  x: number;
  width: number;
  index: number = 0;
  last: number;
  spokenStart: number;
  allowHits: boolean;
  close?: DrawnDeepClose;
  constructor(spec: DrawnRichTextSpec, x: number, spokenStart: number, allowHits: boolean, close?: DrawnDeepClose) {
    this.source = spec.source; this.spec = spec; this.x = x; this.width = Math.max(0, spec.minWidthVp);
    this.spokenStart = spokenStart; this.allowHits = allowHits; this.close = close;
    const blocks = spec.source.blocks ?? []; this.last = blocks.length - 1;
    while (this.last >= 0 && blocks[this.last].kind === 'anchor') { this.last--; }
  }
}
const deepLeafSources: WeakMap<DrawnRichBlock, DrawnRichSource> = new WeakMap<DrawnRichBlock, DrawnRichSource>();
function deepLeafSource(block: DrawnRichBlock): DrawnRichSource {
  const cached = deepLeafSources.get(block);
  if (cached !== undefined) { return cached; }
  const source: DrawnRichSource = { content: '', runs: [], links: block.source.links, targets: block.source.targets,
    blocks: [block], nestingDepth: 1 + (block.source.nestingDepth ?? 0),
    hasMath: block.source.hasMath === true || block.title?.hasMath === true || block.buttons?.some((button: DrawnRichButton): boolean => button.source.hasMath === true) === true,
    hasEmbed: block.source.hasEmbed === true || block.widget?.kind === 'html-embed' };
  deepLeafSources.set(block, source); return source;
}
function deepFramed(block: DrawnRichBlock): boolean { return block.kind === 'pre' || block.kind === 'quote'; }
function deepOwnSpacing(block: DrawnRichBlock, open: boolean): boolean {
  return block.kind === 'anchor' || block.kind === 'preview-image' || block.article !== undefined || block.widget !== undefined ||
    (block.gallery?.length ?? 0) > 0 || block.kind === 'media' || block.kind === 'buttons' || block.kind === 'table' ||
    block.kind === 'math' || block.kind === 'divider' || (block.kind === 'details' && block.title !== undefined && !open);
}

function deepSpeaks(block: DrawnRichBlock): boolean {
  if (block.kind === 'preview-image' || block.widget !== undefined || (block.gallery?.length ?? 0) > 0 ||
    block.kind === 'media' || block.kind === 'divider') { return false; }
  if (block.kind === 'table' || block.kind === 'math') { return (block.title?.content ?? '') !== ''; }
  if (block.kind === 'buttons') { return (block.buttons?.length ?? 0) > 0; }
  return true;
}

// Only deep structural wrappers use this traversal. Shallow subtrees (<=8)
// keep the existing engines/geometry, so an arbitrary nesting depth cannot
// multiply every descendant's hit/icon/media list or the JS paint call stack.
// Each emitted leaf/metadata record is appended once, O(nodes + placements),
// plus native shaping and the final O(H log H) hit-index construction.
class DrawnDeepBlockCompiler {
  private host: DrawnDeepLayoutHost;
  private rootSpec: DrawnRichTextSpec;
  private density: number;
  private backgroundColor: common2D.Color;
  private accentColor: common2D.Color;
  private paragraph: DrawnRichCompositeParagraph = new DrawnRichCompositeParagraph();
  private hits: DrawnRichHit[] = [];
  private anchors: Map<string, number> = new Map<string, number>();
  private spoken: string[] = [];
  private plans: DrawnRichTextLayout[] = [];
  private xs: number[] = [];
  private ys: number[] = [];
  private backgrounds: (DrawnRichBlockBackground | null)[] = [];
  private expanded: ReadonlySet<number>;
  private y: number = 0;
  private order: number = 0;
  constructor(spec: DrawnRichTextSpec, density: number, host: DrawnDeepLayoutHost) {
    this.rootSpec = spec; this.density = density; this.host = host;
    this.expanded = drawnExpandedBlockSet(spec.expandedBlocks);
    this.backgroundColor = drawnColor($r('app.color.code_surface')); this.accentColor = drawnColor(spec.accent);
  }
  private append(plan: DrawnRichTextLayout, x: number, y: number, allowHits: boolean, speak: boolean = true): void {
    const d = this.density;
    this.paragraph.parts.push({ paragraph: plan.paragraph, x: x * d, y: y * d });
    this.plans.push(plan); this.xs.push(x); this.ys.push(y);
    if (allowHits) {
      for (const hit of plan.hits) { this.hits.push({ key: `deep:leaf:${this.order++}:${hit.key}`, link: hit.link,
        x: hit.x + x, y: hit.y + y, widthVp: hit.widthVp, heightVp: hit.heightVp, accessible: hit.accessible }); }
    }
    for (const anchor of plan.anchors) { this.anchors.set(anchor[0], anchor[1] + y); }
    if (speak) { this.spoken.push(plan.accessibilityText); }
    const line = plan.paragraph.getLineMetrics(plan.paragraph.getLineCount() - 1);
    this.paragraph.lastLine = line === undefined ? undefined : { left: line.left + x * d,
      width: line.width, baseline: line.baseline + y * d, ascent: line.ascent };
  }
  private label(content: string, width: number, frame: DrawnDeepFrame, x: number, y: number): DrawnRichTextLayout {
    const label = this.host.label(content, width, frame.spec);
    this.paragraph.parts.push({ paragraph: label.paragraph, x: x * this.density, y: y * this.density });
    return label;
  }
  private gap(parent: DrawnDeepFrame, block: DrawnRichBlock, index: number): void {
    if (index < parent.last && block.kind !== 'flow') { this.y += block.preview ? 3 : 6; }
  }
  private finish(frame: DrawnDeepFrame): void {
    if (this.spoken.length === frame.spokenStart) { this.spoken.push(''); }
    const close = frame.close;
    if (close === undefined) { return; }
    const parent = close.parent, block = close.block, framed = deepFramed(block), d = this.density;
    const height = this.y - close.bodyTop;
    if (block.kind === 'translation-label' && height < 24) { this.y += 24 - height; }
    if (block.action !== undefined && parent.allowHits) {
      const action: DrawnRichLink = { action: block.action, start: 0, end: 0, label: block.source.content, url: '',
        hidesUrl: false, accessibilityFirst: true, accessibilityLabel: block.source.content };
      this.hits.push({ key: `deep:action:${this.order++}`, link: action, x: frame.x, y: close.bodyTop,
        widthVp: frame.width, heightVp: Math.max(24, height), accessible: true });
    }
    parent.width = Math.max(parent.width, framed ? parent.spec.maxWidthVp : frame.width + close.padding);
    if (block.expandable) {
      this.y += 4;
      const content = str(this.expanded.has(block.offset) ? 'mb_collapse_quote' : 'mb_expand_quote');
      const label = this.label(content, frame.spec.maxWidthVp, parent, frame.x, this.y);
      const action: DrawnRichLink = { action: 'quote', blockOffset: block.offset, start: 0, end: 0,
        label: content, url: '', hidesUrl: false, accessibilityFirst: true, accessibilityLabel: content };
      if (parent.allowHits) { this.hits.push({ key: `deep:quote:${this.order++}`, link: action,
        x: frame.x, y: this.y, widthVp: frame.spec.maxWidthVp, heightVp: Math.max(24, label.heightVp), accessible: true }); }
      this.y += Math.max(24, label.heightVp);
    }
    if (framed) {
      this.y += 7;
      this.backgrounds[close.background] = new DrawnRichBlockBackground({ left: parent.x * d, top: close.top * d,
        right: (parent.x + parent.spec.maxWidthVp) * d, bottom: this.y * d }, 7 * d,
        this.backgroundColor, this.accentColor, block.kind === 'quote' ? 3 * d : 0);
      this.paragraph.lastLine = { left: parent.x * d, width: parent.spec.maxWidthVp * d, baseline: this.y * d, ascent: 0 };
    }
    this.gap(parent, block, close.index);
  }
  build(): DrawnRichTextLayout {
    const root = new DrawnDeepFrame(this.rootSpec, 0, 0, true);
    const pending: DrawnDeepFrame[] = [root];
    while (pending.length > 0) {
      const frame = pending[pending.length - 1], blocks = frame.source.blocks;
      if (frame.index === 0 && (blocks === undefined || (frame.source.nestingDepth ?? 0) <= 8)) {
        const plan = this.host.prepare(frame.spec); this.append(plan, frame.x, this.y, frame.allowHits);
        frame.width = plan.widthVp; this.y += plan.heightVp; pending.pop(); this.finish(frame); continue;
      }
      if (frame.index >= (blocks?.length ?? 0)) { pending.pop(); this.finish(frame); continue; }
      const index = frame.index++, block = blocks![index];
      if (block.kind === 'anchor') { this.anchors.set(block.anchorName ?? '', this.y); continue; }
      const open = (block.initiallyOpen === true) !== this.expanded.has(block.offset);
      if (block.source.blocks === undefined || (block.source.nestingDepth ?? 0) <= 8) {
        const spec: DrawnRichTextSpec = { source: deepLeafSource(block), mathRevision: frame.spec.mathRevision,
          expandedBlocks: frame.spec.expandedBlocks, spoilersRevealed: frame.spec.spoilersRevealed,
          maxWidthVp: frame.spec.maxWidthVp, minWidthVp: 0, fontSize: frame.spec.fontSize,
          reserve: index === frame.last ? frame.spec.reserve : '', foreground: frame.spec.foreground,
          accent: frame.spec.accent, environment: frame.spec.environment };
        const plan = this.host.prepare(spec); this.append(plan, frame.x, this.y, frame.allowHits, deepSpeaks(block));
        this.y += plan.heightVp;
        const resetWidth = block.kind === 'preview-image' || block.article !== undefined || block.widget !== undefined ||
          (block.gallery?.length ?? 0) > 0 || block.kind === 'media' || block.kind === 'buttons' || block.kind === 'divider' ||
          (block.kind === 'details' && block.title !== undefined);
        frame.width = resetWidth ? plan.widthVp : Math.max(frame.width, plan.widthVp);
        if (!deepOwnSpacing(block, open)) { this.gap(frame, block, index); }
        continue;
      }
      const framed = deepFramed(block), padding = drawnRichBlockPadding(block, frame.spec.maxWidthVp);
      const innerWidth = Math.max(1, frame.spec.maxWidthVp - padding * 2);
      if (block.kind === 'list-item') {
        const marker = this.label(block.marker ?? '•', 22, frame, frame.x, this.y); this.spoken.push(block.marker ?? '•');
        if (block.task !== undefined && padding > 0 && frame.allowHits) {
          const label = str(block.task.checked ? 'checklist_mark_not_done' : 'checklist_mark_done');
          const action: DrawnRichLink = { action: 'rich-task-toggle', taskId: block.task.id, taskChecked: block.task.checked,
            start: 0, end: 0, label, url: '', hidesUrl: false, accessibilityFirst: true, accessibilityLabel: label };
          this.hits.push({ key: `deep:task:${block.task.id}`, link: action, x: frame.x, y: this.y,
            widthVp: Math.min(24, padding), heightVp: Math.max(20, marker.heightVp), accessible: true });
        }
      }
      if (block.kind === 'details' && block.title !== undefined) {
        const title = this.host.prepare({ source: block.title, mathRevision: frame.spec.mathRevision,
          maxWidthVp: Math.max(1, frame.spec.maxWidthVp - 24), minWidthVp: 0, fontSize: frame.spec.fontSize,
          reserve: '', foreground: frame.spec.accent, accent: frame.spec.accent, environment: frame.spec.environment });
        this.label(open ? '▾' : '▸', 22, frame, frame.x, this.y);
        // Header links are owned by the disclosure control; inline visual
        // resources still need their original paragraph/bitmap geometry.
        this.append(title, frame.x + 24, this.y, false); this.spoken.pop();
        const label = title.accessibilityText + ' · ' + str(open ? 'mb_collapse_quote' : 'mb_expand_quote');
        const action: DrawnRichLink = { action: 'quote', blockOffset: block.offset, start: 0, end: 0,
          label, url: '', hidesUrl: false, accessibilityFirst: true, accessibilityLabel: label };
        if (frame.allowHits) { this.hits.push({ key: `deep:details:${this.order++}`, link: action,
          x: frame.x, y: this.y, widthVp: frame.spec.maxWidthVp, heightVp: Math.max(28, title.heightVp), accessible: true }); }
        this.spoken.push(label); this.y += Math.max(28, title.heightVp) + 6; frame.width = frame.spec.maxWidthVp;
        this.paragraph.lastLine = { left: frame.x * this.density, width: frame.width * this.density, baseline: this.y * this.density, ascent: 0 };
        if (!open) { continue; }
      }
      const top = this.y;
      let background: number = -1;
      if (framed) { background = this.backgrounds.length; this.backgrounds.push(null); this.y += 7; }
      if (block.kind === 'pre') {
        const label = this.label((block.language || str('mb_code')) + '    ' + str('copy'), innerWidth, frame, frame.x + padding, this.y);
        const action: DrawnRichLink = { action: 'copy', start: 0, end: block.source.content.length,
          label: block.source.content, url: '', hidesUrl: false, accessibilityFirst: true, accessibilityLabel: str('copy') };
        if (frame.allowHits) { this.hits.push({ key: `deep:copy:${this.order++}`, link: action, x: frame.x + padding,
          y: this.y, widthVp: innerWidth, heightVp: Math.max(26, label.heightVp), accessible: true }); }
        this.y += Math.max(26, label.heightVp) + 5;
      }
      const spec: DrawnRichTextSpec = { source: block.source, mathRevision: frame.spec.mathRevision,
        expandedBlocks: frame.spec.expandedBlocks, spoilersRevealed: frame.spec.spoilersRevealed,
        maxWidthVp: innerWidth, minWidthVp: 0, fontSize: block.fontSize ?? (block.kind === 'translation-label' ? 11 : frame.spec.fontSize),
        reserve: index === frame.last && !framed ? frame.spec.reserve : '',
        foreground: block.kind === 'preview-site' || block.kind === 'preview-action' ? frame.spec.accent : frame.spec.foreground,
        accent: frame.spec.accent, environment: frame.spec.environment,
        maxLines: block.lineLimit ?? (block.expandable && !this.expanded.has(block.offset) ? 4 : undefined),
        codeBlock: block.kind === 'flow' ? frame.spec.codeBlock : block.kind === 'pre' };
      pending.push(new DrawnDeepFrame(spec, frame.x + padding, this.spoken.length,
        frame.allowHits && block.kind !== 'translation-label' && block.preview !== true,
        { parent: frame, block, index, padding, top, bodyTop: this.y, background }));
    }
    this.paragraph.height = this.y * this.density;
    for (const background of this.backgrounds) { if (background !== null) { this.paragraph.backgrounds.push(background); } }
    // No intermediate structural ancestor constructs another hit index.
    const result = this.host.create(this.paragraph, root.width, this.y, this.hits);
    result.anchors = this.anchors; result.accessibilityText = this.spoken.join('\n'); result.density = this.density;
    result.emojiSizeVp = this.rootSpec.fontSize + 3;
    for (let i: number = 0; i < this.plans.length; i++) {
      const plan = this.plans[i], x = this.xs[i], y = this.ys[i], dx = x * this.density, dy = y * this.density;
      appendDrawnIcons(result.icons, plan.icons, x, y);
      for (const item of plan.widgets) { result.widgets.push(offsetDocumentWidget(item, x, y)); result.widgetOwners.add(item.widget); }
      for (const item of plan.media) { result.media.push({ key: `deep:${i}:${item.key}`, media: item.media, slides: item.slides, x: item.x + x, y: item.y + y, width: item.width, height: item.height }); }
      for (const item of plan.tables) { result.tables.push({ key: `deep:${i}:${item.key}`, layout: item.layout, x: item.x + x, y: item.y + y, width: item.width, height: item.height }); }
      for (const math of plan.maths) { result.maths.push({ key: math.key, expression: math.expression, renderSize: math.renderSize, color: math.color,
        ready: math.ready, fallback: math.fallback, fallbackY: math.fallbackY + dy,
        rect: { left: math.rect.left + dx, right: math.rect.right + dx, top: math.rect.top + dy, bottom: math.rect.bottom + dy } }); }
      for (const emoji of plan.emojis) { result.emojis.push({ id: emoji.id, fallback: emoji.fallback, color: emoji.color, fallbackY: emoji.fallbackY + dy,
        rect: { left: emoji.rect.left + dx, right: emoji.rect.right + dx, top: emoji.rect.top + dy, bottom: emoji.rect.bottom + dy } }); }
      if (plan.previewImage !== null) { result.previewImage = { x: plan.previewImage.x + x, y: plan.previewImage.y + y, width: plan.previewImage.width, height: plan.previewImage.height }; }
    }
    return result;
  }
}

export function buildDrawnDeepBlocks(spec: DrawnRichTextSpec, density: number, host: DrawnDeepLayoutHost): DrawnRichTextLayout {
  return new DrawnDeepBlockCompiler(spec, density, host).build();
}
