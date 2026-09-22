import { describe, it, expect } from '@ohos/hypium';
import {
  TABLE_CELL_PAD_VP, TABLE_COL_MAX_VP, TABLE_COL_MIN_VP,
  tableColumnWidths, tableContentWidth, textWidthEstimate
} from '../main/ets/util/tableLayout';

export default function tableLayoutTest() {
  describe('TableLayout', () => {
    it('汉字按一个字号宽，拉丁按 0.55', 0, () => {
      expect(textWidthEstimate('列', 10)).assertEqual(10);
      expect(textWidthEstimate('列表', 10)).assertEqual(20);
      expect(Math.round(textWidthEstimate('ab', 10))).assertEqual(11);
    });

    // 一个 emoji 是两个码元，两个都算宽就会偏大一倍。
    it('代理对只按一个宽字算', 0, () => {
      expect(textWidthEstimate('😀', 10)).assertEqual(10);
      expect(textWidthEstimate('😀😀', 10)).assertEqual(20);
    });

    it('空串和非法字号返回 0', 0, () => {
      expect(textWidthEstimate('', 15)).assertEqual(0);
      expect(textWidthEstimate('列', 0)).assertEqual(0);
    });

    // 列宽取该列最宽的那一格——不这样各行边界就对不齐，看着就不是一张表。
    it('列宽取该列最宽的一格', 0, () => {
      const rows: string[][] = [['列 1', '一'], ['数据数据数据数据', '二']];
      const w: number[] = tableColumnWidths(rows, 15);
      expect(w.length).assertEqual(2);
      expect(w[0] > w[1]).assertTrue();
    });

    it('窄内容抬到下限，长内容压到上限', 0, () => {
      expect(tableColumnWidths([['一']], 15)[0]).assertEqual(TABLE_COL_MIN_VP);
      const long: string = '很长很长的一句话'.repeat(10);
      expect(tableColumnWidths([[long]], 15)[0]).assertEqual(TABLE_COL_MAX_VP);
    });

    it('算上内边距', 0, () => {
      // 8 个汉字 x 15 = 120，加 20 内边距 = 140，在上下限之间。
      const w: number[] = tableColumnWidths([['一二三四五六七八']], 15);
      expect(w[0]).assertEqual(120 + TABLE_CELL_PAD_VP);
    });

    // 行长不齐是真实数据里会出现的（合并单元格、脏数据）。
    it('行长不齐时按最长的一行定列数，缺的格不参与', 0, () => {
      const rows: string[][] = [['一', '二', '三'], ['甲']];
      const w: number[] = tableColumnWidths(rows, 15);
      expect(w.length).assertEqual(3);
    });

    it('空表没有列', 0, () => {
      expect(tableColumnWidths([], 15).length).assertEqual(0);
      expect(tableContentWidth([])).assertEqual(0);
    });

    // 渲染侧据此决定要不要开横滑：不超宽就不开，免得和气泡的左滑回复抢手势。
    it('内容总宽是各列之和', 0, () => {
      expect(tableContentWidth([10, 20, 30])).assertEqual(60);
    });
  });
}
