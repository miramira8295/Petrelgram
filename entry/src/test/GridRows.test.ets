import { describe, it, expect } from '@ohos/hypium';
import { chunkRows } from '../main/ets/util/gridRows';

// 共享媒体网格按行走 LazyForEach：切行必须不丢、不重、顺序不变。
export default function gridRowsTest() {
  describe('gridRows', () => {
    it('7 个按 3 个一行切成 3/3/1', 0, () => {
      const rows: number[][] = chunkRows([1, 2, 3, 4, 5, 6, 7], 3);
      expect(rows.length).assertEqual(3);
      expect(rows[0].join(',')).assertEqual('1,2,3');
      expect(rows[1].join(',')).assertEqual('4,5,6');
      expect(rows[2].join(',')).assertEqual('7');
    });

    it('正好整除时最后一行是满的', 0, () => {
      const rows: number[][] = chunkRows([1, 2, 3, 4, 5, 6], 3);
      expect(rows.length).assertEqual(2);
      expect(rows[1].join(',')).assertEqual('4,5,6');
    });

    it('空列表切出空行表', 0, () => {
      expect(chunkRows([], 3).length).assertEqual(0);
    });

    it('每行个数不合法时按 1 个一行，不死循环', 0, () => {
      expect(chunkRows([1, 2], 0).length).assertEqual(2);
      expect(chunkRows([1, 2], -3).length).assertEqual(2);
    });
  });
}
