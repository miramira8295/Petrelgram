import { describe, expect, it } from '@ohos/hypium';
import {
  PINNED_EMPTY, PINNED_IGNORE, PINNED_JUMP, PINNED_LATEST, PINNED_LOAD, PINNED_RETRY,
  PinnedTap, PinnedTapInput, pinnedTapAction
} from '../main/ets/util/pinnedJump';

function input(
  busy: boolean, loadState: string, ids: number[], cycle: number, topVisibleId: number
): PinnedTapInput {
  return { busy: busy, loadState: loadState, pinnedIds: ids,
    cycle: cycle, topVisibleId: topVisibleId };
}

const NOT_LOADED: (id: number) => number = (_id: number): number => -1;

export default function pinnedJumpTest() {
  describe('pinnedJump', () => {
    it('守卫未过期时什么都不做', 0, () => {
      expect(pinnedTapAction(input(true, 'ready', [30, 20, 10], 0, 0), NOT_LOADED).kind)
        .assertEqual(PINNED_IGNORE);
    });

    it('置顶列表取失败 → 重取', 0, () => {
      expect(pinnedTapAction(input(false, 'error', [30], 0, 0), NOT_LOADED).kind)
        .assertEqual(PINNED_RETRY);
      // 守卫优先于重取。
      expect(pinnedTapAction(input(true, 'error', [30], 0, 0), NOT_LOADED).kind)
        .assertEqual(PINNED_IGNORE);
    });

    it('一条置顶都没有 → 把条清掉', 0, () => {
      expect(pinnedTapAction(input(false, 'ready', [], 0, 0), NOT_LOADED).kind)
        .assertEqual(PINNED_EMPTY);
    });

    it('目标已在列表里 → 直接滚过去', 0, () => {
      const t: PinnedTap = pinnedTapAction(
        input(false, 'ready', [30, 20, 10], 0, 0), (id: number): number => id === 30 ? 7 : -1);
      expect(t.kind).assertEqual(PINNED_JUMP);
      expect(t.targetId).assertEqual(30);
      expect(t.index).assertEqual(7);
    });

    it('目标不在窗口内 → 先去取', 0, () => {
      const t: PinnedTap = pinnedTapAction(input(false, 'ready', [30, 20, 10], 1, 0), NOT_LOADED);
      expect(t.kind).assertEqual(PINNED_LOAD);
      expect(t.targetId).assertEqual(20);
    });

    it('转到最后一条且已经滚过它 → 循环回最新', 0, () => {
      // 列表越靠上越旧。ids 新→旧，最后一条是最旧的 10。
      // 视口最上面是 5（比 10 还旧），说明 10 在视口顶部之下、已经过眼 → 回最新。
      expect(pinnedTapAction(input(false, 'ready', [30, 20, 10], 2, 5), NOT_LOADED).kind)
        .assertEqual(PINNED_LATEST);
      // 视口最上面正好是它本身，同样算过眼。
      expect(pinnedTapAction(input(false, 'ready', [30, 20, 10], 2, 10), NOT_LOADED).kind)
        .assertEqual(PINNED_LATEST);
    });

    it('转到最后一条但它还在视口上方 → 照常跳过去', 0, () => {
      // 视口最上面是 12（比目标 10 新），说明 10 还在上方，没看到过。
      const t: PinnedTap = pinnedTapAction(
        input(false, 'ready', [30, 20, 10], 2, 12), (id: number): number => id === 10 ? 3 : -1);
      expect(t.kind).assertEqual(PINNED_JUMP);
      expect(t.targetId).assertEqual(10);
    });

    it('视口位置未知（0）时不循环，老老实实跳', 0, () => {
      const t: PinnedTap = pinnedTapAction(
        input(false, 'ready', [30, 20, 10], 2, 0), (id: number): number => id === 10 ? 3 : -1);
      expect(t.kind).assertEqual(PINNED_JUMP);
    });

    it('只有一条置顶时，它既是第一条也是最后一条', 0, () => {
      // 已经滚过它 → 回最新。
      expect(pinnedTapAction(input(false, 'ready', [10], 0, 5), NOT_LOADED).kind)
        .assertEqual(PINNED_LATEST);
      // 还在上方 → 跳过去（未加载则先取）。
      expect(pinnedTapAction(input(false, 'ready', [10], 0, 12), NOT_LOADED).kind)
        .assertEqual(PINNED_LOAD);
    });

    it('cycle 越界时夹回最后一条，不会取到 undefined', 0, () => {
      // 取消置顶后 cycle 可能还停在旧位置上。
      const t: PinnedTap = pinnedTapAction(
        input(false, 'ready', [30, 20], 9, 0), (id: number): number => id === 20 ? 1 : -1);
      expect(t.kind).assertEqual(PINNED_JUMP);
      expect(t.targetId).assertEqual(20);
    });
  });
}
