import { describe, expect, it } from '@ohos/hypium';
import { resolveSplitNavWidth } from '../main/ets/util/splitNavWidth';

export default function splitNavWidthTest() {
  describe('splitNavWidth', () => {
    it('没记过时给 min——正是 HDS 的静息宽度，行为不变', 0, (): void => {
      expect(resolveSplitNavWidth(0, 480, 560)).assertEqual(480);
      expect(resolveSplitNavWidth(-1, 480, 560)).assertEqual(480);
      expect(resolveSplitNavWidth(Number.NaN, 480, 560)).assertEqual(480);
    });
    it('记过就复原（issue #106）', 0, (): void => {
      expect(resolveSplitNavWidth(530, 480, 560)).assertEqual(530);
    });
    it('越出当前区间时夹回来，不能原样喂给 HDS', 0, (): void => {
      // 转屏/分屏后区间变了：上次 560，现在最大 320——越界值 HDS 按默认处理，等于白记。
      expect(resolveSplitNavWidth(560, 240, 320)).assertEqual(320);
      expect(resolveSplitNavWidth(200, 240, 320)).assertEqual(240);
    });
  });
}
