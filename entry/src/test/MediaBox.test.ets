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

    // 视频不能裁：框必须和画面同比例，否则播放时左右留黑。
    it('keeps a tall video in its true aspect instead of cropping', 0, () => {
      // 9:16 竖屏视频。照片会被压到高度上限并靠 Cover 裁掉多余部分；
      // 视频不行——播放器只会留黑边，所以宽度要跟着收。
      const box = mediaBoxFor(SCREEN, 900, 1600, true);
      const boxRatio: number = box.width / box.height;
      expect(Math.abs(boxRatio - 900 / 1600) < 0.02).assertTrue();
    });

    it('a tall video is narrower than the bubble, a tall photo is not', 0, () => {
      const video = mediaBoxFor(SCREEN, 900, 1600, true);
      const photo = mediaBoxFor(SCREEN, 900, 1600, false);
      expect(photo.width).assertEqual(mediaThumbWidth(SCREEN));
      expect(video.width < photo.width).assertTrue();
    });

    it('a landscape video still fills the bubble width', 0, () => {
      // 高度没到上限，不需要收宽度。
      expect(mediaBoxFor(SCREEN, 1600, 900, true).width).assertEqual(mediaThumbWidth(SCREEN));
    });

    it('video ratio clamp is looser than the photo one', 0, () => {
      // 极端竖屏 1:3。照片夹到 0.56，视频夹到 0.4——视频更贴近真实比例。
      expect(mediaRatio(1000, 3000, false) > mediaRatio(1000, 3000, true)).assertTrue();
    });

    it('video height still respects the cap', 0, () => {
      const cap: number = mediaThumbWidth(SCREEN) * MEDIA_MAX_HEIGHT_RATIO;
      for (const h of [1600, 4000, 20000]) {
        expect(mediaBoxFor(SCREEN, 900, h, true).height <= cap + 0.001).assertTrue();
      }
    });
  });
}
