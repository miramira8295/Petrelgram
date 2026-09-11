import { describe, it, expect } from '@ohos/hypium';
import {
  packAlbumRows, AlbumCell, ALBUM_ROW_SLOTS, ALBUM_ROW_MAX_CELLS
} from '../main/ets/util/packAlbumRows';

function rowWidth(row: AlbumCell[]): number {
  let width = 0;
  for (const cell of row) {
    width += cell.width;
  }
  return width + Math.max(0, row.length - 1) * 2;
}

export default function albumLayoutTest() {
  describe('AlbumLayout', () => {
    it('four_items_form_two_balanced_rows', 0, () => {
      const rows = packAlbumRows([1, 1, 1, 1], 280);
      expect(rows.length).assertEqual(2);
      expect(rows[0].length).assertEqual(2);
      expect(rows[1].length).assertEqual(2);
      expect(rowWidth(rows[0])).assertEqual(280);
      expect(rowWidth(rows[1])).assertEqual(280);
    });
    it('extreme_portrait_is_height_bounded', 0, () => {
      const rows = packAlbumRows([0.1], 280);
      expect(rows[0][0].height <= 188).assertTrue();
      expect(rows[0][0].width).assertEqual(280);
    });
    it('extreme_panorama_is_not_paper_thin', 0, () => {
      const rows = packAlbumRows([10], 280);
      expect(rows[0][0].height >= 132).assertTrue();
    });
    it('nine_items_have_no_orphan_row', 0, () => {
      const rows = packAlbumRows([1, 1, 1, 1, 1, 1, 1, 1, 1], 280);
      expect(rows.length).assertEqual(3);
      expect(rows[2].length).assertEqual(3);
    });

    // MessageBubble.albumGrid 摊的是**固定槽位**（不用 ForEach，否则几何送不进
    // 格子、多选时相册只能销毁重建），槽位数就是下面这两个上限。排版一旦排出
    // 更多行/更宽的行，超出部分会画不出来——所以在这里钉死。
    it('行数与每行格数不超过渲染侧的固定槽位', 0, () => {
      for (let count = 0; count <= 10; count++) {
        const ratios: number[] = [];
        for (let i = 0; i < count; i++) { ratios.push(1); }
        const rows = packAlbumRows(ratios, 280);
        expect(rows.length <= ALBUM_ROW_SLOTS).assertTrue();
        for (const row of rows) {
          expect(row.length <= ALBUM_ROW_MAX_CELLS).assertTrue();
        }
      }
    });

    // 极端比例同样不能把某一行撑到 4 格（权重只影响宽度分配，不影响分桶）。
    it('极端比例不改变分桶形状', 0, () => {
      const rows = packAlbumRows([0.2, 5, 0.2, 5, 0.2, 5], 280);
      expect(rows.length <= ALBUM_ROW_SLOTS).assertTrue();
      for (const row of rows) {
        expect(row.length <= ALBUM_ROW_MAX_CELLS).assertTrue();
      }
    });
  });
}
