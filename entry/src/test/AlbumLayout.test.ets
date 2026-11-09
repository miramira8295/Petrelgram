import { describe, it, expect } from '@ohos/hypium';
import {
  packAlbumRows, albumCellAt, albumRowAt, AlbumCell, ALBUM_ROW_SLOTS, ALBUM_ROW_MAX_CELLS,
  EMPTY_ALBUM_CELL
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
    // 行复用时残留槽位会拿旧的行列去索引新相册，索引必须是全函数——这是崩溃
    // 上报里排第一那一类的修复（栈顶 paramsLambda ← aboutToReuseInternal，
    // 两种文案：Cannot load property of null or undefined / Cannot read
    // property idx of undefined）。
    it('cell lookup is total: out of range yields the empty cell', 0, () => {
      const rows: AlbumCell[][] = packAlbumRows([1, 1, 1, 1], 280);
      expect(rows.length).assertEqual(2);
      // 存在的格子照常取到。
      expect(albumCellAt(rows, 0, 0)).assertEqual(rows[0][0]);
      expect(albumCellAt(rows, 1, 1)).assertEqual(rows[1][1]);
      // 整行不存在：以前这里是 rows[2][0]，对 undefined 取下标就是崩溃。
      expect(albumCellAt(rows, 2, 0)).assertEqual(EMPTY_ALBUM_CELL);
      expect(albumCellAt(rows, ALBUM_ROW_SLOTS, 0)).assertEqual(EMPTY_ALBUM_CELL);
      // 行在、列不在：以前 cell 会是 undefined，AlbumCellView.idx() 随即抛。
      expect(albumCellAt(rows, 0, 2)).assertEqual(EMPTY_ALBUM_CELL);
      expect(albumCellAt(rows, 0, ALBUM_ROW_MAX_CELLS)).assertEqual(EMPTY_ALBUM_CELL);
      // 负数与非整数同样不能穿过去。
      expect(albumCellAt(rows, -1, 0)).assertEqual(EMPTY_ALBUM_CELL);
      expect(albumCellAt(rows, 0, -1)).assertEqual(EMPTY_ALBUM_CELL);
      expect(albumCellAt(rows, 0.5, 0)).assertEqual(EMPTY_ALBUM_CELL);
      // 空相册：一行都没有时也不能抛。
      expect(albumCellAt([], 0, 0)).assertEqual(EMPTY_ALBUM_CELL);
    });

    // 空格子必须画不出东西，且让 group.photoXxx[idx] 落到兜底分支。
    it('empty cell renders nothing and indexes nothing', 0, () => {
      expect(EMPTY_ALBUM_CELL.width).assertEqual(0);
      expect(EMPTY_ALBUM_CELL.height).assertEqual(0);
      expect(EMPTY_ALBUM_CELL.idx).assertEqual(-1);
      const paths: string[] = ['a.jpg'];
      expect(paths[EMPTY_ALBUM_CELL.idx] ?? '').assertEqual('');
    });

  });
  // 行级的全函数（2026-09-20）。渲染侧改成「一行一个 AlbumRowView」之后，
  // 「这一行存不存在」的判断从 MessageBubble 里那个**复用时不重算**的 `if`
  // 挪进了组件——组件靠这个函数拿到的空数组决定整行不画。
  //
  // 为什么要紧：残留的行即使每格都是 0×0 的哨兵，Row/Column 的 `space: 2`
  // 照样给它留位，相册高宽抖一下，就是用户报的「相册消息闪动」。
  describe('albumRowAt', () => {
    it('returns_the_row_in_range', 0, () => {
      const rows: AlbumCell[][] = packAlbumRows([1, 1, 1, 1], 300);
      expect(albumRowAt(rows, 0)).assertEqual(rows[0]);
      expect(albumRowAt(rows, rows.length - 1)).assertEqual(rows[rows.length - 1]);
    });

    it('returns_empty_out_of_range', 0, () => {
      const rows: AlbumCell[][] = packAlbumRows([1, 1], 300);
      expect(albumRowAt(rows, rows.length).length).assertEqual(0);
      expect(albumRowAt(rows, ALBUM_ROW_SLOTS).length).assertEqual(0);
      expect(albumRowAt(rows, -1).length).assertEqual(0);
      expect(albumRowAt([], 0).length).assertEqual(0);
    });

    it('never_returns_undefined_for_junk_indices', 0, () => {
      const rows: AlbumCell[][] = packAlbumRows([1, 1, 1], 300);
      expect(albumRowAt(rows, 1.5).length).assertEqual(0);
      expect(albumRowAt(rows, Number.NaN).length).assertEqual(0);
    });
  });

}
