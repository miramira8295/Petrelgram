import { UIUtils } from '@kit.ArkUI';
import { AlbumGroup } from './collapseAlbums';
import { initialMessagePlaceholderHeight } from './initialMessageStage';

const DEFAULT_MESSAGE_ROW_HEIGHT: number = 64;
const MEASURED_ROW_HEIGHT_LIMIT: number = 2048;
const measuredRowHeights: Map<string, number> = new Map<string, number>();

export interface ViewportGeometrySplice {
  start: number;
  deleteCount: number;
  sizes: number[];
}

function geometryFingerprint(value: string): number {
  let hash: number = 2166136261;
  for (let i = 0; i < value.length; i++) {
    hash ^= value.charCodeAt(i);
    hash = Math.imul(hash, 16777619);
  }
  return hash >>> 0;
}

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
    `|${langEpoch}|${showDivider ? 1 : 0}|${contentKey.length}_${geometryFingerprint(contentKey)}`;
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

  private keyOf(group: AlbumGroup): string {
    return viewportGeometryKey(
      this.chatId,
      this.conversationId,
      group.head.rowId,
      group.key,
      this.screenWidth,
      this.langEpoch,
      this.dividerId > 0 && group.memberIds.indexOf(this.dividerId) >= 0
    );
  }

  public rowHeight(group: AlbumGroup): number {
    const showDivider: boolean = this.dividerId > 0 &&
      group.memberIds.indexOf(this.dividerId) >= 0;
    const measured: number = rememberedViewportRowHeight(this.keyOf(group));
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
    if (Math.abs(this.rowSizes[currentIndex] - height) > 0.5) {
      this.rowSizes[currentIndex] = height;
      this.childrenMainSize.update(currentIndex, height);
    }
    if (cacheable) {
      rememberViewportRowHeight(key, height);
    }
  }
}
