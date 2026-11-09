import { describe, expect, it } from '@ohos/hypium';
import { isInteriorRowRemoval } from '../main/ets/util/rowRemoval';

export default function rowRemovalTest() {
  describe('isInteriorRowRemoval', () => {
    it('删掉中间一行：前后都还有行留着，该带动画（issue #149）', 0, (): void => {
      expect(isInteriorRowRemoval([1, 2, 3, 4], [1, 2, 4])).assertTrue();
    });

    it('删掉中间连续几行也算', 0, (): void => {
      expect(isInteriorRowRemoval([1, 2, 3, 4, 5], [1, 5])).assertTrue();
    });

    it('从头部砍掉一段 = 往上翻页时的窗口裁剪，不带动画', 0, (): void => {
      expect(isInteriorRowRemoval([1, 2, 3, 4], [3, 4])).assertFalse();
    });

    it('从尾部砍掉一段同样不带', 0, (): void => {
      expect(isInteriorRowRemoval([1, 2, 3, 4], [1, 2])).assertFalse();
    });

    it('行数没少 / 变多 / 清空，一律不带', 0, (): void => {
      expect(isInteriorRowRemoval([1, 2, 3], [1, 2, 3])).assertFalse();
      expect(isInteriorRowRemoval([1, 2], [1, 2, 3])).assertFalse();
      expect(isInteriorRowRemoval([1, 2, 3], [])).assertFalse();
    });

    it('中间换了一批（有删有加）不算删除', 0, (): void => {
      expect(isInteriorRowRemoval([1, 2, 3, 9], [1, 7, 9])).assertFalse();
    });
  });
}
