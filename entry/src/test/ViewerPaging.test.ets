import { describe, expect, it } from '@ohos/hypium';
import { MediaPageWindow, mediaPageWindow } from '../main/ets/util/viewerPaging';

function ids(n: number): number[] {
  const out: number[] = [];
  for (let i = 1; i <= n; i++) {
    out.push(i * 10);
  }
  return out;
}

export default function viewerPagingTest() {
  describe('viewerPaging', () => {
    it('居中：前后各取 half 张，下标落在窗口正中', 0, () => {
      const w: MediaPageWindow = mediaPageWindow(ids(21), 110, 2);
      expect(w.ids.join(',')).assertEqual('90,100,110,120,130');
      expect(w.index).assertEqual(2);
    });

    // 头尾是最容易错的两处：窗口被裁短，下标必须跟着裁。
    it('目标在开头：窗口从 0 起，下标就是它自己的位置', 0, () => {
      const w: MediaPageWindow = mediaPageWindow(ids(10), 10, 3);
      expect(w.ids.join(',')).assertEqual('10,20,30,40');
      expect(w.index).assertEqual(0);
    });

    it('目标在结尾：窗口到末尾为止，下标是窗口内的最后一个', 0, () => {
      const w: MediaPageWindow = mediaPageWindow(ids(10), 100, 3);
      expect(w.ids.join(',')).assertEqual('70,80,90,100');
      expect(w.index).assertEqual(3);
    });

    it('列表比窗口还短：整份取回，下标不变', 0, () => {
      const w: MediaPageWindow = mediaPageWindow(ids(3), 20, 10);
      expect(w.ids.join(',')).assertEqual('10,20,30');
      expect(w.index).assertEqual(1);
    });

    // 消息刚被撤回，或者点开的根本不是媒体：退化成只有它自己，查看器仍能显示。
    it('目标不在列表里：退化成单元素而不是空列表', 0, () => {
      const w: MediaPageWindow = mediaPageWindow(ids(5), 999, 3);
      expect(w.ids.join(',')).assertEqual('999');
      expect(w.index).assertEqual(0);
    });

    it('目标为 0 且列表为空：空窗口，下标 -1', 0, () => {
      const w: MediaPageWindow = mediaPageWindow([], 0, 3);
      expect(w.ids.length).assertEqual(0);
      expect(w.index).assertEqual(-1);
    });

    it('half 为 0：只有当前这一张', 0, () => {
      const w: MediaPageWindow = mediaPageWindow(ids(5), 30, 0);
      expect(w.ids.join(',')).assertEqual('30');
      expect(w.index).assertEqual(0);
    });

    it('不修改传入的数组', 0, () => {
      const src: number[] = ids(5);
      mediaPageWindow(src, 30, 1);
      expect(src.join(',')).assertEqual('10,20,30,40,50');
    });
  });
}
