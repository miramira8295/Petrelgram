// 实心普通文本及其群聊名字/身份/回复启用自绘；其余特性仍回退。

// Links, translations and material effects keep their original renderer.
// Sender headers and reply hit targets are now handled by the drawn branch.
export function drawnPlainTextEligible(text: string, material: boolean, _senderLabel: boolean,
  _replyId: number, translating: boolean, views: string, hasLinks: boolean, rtlLayout: boolean = false): boolean {
  return !rtlLayout && !material && !translating && views === '' &&
    !hasLinks && text.length > 0 && text.length <= 4096 &&
    // Preserve native bidi layout and tab handling until they have dedicated
    // drawing/hit-test coverage. This includes explicit directional controls.
    !/[\u0590-\u08ff\ufb1d-\ufdff\ufe70-\ufeff\u202a-\u202e\u2066-\u2069\t]/.test(text);
}

export function drawnTailGutter(hasTail: boolean): number {
  // Existing solid Path: 8vp width - 2vp overlap. Tail-less rows reserve 7vp.
  return hasTail ? 6 : 7;
}

// The layout key consists of fixed fields and the original immutable string.
// Resource colors compare by reference/value: an equivalent new Resource may
// miss the cache, but cannot reuse a layout with the wrong color.
export interface DrawnPlainTextSpec {
  content: string;
  time: string;
  edited: string;
  maxWidthVp: number;
  fontSize: number;
  outgoing: boolean;
  tail: boolean;
  topLeft: number;
  topRight: number;
  bottomRight: number;
  bottomLeft: number;
  fill: ResourceColor;
  foreground: ResourceColor;
  secondary: ResourceColor;
  accent: ResourceColor;
  environment: string;
  textEnvironment: string;
}

export function sameDrawnPlainTextSpec(a: DrawnPlainTextSpec, b: DrawnPlainTextSpec): boolean {
  return a.maxWidthVp === b.maxWidthVp && a.fontSize === b.fontSize &&
    a.outgoing === b.outgoing && a.tail === b.tail &&
    a.topLeft === b.topLeft && a.topRight === b.topRight &&
    a.bottomRight === b.bottomRight && a.bottomLeft === b.bottomLeft &&
    a.fill === b.fill && a.foreground === b.foreground &&
    a.secondary === b.secondary && a.accent === b.accent &&
    a.environment === b.environment && a.textEnvironment === b.textEnvironment && a.time === b.time &&
    a.edited === b.edited && a.content === b.content;
}

// Only inputs that affect shaping/line breaks. Paint colors and shell geometry
// do not belong here; Paragraph.updateColor handles recoloring on API 20+.
export function sameDrawnPlainParagraphSpec(a: DrawnPlainTextSpec, b: DrawnPlainTextSpec): boolean {
  return a.maxWidthVp === b.maxWidthVp && a.fontSize === b.fontSize &&
    a.outgoing === b.outgoing && a.textEnvironment === b.textEnvironment &&
    a.time === b.time && a.edited === b.edited && a.content === b.content;
}

// Snapshot only on cache insertion: callers may reuse/mutate their input object
// later. Strings are retained by value without building a second full-text key.
export function snapshotDrawnPlainTextSpec(spec: DrawnPlainTextSpec): DrawnPlainTextSpec {
  return {
    content: spec.content, time: spec.time, edited: spec.edited,
    maxWidthVp: spec.maxWidthVp, fontSize: spec.fontSize,
    outgoing: spec.outgoing, tail: spec.tail,
    topLeft: spec.topLeft, topRight: spec.topRight,
    bottomRight: spec.bottomRight, bottomLeft: spec.bottomLeft,
    fill: spec.fill, foreground: spec.foreground, secondary: spec.secondary,
    accent: spec.accent, environment: spec.environment, textEnvironment: spec.textEnvironment
  };
}

class DrawnPlainCacheEntry<K, T> {
  key: K;
  item: T;
  constructor(key: K, item: T) { this.key = key; this.item = item; }
}

// Four entries per row: at most four fixed-field comparisons, no full-text
// serialization/hashing and no unbounded global native-paragraph pool.
export class DrawnPlainLayoutCache<K, T> {
  private entries: DrawnPlainCacheEntry<K, T>[] = [];
  private epoch: string = '';
  private capacity: number;
  private sameKey: (a: K, b: K) => boolean;
  constructor(sameKey: (a: K, b: K) => boolean, capacity: number = 4) {
    this.sameKey = sameKey;
    this.capacity = Math.max(1, Math.floor(capacity));
  }

  prepare(epoch: string): void {
    if (epoch !== this.epoch) {
      this.epoch = epoch;
      this.entries = [];
    }
  }

  get(key: K): T | undefined {
    for (let i: number = 0; i < this.entries.length; i++) {
      const entry = this.entries[i];
      if (this.sameKey(entry.key, key)) {
        if (i > 0) {
          this.entries.splice(i, 1);
          this.entries.unshift(entry);
        }
        return entry.item;
      }
    }
    return undefined;
  }

  put(key: K, item: T): void {
    for (let i: number = 0; i < this.entries.length; i++) {
      if (this.sameKey(this.entries[i].key, key)) {
        this.entries.splice(i, 1);
        break;
      }
    }
    this.entries.unshift(new DrawnPlainCacheEntry<K, T>(key, item));
    if (this.entries.length > this.capacity) { this.entries.pop(); }
  }
}

// Chrome is independently bounded and keeps unsupported direction/control cases
// on the original renderer. Empty reply labels remain legal (loading/deleted target).
export function drawnChromeTextSupported(content: string): boolean {
  return content.length <= 4096 && !/[\u0590-\u08ff\ufb1d-\ufdff\ufe70-\ufeff\u202a-\u202e\u2066-\u2069\t]/.test(content);
}

// ClickEvent uses vp; drawing and the cached quote rectangle use physical px.
export function drawnReplyHit(xVp: number, yVp: number, leftPx: number, topPx: number,
  widthPx: number, heightPx: number, density: number): boolean {
  if (!(density > 0) || !(widthPx > 0) || !(heightPx > 0)) { return false; }
  const x: number = xVp * density;
  const y: number = yVp * density;
  return x >= leftPx && x < leftPx + widthPx && y >= topPx && y < topPx + heightPx;
}
