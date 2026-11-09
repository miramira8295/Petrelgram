import { describe, expect, it } from '@ohos/hypium';
import {
  FolderOrder, MAIN_LIST_ROW, combinedRows, minRowFor, moveRow, splitRows
} from '../main/ets/util/folderOrder';

export default function folderOrderTest() {
  describe('folderOrder', () => {
    // 用户要求「所有」也能排序：设置页把它和文件夹放进同一张拖动列表。
    it('「所有」按位置插进文件夹列表，越界夹到两端', 0, () => {
      expect(combinedRows([7, 8, 9], 0).join(',')).assertEqual(`${MAIN_LIST_ROW},7,8,9`);
      expect(combinedRows([7, 8, 9], 2).join(',')).assertEqual(`7,8,${MAIN_LIST_ROW},9`);
      expect(combinedRows([7, 8, 9], 99).join(',')).assertEqual(`7,8,9,${MAIN_LIST_ROW}`);
      expect(combinedRows([], 3).join(',')).assertEqual(`${MAIN_LIST_ROW}`);
    });

    it('混合列表拆回 reorderChatFolders 的两个参数', 0, () => {
      const order: FolderOrder = splitRows([7, MAIN_LIST_ROW, 8, 9]);
      expect(order.folderIds.join(',')).assertEqual('7,8,9');
      expect(order.mainPosition).assertEqual(1);
    });

    it('拆和拼互为逆运算', 0, () => {
      const order: FolderOrder = splitRows(combinedRows([3, 1, 2], 2));
      expect(order.folderIds.join(',')).assertEqual('3,1,2');
      expect(order.mainPosition).assertEqual(2);
    });

    it('挪行：把「所有」从第 0 行拖到最后', 0, () => {
      const rows: number[] = moveRow([MAIN_LIST_ROW, 7, 8], 0, 2);
      expect(rows.join(',')).assertEqual(`7,8,${MAIN_LIST_ROW}`);
      expect(splitRows(rows).mainPosition).assertEqual(2);
    });

    it('挪行越界或原地不动时原样返回', 0, () => {
      const rows: number[] = [MAIN_LIST_ROW, 7];
      expect(moveRow(rows, 1, 1) === rows).assertTrue();
      expect(moveRow(rows, 0, 5) === rows).assertTrue();
    });

    it('非会员「所有」钉在第 0 行，别的行最高到第 1 行', 0, () => {
      expect(minRowFor(true)).assertEqual(0);
      expect(minRowFor(false)).assertEqual(1);
    });
  });
}
