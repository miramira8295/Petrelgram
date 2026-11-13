import { TdObject } from '../tdkit/TdTypes';
import { parseFormattedText, RichRun, RichSegment } from './richText';
import { linkTextHidesUrl } from './messageLinkAction';
import { DrawnPlainLayoutCache } from './drawnPlainTextPolicy';
import { DrawnSourcePool } from './drawnSourcePool';


export interface DrawnRichLink {
  start: number;
  end: number;
  label: string;
  url: string;
  hidesUrl: boolean;
  // Several styled runs can belong to one continuous spoken link. Physical
  // clicks keep each run's existing confirmation semantics.
  accessibilityLabel: string;
  accessibilityFirst: boolean;
}

export interface DrawnRichSource {
  content: string;
  runs: RichRun[];
  links: DrawnRichLink[];
  targets: Set<string>;
}

export type DrawnRichParser = (content: string, entities: TdObject[]) => RichSegment[];

interface DrawnRichSourceKey {
  content: string;
  entities: TdObject[];
}

interface DrawnRichSourceDecision { source: DrawnRichSource | null; reason: string; }
const sharedDrawnSources: DrawnSourcePool<DrawnRichSourceDecision> = new DrawnSourcePool();

function drawnSourceCost(content: string, source: DrawnRichSource | null): number {
  let cost = content.length * 2 + 128;
  if (source === null) { return cost; }
  for (const run of source.runs) {
    cost += 128 + 2 * (run.text.length + run.url.length + run.customEmojiId.length);
  }
  for (const link of source.links) {
    cost += 128 + 2 * (link.label.length + link.url.length + link.accessibilityLabel.length);
  }
  return cost;
}

// Four source snapshots per text owner, including negative results. The existing
// parser already uses a WeakMap, sorted entity events and active-entity heaps.
// Width, theme, status and drawing never cause another source parse here.
export class DrawnRichSourceCache {
  private content: string = '';
  private entities: TdObject[] | null = null;
  private result: DrawnRichSource | null = null;
  private parser: DrawnRichParser;
  private shared: boolean;
  // Reason travels with positive/negative cache entries; never reparse for diagnostics.
  reason: string = '';
  private reject = (reason: string): DrawnRichSource | null => { this.reason = reason; return null; };
  private sources: DrawnPlainLayoutCache<DrawnRichSourceKey, DrawnRichSourceDecision> =
    new DrawnPlainLayoutCache<DrawnRichSourceKey, DrawnRichSourceDecision>(
      (a: DrawnRichSourceKey, b: DrawnRichSourceKey): boolean => a.content === b.content && a.entities === b.entities);

  constructor(parser: DrawnRichParser = parseFormattedText) {
    this.parser = parser; this.shared = parser === parseFormattedText;
  }

  prepare(content: string, entities: TdObject[]): DrawnRichSource | null {
    if (this.entities === entities && this.content === content) { return this.result; }
    this.content = content; this.entities = entities; this.result = null; this.reason = '';
    const key: DrawnRichSourceKey = { content, entities };
    const hit = this.sources.get(key);
    if (hit !== undefined) { this.result = hit.source; this.reason = hit.reason; return this.result; }
    const shared = this.shared ? sharedDrawnSources.get(content, entities) : undefined;
    if (shared !== undefined) {
      this.result = shared.source; this.reason = shared.reason;
      this.sources.put(key, shared);
      return this.result;
    }
    try {
      this.result = this.prepareSource(content, entities);
      if (this.shared) {
        sharedDrawnSources.put(content, entities, { source: this.result, reason: this.reason },
          drawnSourceCost(content, this.result));
      }
      return this.result;
    } catch (error) {
      this.reason = 'parser-exception'; throw error as Error;
    } finally {
      this.sources.put(key, { source: this.result, reason: this.reason });
    }
  }

  private prepareSource(content: string, entities: TdObject[]): DrawnRichSource | null {
    if (content.length === 0) { return this.reject('empty'); }
    if (content.length > 16384) { return this.reject('text-limit'); }
    if (entities.length > 1024) { return this.reject('entity-limit'); }
    const control = /[\u0590-\u08ff\ufb1d-\ufdff\ufe70-\ufeff\u202a-\u202e\u2066-\u2069\t]/.exec(content);
    if (control !== null) { return this.reject(`direction-or-control:U+${control[0].charCodeAt(0).toString(16)}`); }
    const segments = this.parser(content, entities);
    if (segments.length !== 1) { return this.reject(`segments:${segments.length}`); }
    if (segments[0].kind !== 'text') { return this.reject(`segment-kind:${segments[0].kind}`); }
    if (segments[0].offset !== 0) { return this.reject('segment-offset'); }
    const runs = segments[0].runs;
    if (runs.length === 0 || runs.length > 512) { return this.reject('run-limit'); }
    return buildDrawnRichSource(content, runs, this.reject);
  }
}

function discardDrawnRichSource(_reason: string): DrawnRichSource | null { return null; }

