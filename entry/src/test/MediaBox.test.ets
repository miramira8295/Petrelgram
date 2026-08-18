import { describe, expect, it } from '@ohos/hypium';
import {
  MEDIA_MAX_HEIGHT_RATIO,
  mediaBoxFor,
  mediaRatio,
  mediaThumbWidth
} from '../main/ets/util/mediaBox';

// 气泡里的单图应当铺满气泡宽度，不管横竖。
//
// 之前不是这样：高度超过上限时，代码把高压回上限**并按比例把宽度也缩了**，
// 于是竖图只占气泡宽度的 67%，一条竖图消息比同一群里的横图窄一截。正确的
// 做法是宽度钉死、只压高度，多出来的部分交给 ImageFit.Cover 裁掉。
const SCREEN: number = 360;

export default function mediaBoxTest() {
  describe('mediaBox', () => {
    it('fills the bubble width for a landscape photo', 0, () => {
      const box = mediaBoxFor(SCREEN, 1600, 900, false);
      expect(box.width).assertEqual(mediaThumbWidth(SCREEN));
    });

    // 这一条是那个 bug 本身。
    it('fills the bubble width for a portrait photo too', 0, () => {
      const box = mediaBoxFor(SCREEN, 900, 1600, false);
      expect(box.width).assertEqual(mediaThumbWidth(SCREEN));
    });

    it('fills the bubble width for a square photo', 0, () => {
      const box = mediaBoxFor(SCREEN, 1000, 1000, false);
      expect(box.width).assertEqual(mediaThumbWidth(SCREEN));
    });

    // 尺寸还没到（占位阶段）也要满宽，否则图一到就横向跳一下。
    it('fills the bubble width before the size is known', 0, () => {
      expect(mediaBoxFor(SCREEN, 0, 0, false).width).assertEqual(mediaThumbWidth(SCREEN));
      expect(mediaBoxFor(SCREEN, 0, 0, true).width).assertEqual(mediaThumbWidth(SCREEN));
    });

    // 满宽不能变成"无限高"：极端竖图会把整屏占满，上限仍然要在。
    it('never exceeds the height cap', 0, () => {
      const cap: number = mediaThumbWidth(SCREEN) * MEDIA_MAX_HEIGHT_RATIO;
      for (const h of [1600, 4000, 20000]) {
        expect(mediaBoxFor(SCREEN, 900, h, false).height <= cap + 0.001).assertTrue();
      }
    });

    // 没到上限的图必须保持原始比例，不能被拉伸。
    it('keeps the aspect ratio while under the cap', 0, () => {
      const box = mediaBoxFor(SCREEN, 1600, 900, false);
      const want: number = mediaThumbWidth(SCREEN) / mediaRatio(1600, 900, false);
      expect(Math.abs(box.height - want) < 0.001).assertTrue();
    });

    // 预取器和气泡共用这个函数，像素缓存按"路径 + 目标尺寸"做键——同样的
    // 输入必须给出同样的输出，差一个像素就是多解码一份。
    it('is deterministic', 0, () => {
      const a = mediaBoxFor(SCREEN, 900, 1600, false);
      const b = mediaBoxFor(SCREEN, 900, 1600, false);
      expect(a.width).assertEqual(b.width);
      expect(a.height).assertEqual(b.height);
    });
  });
}
