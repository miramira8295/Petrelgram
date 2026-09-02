import { UIUtils } from '@kit.ArkUI';
import { AlbumGroup } from './collapseAlbums';
import { initialMessagePlaceholderHeight } from './initialMessageStage';
// ⚠️ rowH.* 是临时判读探针（绘制面·行高离线 批 0，判读完删）：量化「事后
// 纠偏」的规模来决定离线预算值不值得做——rowH.fix 每次都伴随一次
// childrenMainSize.update（List 重排），gt8 档还意味着肉眼可见的锚点跳动。
import { probeHit } from './panelProbe';

const DEFAULT_MESSAGE_ROW_HEIGHT: number = 64;
const MEASURED_ROW_HEIGHT_LIMIT: number = 2048;
const measuredRowHeights: Map<string, number> = new Map<string, number>();

export interface ViewportGeometrySplice {
  start: number;
  deleteCount: number;
  sizes: number[];
}

// contentKey 直接进复合串，不再过 JS 哈希：原来的 FNV 逐字符循环是滚动热路径
// （行模板的 .height()、每次测量回调、每次发布的 reconcile 都要算 key），一份
// 15s 录制里累计 ~307ms 纯 JS 自身耗时（cpuprofile, 20260902T102459）。Map 的
// 字符串比较在原生侧，比 JS 手搓摘要快；原串还天然无碰撞。
export function viewportGeometryKey(
  chatId: number,
  conversationId: number,
  rowId: number,
  contentKey: string,
  screenWidth: number,
  langEpoch: number,
  showDivider: boolean
): string {
  return `${chatId}_${conversationId}|${rowId}|${Math.round(screenWidth)}` +
    `|${langEpoch}|${showDivider ? 1 : 0}|${contentKey}`;
}

export function planViewportGeometrySplice(
  previousKeys: string[], nextKeys: string[], nextSizes: number[]
): ViewportGeometrySplice {
  let prefix: number = 0;
  while (prefix < previousKeys.length && prefix < nextKeys.length &&
    previousKeys[prefix] === nextKeys[prefix]) {
    prefix++;
  }
  let suffix: number = 0;
  while (suffix < previousKeys.length - prefix && suffix < nextKeys.length - prefix &&
    previousKeys[previousKeys.length - 1 - suffix] === nextKeys[nextKeys.length - 1 - suffix]) {
    suffix++;
  }
  return {
    start: prefix,
    deleteCount: previousKeys.length - prefix - suffix,
    sizes: nextSizes.slice(prefix, nextSizes.length - suffix)
  };
}

export function rememberViewportRowHeight(key: string, height: number): void {
  if (key === '' || !Number.isFinite(height) || height <= 0) {
    return;
  }
  measuredRowHeights.delete(key);
  measuredRowHeights.set(key, height);
  while (measuredRowHeights.size > MEASURED_ROW_HEIGHT_LIMIT) {
    const oldest: string | undefined = measuredRowHeights.keys().next().value as
      string | undefined;
    if (oldest === undefined) {
      break;
    }
    measuredRowHeights.delete(oldest);
  }
}

export function rememberedViewportRowHeight(key: string): number {
  const height: number | undefined = measuredRowHeights.get(key);
  if (height === undefined) {
    return 0;
  }
  // Keep recently reused viewport rows at the back of the bounded cache.
  measuredRowHeights.delete(key);
  measuredRowHeights.set(key, height);
  return height;
}

export function resetChatViewportGeometry(): void {
  measuredRowHeights.clear();
}

// Per-List size table backed by a process-level cache of real visible row
// heights. ChildrenMainSize is one-to-one with a List, so only the measured
// values are shared between ChatPage instances; every page owns this adapter.
interface CachedGeometryKey {
  generation: number;
  key: string;
}

export class ChatViewportGeometry {
  public readonly childrenMainSize: ChildrenMainSize =
    UIUtils.makeObserved(new ChildrenMainSize(DEFAULT_MESSAGE_ROW_HEIGHT));
  private rowKeys: string[] = [];
  private rowSizes: number[] = [];
  private chatId: number = 0;
  private conversationId: number = 0;
  private screenWidth: number = 360;
  private langEpoch: number = 0;
  private dividerId: number = 0;
  // keyOf 按 group 对象记忆：AlbumGroup 每次发布都是全新对象、发布后零原地
  // 修改（见 ReusableMessageBubble 的 @Param 注释），对象身份即内容身份。
  // 同一行的 key 在一次发布里要被要走多次（reconcile 里 nextKeys 和 rowHeight
  // 各一次、行模板 .height()、每次测量回调），拼串只做第一次。
  // generation：chatId/宽度/语言纪元/分隔线一变，旧账全部作废。
  private keyCache: WeakMap<AlbumGroup, CachedGeometryKey> = new WeakMap<AlbumGroup, CachedGeometryKey>();
  private keyGeneration: number = 0;