function buildDrawnRichSource(content: string, runs: RichRun[],
  reject: (reason: string) => DrawnRichSource | null = discardDrawnRichSource): DrawnRichSource | null {
  const links: DrawnRichLink[] = [];
  const targets = new Set<string>();
  let position: number = 0;
  let spokenStart: number = 0;
  let spokenFirst: DrawnRichLink | null = null;
  let previousLink: DrawnRichLink | null = null;
  // O(text length + runs): no per-character entity search, pairwise run
  // comparisons or growing concatenation. Cached parser output is read-only.
  for (const run of runs) {
    if (run.code) { return reject('inline-code'); }
    if (run.spoiler) { return reject('spoiler'); }
    if (run.text.length === 0) { return reject('empty-run'); }
    if (run.offset !== position || !content.startsWith(run.text, position)) { return reject('run-offset'); }
    const end: number = position + run.text.length;
    if (run.url !== '') {
      const continued: boolean = previousLink !== null && previousLink.end === position &&
        previousLink.url === run.url;
      const link: DrawnRichLink = {
        start: position, end, label: run.text, url: run.url,
        hidesUrl: linkTextHidesUrl(run.text, run.url),
        accessibilityLabel: run.text, accessibilityFirst: !continued
      };
      if (!continued) {
        if (spokenFirst !== null && previousLink !== null) {
          spokenFirst.accessibilityLabel = content.substring(spokenStart, previousLink.end);
        }
        spokenStart = position; spokenFirst = link;
      }
      links.push(link); targets.add(run.url); previousLink = link;
    } else {
      if (spokenFirst !== null && previousLink !== null) {
        spokenFirst.accessibilityLabel = content.substring(spokenStart, previousLink.end);
      }
      spokenFirst = null; previousLink = null;
    }
    position = end;
  }
  if (spokenFirst !== null && previousLink !== null) {
    spokenFirst.accessibilityLabel = content.substring(spokenStart, previousLink.end);
  }
  if (position !== content.length) { return reject('text-coverage'); }
  if (links.length > 256) { return reject('link-limit'); }
  return { content, runs, links, targets };
}

// Parser-owned segments are immutable and weakly held. Source normalization
// happens once per segment, not once per render/width/theme or once per link.
const segmentSources: WeakMap<RichSegment, DrawnRichSource | null> = new WeakMap();

export function drawnRichSegmentSource(segment: RichSegment): DrawnRichSource | null {
  const cached = segmentSources.get(segment);
  if (cached !== undefined) { return cached; }
  let result: DrawnRichSource | null = null;
  if (segment.kind === 'text' && segment.runs.length > 0 && segment.runs.length <= 512) {
    const parts: string[] = [];
    const runs: RichRun[] = [];
    let position: number = 0;
    let supported: boolean = true;
    for (const run of segment.runs) {
      if (run.code || run.spoiler || run.text.length === 0 ||
        position + run.text.length > 16384) { supported = false; break; }
      parts.push(run.text);
      // Block separators may have been trimmed. Local offsets belong to the
      // displayed paragraph, never to the message's original entity ranges.
      runs.push({ offset: position, text: run.text, bold: run.bold, italic: run.italic,
        underline: run.underline, strike: run.strike, code: run.code, spoiler: run.spoiler,
        customEmojiId: run.customEmojiId, link: run.link, url: run.url });
      position += run.text.length;
    }
    if (supported) {
      const content: string = parts.join('');
      if (!/[\u0590-\u08ff\ufb1d-\ufdff\ufe70-\ufeff\u202a-\u202e\u2066-\u2069\t]/.test(content)) {
        result = buildDrawnRichSource(content, runs);
      }
    }
  }
  segmentSources.set(segment, result);
  return result;
}

export interface DrawnRichRect {
  left: number;
  top: number;
  right: number;
  bottom: number;
}

export interface DrawnRichHit {
  key: string;
  link: DrawnRichLink;
  x: number;
  y: number;
  widthVp: number;
  heightVp: number;
  accessible: boolean;
}

// Visits only returned rectangles: across all links this is O(total boxes),
// not links × all glyphs. Empty/invalid boxes trigger native fallback upstream.
export function appendDrawnRichHits(hits: DrawnRichHit[], boxes: DrawnRichRect[], link: DrawnRichLink,
  density: number, maxPx: number, heightPx: number, generation: number): boolean {
  if (!(density > 0) || !Number.isFinite(density)) { return false; }
  const before: number = hits.length;
  for (const box of boxes) {
    if (!Number.isFinite(box.left) || !Number.isFinite(box.top) ||
      !Number.isFinite(box.right) || !Number.isFinite(box.bottom)) {
      return false;
    }
    const left: number = Math.max(0, box.left);
    const right: number = Math.min(maxPx, box.right);
    const top: number = Math.max(0, box.top);
    const bottom: number = Math.min(heightPx, box.bottom);
    if (right <= left || bottom <= top) { continue; }
    hits.push({ key: `${generation}:${link.start}:${hits.length - before}`, link,
      x: left / density, y: top / density, widthVp: (right - left) / density,
      heightVp: (bottom - top) / density, accessible: link.accessibilityFirst && hits.length === before });
    if (hits.length > 1024) { return false; }
  }
  return hits.length > before;
}
