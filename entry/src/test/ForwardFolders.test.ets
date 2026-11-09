import { describe, it, expect } from '@ohos/hypium';
import {
  forwardFolderChips, forwardListKey, ForwardFolderChip, ALL_FOLDER_ID, forwardGridColumns, forwardColumnsTemplate
} from '../main/ets/util/forwardFolders';
import { FolderInfo } from '../main/ets/store/FolderStore';

// 转发面板的文件夹页签（issue #200）：「全部」恒在首位、键的拼法与首页一致。
function folder(id: number, title: string): FolderInfo {
  return { id, title, iconName: '', colorId: -1, isShareable: false, hasMyInviteLinks: false };
}

export default function forwardFoldersTest(): void {
  describe('forwardFolders', (): void => {
    it('全部 → main；文件夹 → folder:<id>（与 ChatStore 的分桶键一致）', 0, (): void => {
      expect(forwardListKey(ALL_FOLDER_ID)).assertEqual('main');
      expect(forwardListKey(7)).assertEqual('folder:7');
    });
    it('页签列表：「全部」在首位，其余按文件夹顺序', 0, (): void => {
      const chips: ForwardFolderChip[] = forwardFolderChips([folder(3, 'B'), folder(9, 'A')]);
      expect(chips.map((c: ForwardFolderChip): number => c.id).join(',')).assertEqual(`${ALL_FOLDER_ID},3,9`);
      expect(chips[0].isAll).assertTrue();
      expect(chips[2].title).assertEqual('A');
    });
    it('没有文件夹时只剩「全部」——调用方据此决定藏起整排', 0, (): void => {
      expect(forwardFolderChips([]).length).assertEqual(1);
    });

    // 头像网格列数按可用宽度自适应：每格 72vp，夹在 4–6 之间。
    it('grid columns: 4 on a 360vp phone, 5 on 440vp, 6 on tablets, never outside 4–6', 0, (): void => {
      expect(forwardGridColumns(360 - 16 - 24)).assertEqual(4);
      expect(forwardGridColumns(440 - 16 - 24)).assertEqual(5);
      expect(forwardGridColumns(600)).assertEqual(6);
      expect(forwardGridColumns(1200)).assertEqual(6);
      expect(forwardGridColumns(0)).assertEqual(4);
      expect(forwardColumnsTemplate(5)).assertEqual('1fr 1fr 1fr 1fr 1fr');
    });
  });
}
