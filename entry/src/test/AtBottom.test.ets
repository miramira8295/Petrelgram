import { describe, expect, it } from '@ohos/hypium';
import {
  AT_BOTTOM_KEEP, AT_BOTTOM_NO, AT_BOTTOM_YES,
  AtBottomInput, atBottomVerdict, tailIndexFresh
} from '../main/ets/util/atBottom';

function at(
  scrollerAtEnd: boolean, visibleEndIdx: number, indexGroupsLen: number,
  groupsLen: number, hasMoreNewer: boolean
): AtBottomInput {
  return { viewerOpen: false, imeTailPinned: false, scrollerAtEnd: scrollerAtEnd,
    visibleEndIdx: visibleEndIdx, indexGroupsLen: indexGroupsLen,
    groupsLen: groupsLen, hasMoreNewer: hasMoreNewer };
}

export default function atBottomTest() {
  describe('atBottom', () => {
    it('查看器开着时不动判定', 0, () => {
      const input: AtBottomInput = at(false, 0, 0, 10, false);
      input.viewerOpen = true;
      expect(atBottomVerdict(input)).assertEqual(AT_BOTTOM_KEEP);
    });

    it('输入法改高度的那几帧强制算在底部', 0, () => {
      // 最后一行被短暂裁掉，isAtEnd 会瞬时变假；此时若如实否决，
      // 键盘一弹出视口就从底部掉下来。
      const input: AtBottomInput = at(false, 3, 42, 42, false);
      input.imeTailPinned = true;
      expect(atBottomVerdict(input)).assertEqual(AT_BOTTOM_YES);
    });

    it('滚动条到底 + 行号也说到底 → 在底部', 0, () => {
      expect(atBottomVerdict(at(true, 41, 42, 42, false))).assertEqual(AT_BOTTOM_YES);
    });

    it('滚动条没到底就一定不在底部', 0, () => {
      expect(atBottomVerdict(at(false, 41, 42, 42, false))).assertEqual(AT_BOTTOM_NO);
    });

    it('还有更新的历史没拉时，窗口边缘不算会话末尾', 0, () => {
      // loadAround 取出来的窗口末尾不是真正的最新消息，「↓」得留着。
      expect(atBottomVerdict(at(true, 41, 42, 42, true))).assertEqual(AT_BOTTOM_NO);
    });

    it('行号新鲜且指向中间 → 否决 isAtEnd', 0, () => {
      // 上线过的 bug：列表刚被换掉时 isAtEnd 瞬时返回真，
      // 日志里 atBottom=true 而 endIdx=11 / rows=42，自相矛盾。
      expect(atBottomVerdict(at(true, 11, 42, 42, false))).assertEqual(AT_BOTTOM_NO);
    });

    it('行号陈旧时绝不否决——否则自锁死', 0, () => {
      // 新消息到达：行数先从 42 变 43，行号还停在旧的一批（indexGroupsLen=42）。
      // 若拿它否决，就会判成不在底部 → 不贴底 → 不滚动 → 没有新的
      // onScrollIndex → 永远卡住，现象是停在底部却不跟新消息。
      expect(atBottomVerdict(at(true, 41, 42, 43, false))).assertEqual(AT_BOTTOM_YES);
      // 换会话后的重置态（-1 / -1）同样属于不新鲜，走宽松侧。
      expect(atBottomVerdict(at(true, -1, -1, 30, false))).assertEqual(AT_BOTTOM_YES);
    });

    it('新鲜度的定义：要有过回调，且长度对得上', 0, () => {
      expect(tailIndexFresh(at(true, 41, 42, 42, false))).assertTrue();
      expect(tailIndexFresh(at(true, -1, 42, 42, false))).assertFalse();
      expect(tailIndexFresh(at(true, 41, 42, 43, false))).assertFalse();
    });

    it('陈旧行号在任何行数下都不否决', 0, () => {
      // 穷一遍：只要长度对不上，无论行号落在哪里都不该翻成 NO。
      for (let endIdx = 0; endIdx < 20; endIdx++) {
        expect(atBottomVerdict(at(true, endIdx, 99, 20, false))).assertEqual(AT_BOTTOM_YES);
      }
    });

    it('空列表不会因为 groupsLen-1 变成 -1 而误判', 0, () => {
      // groupsLen=0 时 groupsLen-1 = -1，endIdx>=-1 恒真；
      // 但此时 indexGroupsLen 若也是 0 就算新鲜，仍应放行。
      expect(atBottomVerdict(at(true, 0, 0, 0, false))).assertEqual(AT_BOTTOM_YES);
    });
  });
}
