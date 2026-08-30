import { describe, expect, it } from '@ohos/hypium';
import { albumCellKey, albumRowKey } from '../main/ets/util/albumCellKey';

// 一整块相册（每行的格子键）。真机上的 bug 就是两块不同的相册算出了同一串键。
function gridKeys(memberIds: number[], fileIds: number[], video: boolean[]): string[] {
  const cells: string[] = [];
  for (let i = 0; i < memberIds.length; i++) {
    cells.push(albumCellKey(i, memberIds[i], fileIds[i], video[i]));
  }
  return [albumRowKey(0, cells)].concat(cells);
}

export default function albumCellKeyTest() {
  describe('albumCellKey', () => {
    // 这一条就是那个 bug。两条相册消息张数相同（"格式一致的频道"），几何完全
    // 一样，于是原来的 `row_0` / `cell_0` 两层键逐字相同——ForEach 判定"没变化"，
    // 不重跑子构建函数，格子里的缩略图还挂在上一条消息的文件上。
    it('two_albums_of_the_same_shape_must_not_share_keys', 0, () => {
      const a: string[] = gridKeys([101, 102], [7001, 7002], [false, false]);
      const b: string[] = gridKeys([201, 202], [8001, 8002], [false, false]);
      expect(a.join('#') === b.join('#')).assertFalse();
      // 每一格都要能分辨，不能只有整行的键不同。
      expect(a[1] === b[1]).assertFalse();
      expect(a[2] === b[2]).assertFalse();
    });
    // 反向的不变式同样重要：同一块相册重新求值必须得到同一串键，否则每帧都在
    // 重建格子——那会把缩略图重新解码一遍，比配错图还糟。
    it('the_same_album_keeps_its_keys_stable', 0, () => {
      const first: string[] = gridKeys([101, 102], [7001, 7002], [false, true]);
      const again: string[] = gridKeys([101, 102], [7001, 7002], [false, true]);
      expect(first.join('#')).assertEqual(again.join('#'));
    });
    // 缩略图路径**不进 key**（旁路通道的前提），但换了文件必须重建。
    it('a_replaced_file_changes_the_key', 0, () => {
      const before: string = albumCellKey(0, 101, 7001, false);
      const after: string = albumCellKey(0, 101, 9999, false);
      expect(before === after).assertFalse();
    });
    // 视频格和图片格在 albumGrid 里是两棵完全不同的子树。
    it('video_and_photo_cells_do_not_share_a_key', 0, () => {
      expect(albumCellKey(0, 101, 7001, true) === albumCellKey(0, 101, 7001, false))
        .assertFalse();
    });
    // 位置仍然要在键里：同一条消息里两格的 memberId 可能相同（付费媒体、
    // 同一文件重复出现），只靠身份会撞。
    it('position_still_separates_two_identical_cells', 0, () => {
      expect(albumCellKey(0, 101, 7001, false) === albumCellKey(1, 101, 7001, false))
        .assertFalse();
    });
    // 行键必须跟着格子变：外层键不变时 ForEach 连行的构建函数都不会重跑，
    // 内层那个 ForEach 根本没有机会被重新求值。
    it('the_row_key_follows_its_cells', 0, () => {
      const one: string = albumRowKey(0, [albumCellKey(0, 101, 7001, false)]);
      const two: string = albumRowKey(0, [albumCellKey(0, 202, 8002, false)]);
      expect(one === two).assertFalse();
    });
  });
}
