import { describe, expect, it } from '@ohos/hypium';
import {
  ANCHOR_BOTTOM, ANCHOR_UNREAD, InitialAnchor,
  anchorLatchesBottom, initialAnchorOf
} from '../main/ets/util/initialAnchor';

// 行号 → 该行首条消息 id 的假映射：第 i 行的头条 id 是 1000+i。
const headAt: (i: number) => number = (i: number): number => 1000 + i;

export default function initialAnchorTest() {
  describe('initialAnchor', () => {
    it('全读完了就落到底部', 0, () => {
      const a: InitialAnchor = initialAnchorOf(0, -1, headAt);
      expect(a.kind).assertEqual(ANCHOR_BOTTOM);
      expect(a.dividerId).assertEqual(0);
    });

    it('第一条未读在窗口里 → 停在它那一行', 0, () => {
      const a: InitialAnchor = initialAnchorOf(5000, 7, headAt);
      expect(a.kind).assertEqual(ANCHOR_UNREAD);
      expect(a.index).assertEqual(7);
      // 分界线画在行首那条上：相册是一整行，画在成员身上会落到行中间。
      expect(a.dividerId).assertEqual(1007);
    });

    it('第一条未读不在已加载窗口里 → 落到底部且不画分界线', 0, () => {
      // 未读很多时首屏只装得下最新的十几条，第一条未读远在窗口之外。
      // 这条决定了"两百条未读"时用户看到的是最新消息而不是分界线。
      const a: InitialAnchor = initialAnchorOf(5000, -1, headAt);
      expect(a.kind).assertEqual(ANCHOR_BOTTOM);
      expect(a.index).assertEqual(-1);
      expect(a.dividerId).assertEqual(0);
    });

    it('有 id 但行号为负、有行号但 id 为 0，都落到底部', 0, () => {
      expect(initialAnchorOf(5000, -1, headAt).kind).assertEqual(ANCHOR_BOTTOM);
      expect(initialAnchorOf(0, 3, headAt).kind).assertEqual(ANCHOR_BOTTOM);
      // 负的 id 同样不算数。
      expect(initialAnchorOf(-1, 3, headAt).kind).assertEqual(ANCHOR_BOTTOM);
    });

    it('第 0 行也是合法落点', 0, () => {
      const a: InitialAnchor = initialAnchorOf(5000, 0, headAt);
      expect(a.kind).assertEqual(ANCHOR_UNREAD);
      expect(a.index).assertEqual(0);
      expect(a.dividerId).assertEqual(1000);
    });

    it('只有停在未读分界时才闩住贴底', 0, () => {
      expect(anchorLatchesBottom(initialAnchorOf(5000, 7, headAt))).assertTrue();
      expect(anchorLatchesBottom(initialAnchorOf(0, -1, headAt))).assertFalse();
    });
  });
}
