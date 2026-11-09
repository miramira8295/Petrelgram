import { describe, it, expect } from '@ohos/hypium';
import { readableContentWidth, contentSideGutter } from '../main/ets/util/contentWidth';

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

    // 单侧留白宽度。悬浮元素（联系人页的 FAB）靠它跟住内容列的右下角，而不是
    // 继续贴屏幕右下角——2880px 平板上实测两者差了约 500px。
    it('手机上单侧留白为 0——悬浮元素位置逐像素不变', 0, (): void => {
      expect(contentSideGutter(360)).assertEqual(0);
      expect(contentSideGutter(374)).assertEqual(0);
      expect(contentSideGutter(599)).assertEqual(0);
    });

    it('单侧留白恒等于（窗口宽 − 内容宽）的一半，且从不为负', 0, (): void => {
      for (let w = 320; w <= 2560; w++) {
        const g: number = contentSideGutter(w);
        expect(g >= 0).assertTrue();
        expect(g === (w - readableContentWidth(w)) / 2).assertTrue();
      }
    });

    it('宽屏上留白确实把悬浮元素拉回来了', 0, (): void => {
      expect(contentSideGutter(1440)).assertEqual(280);
      expect(contentSideGutter(2560)).assertEqual(840);
    });

  });
}