  private keyOf(group: AlbumGroup): string {
    const cached: CachedGeometryKey | undefined = this.keyCache.get(group);
    if (cached !== undefined && cached.generation === this.keyGeneration) {
      return cached.key;
    }
    const key: string = viewportGeometryKey(
      this.chatId,
      this.conversationId,
      group.head.rowId,
      group.key,
      this.screenWidth,
      this.langEpoch,
      this.dividerId > 0 && group.memberIds.indexOf(this.dividerId) >= 0
    );
    this.keyCache.set(group, { generation: this.keyGeneration, key: key });
    return key;
  }

  public rowHeight(group: AlbumGroup): number {
    const showDivider: boolean = this.dividerId > 0 &&
      group.memberIds.indexOf(this.dividerId) >= 0;
    const measured: number = rememberedViewportRowHeight(this.keyOf(group));
    // est/memo 记发布时的记忆命中面：est 高 = 大量行以粗估进表，等着被纠偏。
    probeHit(measured > 0 ? 'rowH.memo' : 'rowH.est');
    return measured > 0
      ? measured : initialMessagePlaceholderHeight(group, this.screenWidth, showDivider);
  }

  public reconcile(
    chatId: number,
    conversationId: number,
    groups: AlbumGroup[],
    screenWidth: number,
    langEpoch: number,
    dividerId: number
  ): void {
    // key 的上下文分量变了才作废记忆（滚动中的常态是全都没变）。
    if (chatId !== this.chatId || conversationId !== this.conversationId ||
      Math.round(screenWidth) !== Math.round(this.screenWidth) ||
      langEpoch !== this.langEpoch || dividerId !== this.dividerId) {
      this.keyGeneration++;
    }
    this.chatId = chatId;
    this.conversationId = conversationId;
    this.screenWidth = screenWidth;
    this.langEpoch = langEpoch;
    this.dividerId = dividerId;
    const nextKeys: string[] = [];
    const nextSizes: number[] = [];
    for (const group of groups) {
      nextKeys.push(this.keyOf(group));
      nextSizes.push(this.rowHeight(group));
    }

    const plan: ViewportGeometrySplice = planViewportGeometrySplice(
      this.rowKeys, nextKeys, nextSizes);
    let appliedSizes: number[] = this.rowSizes.slice(0, plan.start)
      .concat(plan.sizes)
      .concat(this.rowSizes.slice(plan.start + plan.deleteCount));
    if (plan.deleteCount > 0 || plan.sizes.length > 0) {
      this.childrenMainSize.splice(plan.start, plan.deleteCount, plan.sizes);
    }
    for (let i = 0; i < nextSizes.length; i++) {
      if (i >= appliedSizes.length || Math.abs(appliedSizes[i] - nextSizes[i]) > 0.5) {
        this.childrenMainSize.update(i, nextSizes[i]);
      }
    }
    appliedSizes = nextSizes;
    this.rowKeys = nextKeys;
    this.rowSizes = appliedSizes;
  }

  public record(
    index: number,
    group: AlbumGroup,
    height: number,
    cacheable: boolean
  ): void {
    if (!Number.isFinite(height) || height <= 0) {
      return;
    }
    const key: string = this.keyOf(group);
    let currentIndex: number = index;
    if (currentIndex < 0 || currentIndex >= this.rowKeys.length ||
      this.rowKeys[currentIndex] !== key) {
      currentIndex = this.rowKeys.indexOf(key);
    }
    if (currentIndex < 0) {
      return;
    }
    const drift: number = Math.abs(this.rowSizes[currentIndex] - height);
    if (drift > 0.5) {
      // 纠偏 = 一次 List 重排；>8vp 档按视口锚点稳定性算肉眼可见级。
      probeHit(drift > 8 ? 'rowH.fix.gt8' : 'rowH.fix.le8');
      this.rowSizes[currentIndex] = height;
      this.childrenMainSize.update(currentIndex, height);
    } else {
      probeHit('rowH.ok');
    }
    if (cacheable) {
      rememberViewportRowHeight(key, height);
    }
  }
}
