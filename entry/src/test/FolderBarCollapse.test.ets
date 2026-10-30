import { describe, expect, it } from '@ohos/hypium';
import {
  FOLDER_BAR_COLLAPSE_VP, FOLDER_BAR_DRAG_REVEAL_VP, FolderBarCollapseState,
  expandedFolderBar, folderBarForceExpand, folderDragReveals, nextFolderBarCollapse
} from '../main/ets/util/folderBarCollapse';

function run(deltas: number[], start: FolderBarCollapseState = new FolderBarCollapseState(),
  forceExpand: boolean = false): FolderBarCollapseState {
  let s: FolderBarCollapseState = start;
  for (const d of deltas) {
    s = nextFolderBarCollapse(s, d, forceExpand);
  }
  return s;
}

// 首页文件夹条的收起 / 展开（2026-10-30 用户定：方向 + 到顶双保险）。
export default function folderBarCollapseTest() {
  describe('FolderBarCollapse', () => {
    it('往列表尾部累计滑过阈值才收起', 0, () => {
      expect(run([5, 5, 5]).collapsed).assertFalse();
      expect(run([10, 10, 10]).collapsed).assertTrue();
      expect(run([FOLDER_BAR_COLLAPSE_VP]).collapsed).assertTrue();
    });

    it('收起后往回累计滑过阈值才展开', 0, () => {
      const collapsed: FolderBarCollapseState = run([FOLDER_BAR_COLLAPSE_VP]);
      expect(collapsed.collapsed).assertTrue();
      expect(run([-10], collapsed).collapsed).assertTrue();
      expect(run([-10, -10, -10], collapsed).collapsed).assertFalse();
    });

    // 惯性末尾的来回小抖动不能让横条一闪一闪：方向一反就从零累计。
    it('方向来回抖动不切换', 0, () => {
      expect(run([15, -3, 15, -3, 15]).collapsed).assertFalse();
      const collapsed: FolderBarCollapseState = run([FOLDER_BAR_COLLAPSE_VP]);
      expect(run([-15, 3, -15, 3, -15], collapsed).collapsed).assertTrue();
    });

    // 「到顶」「正在横拖文件夹条」「一个文件夹都没有」三种情况都走这一条：
    // 只要 forceExpand 为真，一律展开，并且累计量清零（否则回到顶之后
    // 一个很小的同向滚动就能立刻把它收回去）。
    it('强制展开优先于一切，且清空累计量', 0, () => {
      const collapsed: FolderBarCollapseState = run([FOLDER_BAR_COLLAPSE_VP]);
      const forced: FolderBarCollapseState = nextFolderBarCollapse(collapsed, 100, true);
      expect(forced.collapsed).assertFalse();
      expect(forced.accumulated).assertEqual(0);
      // 展开之后紧接着一帧同向滚动不能立刻又收起。
      expect(nextFolderBarCollapse(forced, 5, false).collapsed).assertFalse();
    });

    it('零或非法增量不改变状态，也不改入参', 0, () => {
      const collapsed: FolderBarCollapseState = run([FOLDER_BAR_COLLAPSE_VP]);
      expect(nextFolderBarCollapse(collapsed, 0, false).collapsed).assertTrue();
      expect(nextFolderBarCollapse(collapsed, Number.NaN, false).collapsed).assertTrue();
      expect(nextFolderBarCollapse(collapsed, Number.POSITIVE_INFINITY, false).collapsed).assertTrue();
      const before: number = collapsed.accumulated;
      nextFolderBarCollapse(collapsed, -100, false);
      expect(collapsed.collapsed).assertTrue();
      expect(collapsed.accumulated).assertEqual(before);
    });

    it('横拖展开看拖动距离，不看方向', 0, () => {
      expect(folderDragReveals(0)).assertFalse();
      expect(folderDragReveals(FOLDER_BAR_DRAG_REVEAL_VP - 1)).assertFalse();
      expect(folderDragReveals(FOLDER_BAR_DRAG_REVEAL_VP)).assertTrue();
      expect(folderDragReveals(-FOLDER_BAR_DRAG_REVEAL_VP)).assertTrue();
      expect(folderDragReveals(Number.NaN)).assertFalse();
    });

    // 点收缩态的胶囊 = 用户明确要求展开，不看累计量。
    it('显式展开返回已展开的新对象', 0, () => {
      const collapsed: FolderBarCollapseState = run([FOLDER_BAR_COLLAPSE_VP]);
      const expanded: FolderBarCollapseState = expandedFolderBar();
      expect(expanded.collapsed).assertFalse();
      expect(expanded.accumulated).assertEqual(0);
      expect(collapsed.collapsed).assertTrue();
    });

    // 设置里的「列表滑动隐藏文件夹」开关（默认开）。关掉 = 每帧都强制展开，
    // 于是横条常驻；开着一律走原来那套判定。
    it('开关关掉时任何滚动都不收起', 0, () => {
      expect(folderBarForceExpand(false, false, true, false)).assertTrue();
      expect(folderBarForceExpand(true, false, true, false)).assertTrue();
      // 真跑一遍状态机：拿同一串滚动量，开着会收起，关着纹丝不动。
      const on: FolderBarCollapseState = nextFolderBarCollapse(expandedFolderBar(),
        FOLDER_BAR_COLLAPSE_VP, folderBarForceExpand(false, false, true, true));
      const off: FolderBarCollapseState = nextFolderBarCollapse(expandedFolderBar(),
        FOLDER_BAR_COLLAPSE_VP, folderBarForceExpand(false, false, true, false));
      expect(on.collapsed).assertTrue();
      expect(off.collapsed).assertFalse();
      expect(off.accumulated).assertEqual(0);
    });

    // 开着的三种强制展开来源与开关无关，一个都不能因为加了开关而失灵。
    it('开关开着时到顶/横拖/无文件夹仍然强制展开', 0, () => {
      expect(folderBarForceExpand(true, false, true, true)).assertTrue();
      expect(folderBarForceExpand(false, true, true, true)).assertTrue();
      expect(folderBarForceExpand(false, false, false, true)).assertTrue();
      expect(folderBarForceExpand(false, false, true, true)).assertFalse();
    });
  });
}
