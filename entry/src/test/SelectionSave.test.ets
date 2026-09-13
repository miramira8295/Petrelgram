import { describe, it, expect } from '@ohos/hypium';
import { saveableEntries, SaveableEntry, SaveablePlan } from '../main/ets/util/selectionSave';

// 多选保存（issue #199）：从选中 id 里挑出能保存的媒体，照片/视频进相册、文件进下载目录。
interface Stub { id: number; contentType: string; }
function stub(id: number, contentType: string): Stub { return { id, contentType }; }

export default function selectionSaveTest(): void {
  describe('selectionSave', (): void => {
    const all: Stub[] = [
      stub(5, 'text'), stub(4, 'photo'), stub(3, 'video'), stub(2, 'file'),
      stub(1, 'sticker'), stub(6, 'audio'), stub(7, 'voice'), stub(8, 'videoNote')
    ];
    it('只挑媒体，按 id 升序，分成相册与文件两类', 0, (): void => {
      const plan: SaveablePlan = saveableEntries(all, [5, 4, 3, 2, 1, 6, 7, 8]);
      expect(plan.entries.map((e: SaveableEntry): number => e.id).join(',')).assertEqual('2,3,4,6,8');
      expect(plan.entries.filter((e: SaveableEntry): boolean => e.toFiles).map((e: SaveableEntry): number => e.id).join(','))
        .assertEqual('2,6');
      expect(plan.galleryCount).assertEqual(3);
      expect(plan.fileCount).assertEqual(2);
    });
    it('不在选中集合里的不算；选中集合里找不到的 id 忽略', 0, (): void => {
      const plan: SaveablePlan = saveableEntries(all, [4, 999]);
      expect(plan.entries.length).assertEqual(1);
      expect(plan.entries[0].id).assertEqual(4);
    });
    it('全是文本/贴纸 → 空计划', 0, (): void => {
      const plan: SaveablePlan = saveableEntries(all, [5, 1, 7]);
      expect(plan.entries.length).assertEqual(0);
      expect(plan.galleryCount + plan.fileCount).assertEqual(0);
    });
  });
}
