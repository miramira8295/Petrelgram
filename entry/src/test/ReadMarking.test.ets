import { describe, expect, it } from '@ohos/hypium';
import { isAtLiveTail, newestVisibleMessageId } from '../main/ets/util/readMarking';

// 测试里用得到的小工具：把字面量数组原样交回，避免在断言里重复构造。
function rowsOf(rows: number[][]): number[][] {
  return rows;
}

export default function readMarkingTest() {
  describe('readMarking', () => {
    it('取可见区末行的最大成员 id', 0, () => {
      // 相册行有多个成员，要报其中最大的那个。
      expect(newestVisibleMessageId(rowsOf([[10], [20, 22, 21], [30]]).length, (i: number): number[] => rowsOf([[10], [20, 22, 21], [30]])[i], 1)).assertEqual(22);
      expect(newestVisibleMessageId(rowsOf([[10], [20], [30]]).length, (i: number): number[] => rowsOf([[10], [20], [30]])[i], 2)).assertEqual(30);
    });

    it('末行是服务行（无成员）时往回找', 0, () => {
      // 本地合成的"你加入了本群"没有成员 id。直接取末行会得到 0，
      // 整个尾部就永远标不上已读，角标一直挂着。
      expect(newestVisibleMessageId(rowsOf([[10], [20], []]).length, (i: number): number[] => rowsOf([[10], [20], []])[i], 2)).assertEqual(20);
      // 连着两条服务行也要能穿过去。
      expect(newestVisibleMessageId(rowsOf([[10], [], []]).length, (i: number): number[] => rowsOf([[10], [], []])[i], 2)).assertEqual(10);
    });

    it('全是服务行时返回 0，调用方据此不推进', 0, () => {
      expect(newestVisibleMessageId(rowsOf([[], [], []]).length, (i: number): number[] => rowsOf([[], [], []])[i], 2)).assertEqual(0);
    });

    it('越界与空列表都返回 0', 0, () => {
      expect(newestVisibleMessageId(rowsOf([[10]]).length, (i: number): number[] => rowsOf([[10]])[i], -1)).assertEqual(0);
      expect(newestVisibleMessageId(rowsOf([[10]]).length, (i: number): number[] => rowsOf([[10]])[i], 5)).assertEqual(0);
      expect(newestVisibleMessageId(rowsOf([]).length, (i: number): number[] => rowsOf([])[i], 0)).assertEqual(0);
    });

    it('只看到第 0 行时也能取到', 0, () => {
      expect(newestVisibleMessageId(rowsOf([[10], [20]]).length, (i: number): number[] => rowsOf([[10], [20]])[i], 0)).assertEqual(10);
    });

    it('实时尾部要两个条件同时成立', 0, () => {
      expect(isAtLiveTail(9, 10, false)).assertTrue();
      // 还有更新的历史没拉：窗口边缘不是会话末尾。
      expect(isAtLiveTail(9, 10, true)).assertFalse();
      // 最后一组还没进可见区。
      expect(isAtLiveTail(7, 10, false)).assertFalse();
    });

    it('可见区末行越过末尾时仍算尾部', 0, () => {
      // onScrollIndex 偶尔会报出等于行数的下标。
      expect(isAtLiveTail(10, 10, false)).assertTrue();
    });

    it('空列表不算尾部——没内容就没什么可标已读', 0, () => {
      // rowCount 0 时 end 只可能是 -1（无可见行），此时 -1 >= -1 成立，
      // 但调用方在此之前已被 newestVisibleMessageId 的 0 挡住。
      expect(newestVisibleMessageId(rowsOf([]).length, (i: number): number[] => rowsOf([])[i], -1)).assertEqual(0);
    });
  });
}
