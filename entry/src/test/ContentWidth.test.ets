import { describe, it, expect } from '@ohos/hypium';
import { readableContentWidth } from '../main/ets/util/contentWidth';

export default function contentWidthTest(): void {
  describe('contentWidth', (): void => {

    it('手机宽度不限宽——返回窗口宽本身', 0, (): void => {
      expect(readableContentWidth(360)).assertEqual(360);
      expect(readableContentWidth(374)).assertEqual(374);
      expect(readableContentWidth(599)).assertEqual(599);
    });

    it('刚进入平板区间就开始限宽', 0, (): void => {
      expect(readableContentWidth(600) < 600).assertTrue();
    });

    it('宽屏下内容宽度有上限，不随屏幕无限变宽', 0, (): void => {
      const w1440: number = readableContentWidth(1440);
      const w2560: number = readableContentWidth(2560);
      expect(w1440 === w2560).assertTrue();
    });

    it('限宽后左右留白各不超过窗口宽的 20%（官方 3.2.1.8）', 0, (): void => {
      const w: number = 1440;
      const content: number = readableContentWidth(w);
      const sideMargin: number = (w - content) / 2;
      expect(sideMargin <= w * 0.2).assertTrue();
    });

    it('留白率不超过 70%（官方 3.2.1.9）', 0, (): void => {
      const w: number = 2560;
      const content: number = readableContentWidth(w);
      expect(content / w >= 0.3).assertTrue();
    });

    it('单调不减——窗口变宽内容不会变窄', 0, (): void => {
      let prev: number = 0;
      for (let w = 320; w <= 2560; w++) {
        const c: number = readableContentWidth(w);
        expect(c >= prev).assertTrue();
        prev = c;
      }
    });

    it('任何输入下内容宽度都不超过窗口宽', 0, (): void => {
      for (let w = 320; w <= 2560; w++) {
        expect(readableContentWidth(w) <= w).assertTrue();
      }
    });

  });
}
